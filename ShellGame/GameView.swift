// GameView.swift
// SwiftUI container for the active game.
// Hosts the SpriteKit scene + SwiftUI HUD overlay.
// A private Coordinator class bridges SpriteKit delegate callbacks → GameState (main thread safe).

import SwiftUI
import SpriteKit

// MARK: - GameView

struct GameView: View {

    @StateObject private var gameState    = GameState()
    @State       private var scene:        GameScene?
    @State       private var coordinator:  Coordinator?   // retained here; scene holds weak ref
    @State       private var showLevelUp:    Bool = false
    @State       private var watchCueVisible: Bool = false
    @State       private var hintVisible:    Bool = false
    @State       private var hintTask:          Task<Void, Never>? = nil
    @State       private var levelUpAutoTask:   Task<Void, Never>? = nil   // auto-advances after level-up
    @State       private var showScoreboard: Bool = false
    @State       private var sessionEntryID: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {

            // ── Stage background ──────────────────────────────────────────
            casinoBackground

            VStack(spacing: 0) {

                // ── Phase indicator (top) ─────────────────────────────────
                phaseIndicatorSection
                    .padding(.top, 12)

                // ── SpriteKit game canvas ─────────────────────────────────
                GeometryReader { geo in
                    if let scene = scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .frame(width: geo.size.width, height: 310)
                            .onAppear { resizeScene(to: geo.size) }
                    }
                }
                .frame(height: 310)

                // ── Score HUD (bottom) ────────────────────────────────────
                scoreHUD
                    .padding(.top, 10)

                Spacer()
            }

            // ── Level-up flash ────────────────────────────────────────────
            if showLevelUp {
                levelUpBadge
            }

            // ── "WATCH!" anticipation cue ─────────────────────────────────
            if watchCueVisible {
                watchCueBanner
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.4).combined(with: .opacity),
                        removal:   .opacity
                    ))
            }

            // ── Hint button (fades in after 2s during .choosing) ─────────
            if hintVisible {
                hintButton
                    .transition(.opacity.animation(.easeIn(duration: 0.35)))
            }

            // ── Result overlay ────────────────────────────────────────────
            if gameState.phase == .result {
                resultOverlay
                    .transition(.asymmetric(
                        insertion:  .opacity.combined(with: .scale(scale: 0.88)),
                        removal:    .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.phase)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    levelUpAutoTask?.cancel()
                    levelUpAutoTask = nil
                    submitSessionScores()
                    SoundManager.shared.stopAmbient()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
        }
        .onAppear(perform: setupScene)
        .onChange(of: gameState.phase) { newPhase in
            // Feature 4 + 5: phase-reactive music — shuffle percussion, choosing tension, L30 survival
            if newPhase == .shuffling && gameState.level == 30 && gameState.survivalCount >= 2 {
                SoundManager.shared.updateSurvivalCount(gameState.survivalCount)
            } else {
                SoundManager.shared.updatePhase(newPhase)
            }

            // Hint timer: start 2s countdown on .choosing; cancel on any other phase
            hintTask?.cancel()
            hintTask = nil
            if newPhase == .choosing {
                hintTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.35)) { hintVisible = true }
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { hintVisible = false }
            }

            if newPhase == .placing {
                // Haptic: ball thud when cup covers it (slight delay matches animation)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            if newPhase == .shuffling {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                    watchCueVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        watchCueVisible = false
                    }
                }
            }
        }
        .onChange(of: gameState.isCorrect) { result in
            guard let result else { return }
            if result {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        .onChange(of: gameState.level) { _ in
            showLevelUp = true
            SoundManager.shared.playLevelUp()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showLevelUp = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            scene?.isPaused = true
            submitSessionScores()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            scene?.isPaused = false
            // If the player missed the shuffle while away, restart the round cleanly
            if [.placing, .shuffling, .choosing].contains(gameState.phase) {
                scene?.resetForNewRound()
                gameState.resetToIdle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { startRound() }
            }
        }
        .fullScreenCover(isPresented: $showScoreboard) {
            ScoreboardView(
                sessionScore:    gameState.score,
                sessionLevel:    gameState.level,
                sessionSurvival: gameState.survivalCount,
                sessionEntryID:  sessionEntryID,
                onHome: {
                    showScoreboard = false
                    // Small delay so the cover dismiss animation completes before nav pop
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        dismiss()
                    }
                }
            )
        }
    }

    // MARK: - Level-Up Badge

    private var levelUpBadge: some View {
        VStack(spacing: 6) {
            Text("LEVEL UP!")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.black)
            Text("Level \(gameState.level) 🔥")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.75))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .orange.opacity(0.65), radius: 20, y: 6)
        .transition(.asymmetric(
            insertion:  .scale(scale: 0.5).combined(with: .opacity),
            removal:    .scale(scale: 1.2).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.38, dampingFraction: 0.6), value: showLevelUp)
    }

    // MARK: - Background

    private var casinoBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.03, blue: 0.18),
                Color(red: 0.11, green: 0.05, blue: 0.26),
                Color(red: 0.05, green: 0.03, blue: 0.18)
            ],
            startPoint: .top,
            endPoint:   .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Phase Indicator

    private var phaseIndicatorSection: some View {
        VStack(spacing: 8) {
            phaseVisual
            hostMessageBubble
        }
    }

    private var phaseVisual: some View {
        ZStack {
            Circle()
                .fill(phaseColor.opacity(0.20))
                .frame(width: 80, height: 80)
                .blur(radius: 12)

            Image(systemName: phaseIcon)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(phaseColor)
                .shadow(color: phaseColor.opacity(0.85), radius: 12)
        }
        .frame(width: 74, height: 74)
        .animation(.easeInOut(duration: 0.28), value: gameState.phase)
    }

    private var phaseIcon: String {
        switch gameState.phase {
        case .idle, .placing: return "circle.fill"
        case .shuffling:      return "flame.fill"
        case .choosing:       return "eye.fill"
        default:              return "checkmark.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch gameState.phase {
        case .idle, .placing: return Color(red: 1.0, green: 0.85, blue: 0.15)
        case .shuffling:      return .orange
        case .choosing:       return Color(red: 0.30, green: 0.92, blue: 0.52)
        default:              return .yellow
        }
    }

    private var hostMessageBubble: some View {
        Text(gameState.hostMessage)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Color.yellow.opacity(0.32), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 22)
            .animation(.easeInOut(duration: 0.22), value: gameState.hostMessage)
    }

    /// Full-screen stamp that flashes briefly when the shuffle starts.
    private var watchCueBanner: some View {
        Text("WATCH!")
            .font(.system(size: 56, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .shadow(color: .orange.opacity(0.85), radius: 18, y: 4)
    }

    // MARK: - Hint Button

    private var hintButton: some View {
        VStack {
            Spacer()
            Button {
                hintTask?.cancel()
                withAnimation(.easeOut(duration: 0.18)) { hintVisible = false }
                AdManager.shared.showRewardedAd {
                    scene?.peekBall()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                HStack(spacing: 7) {
                    Text("💡")
                        .font(.system(size: 16))
                    Text("Hint")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(Color(red: 1, green: 0.93, blue: 0.28))
                        .shadow(color: Color.yellow.opacity(0.55), radius: 10, y: 3)
                )
            }
            .padding(.bottom, 148)   // sits just above the score HUD
        }
    }

    // MARK: - Score HUD

    private var scoreHUD: some View {
        HStack(spacing: 0) {
            hudCell(label: "SCORE",  value: "\(gameState.score)")
            hudDivider
            hudCell(label: "STREAK", value: formattedStreak)
            hudDivider
            if gameState.level == 30 {
                hudCell(label: "SURVIVED", value: "\(gameState.survivalCount)")
            } else {
                hudCell(label: "LEVEL", value: "L\(gameState.level)")
            }
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.yellow.opacity(0.65), .orange.opacity(0.35)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .padding(.horizontal, 18)
    }

    private func hudCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35), value: value)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .tracking(1.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.35))
            .frame(width: 1, height: 44)
    }

    private var formattedStreak: String {
        let s = gameState.streak
        if s >= 5 { return "🔥\(s)" }
        if s >= 3 { return "⭐\(s)" }
        return "\(s)"
    }

    // MARK: - Result Overlay

    private var resultOverlay: some View {
        // Derive display state from published values
        let isWin      = gameState.isCorrect == true
        let isLevelUp  = gameState.leveledUp
        let isMaxLevel = gameState.level == 30

        let emoji     = isLevelUp ? "🎊" : isWin ? "✨" : "😮"
        let headline  = isLevelUp ? "Level Up!" : isWin ? "You Found It!" : "Not Quite!"
        let ctaLabel  = isLevelUp ? "Level \(gameState.level) →" : isWin ? "Play Again" : "Try Again"
        let ctaIcon   = isLevelUp ? "star.circle.fill" : isWin ? "arrow.counterclockwise" : "arrow.counterclockwise"
        let ctaColors: [Color] = isLevelUp
            ? [Color(red: 1.0, green: 0.85, blue: 0.0), .orange]
            : isWin
                ? [.yellow, Color(red: 1, green: 0.72, blue: 0)]
                : [Color(red: 0.55, green: 0.10, blue: 0.80), Color(red: 0.35, green: 0.05, blue: 0.55)]

        return ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()
                .onAppear {
                    // Fire interstitial ad after every 3 cumulative losses
                    if !isWin && gameState.lossCount >= 3 {
                        gameState.consumeAdTrigger()
                        Task { await AdManager.shared.requestATTThenShowInterstitial() }
                    }
                    // Auto-advance to next level after 2s on level-up (no tap required)
                    if isLevelUp {
                        levelUpAutoTask?.cancel()
                        levelUpAutoTask = Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run { handlePlayAgain() }
                        }
                    }
                }

            VStack(spacing: 20) {
                // Result emoji
                Text(emoji)
                    .font(.system(size: 74))

                // Result headline
                Text(headline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(isWin ? .yellow : Color(red: 1, green: 0.9, blue: 0.9))

                // Level-up badge (shows new level number)
                if isLevelUp && !isMaxLevel {
                    HStack(spacing: 6) {
                        Text("Level \(gameState.level - 1)")
                            .strikethrough()
                            .foregroundColor(.white.opacity(0.45))
                        Image(systemName: "arrow.right")
                            .foregroundColor(.yellow)
                        Text("Level \(gameState.level)")
                            .foregroundColor(.yellow)
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 15, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Score delta badge
                if isWin && gameState.lastScoreDelta > 0 {
                    Text("+\(gameState.lastScoreDelta) pts")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }

                // Endless mode survival badge (L30 wins)
                if isWin && gameState.level == 30 && gameState.survivalCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow)
                        Text("Survived \(gameState.survivalCount)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.14))
                    .clipShape(Capsule())
                }

                // Primary CTA button
                Button(action: handlePlayAgain) {
                    HStack(spacing: 8) {
                        Image(systemName: ctaIcon)
                        Text(ctaLabel)
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(isWin ? .black : .white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: ctaColors,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: (isLevelUp ? Color.orange : isWin ? Color.orange : Color.purple).opacity(0.55),
                            radius: 12, y: 4)
                }

                Button("Main Menu") {
                    levelUpAutoTask?.cancel()
                    levelUpAutoTask = nil
                    submitSessionScores()
                    SoundManager.shared.stopAmbient()
                    if gameState.score > 0 {
                        sessionEntryID = ScoreStore.shared.save(
                            score: gameState.score,
                            level: gameState.level,
                            survivalCount: gameState.survivalCount
                        )
                        showScoreboard = true
                    } else {
                        dismiss()
                    }
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))

                // Remove Ads upsell — shown on loss, hidden once purchased
                if !isWin && !AdManager.shared.adsRemoved {
                    VStack(spacing: 6) {
                        Button {
                            Task { await PurchaseManager.shared.purchaseRemoveAds() }
                        } label: {
                            Text("Remove Ads — $1.99")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(red: 1, green: 0.85, blue: 0.35))
                        }
                        Button {
                            Task { await PurchaseManager.shared.restorePurchases() }
                        } label: {
                            Text("Restore Purchase")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.05, blue: 0.24),
                            Color(red: 0.14, green: 0.08, blue: 0.34)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(
                                LinearGradient(colors: [.yellow.opacity(0.75), .purple.opacity(0.45)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.55), radius: 28)
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Setup & Coordination

    private func setupScene() {
        let s = GameScene(size: CGSize(width: 390, height: 310))
        s.level = gameState.level   // must be set before didMove(to:) so cups are built for the right level
        let coord = Coordinator(gameState: gameState, scene: s)
        s.shellDelegate = coord
        coordinator = coord
        scene = s

        SoundManager.shared.startGameAmbient(level: gameState.level)   // Feature 2

        // First round starts after the scene has a moment to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            startRound()
        }
    }

    private func resizeScene(to containerSize: CGSize) {
        // Keep scene aspect-fill inside the GeometryReader frame
        scene?.size = CGSize(width: containerSize.width, height: 310)
    }

    private func startRound() {
        let isFTUE = gameState.isFTUERound   // capture before beginRound() clears it
        gameState.beginRound()
        scene?.level = gameState.level
        scene?.isFTUERound = isFTUE
        scene?.survivalBonus = gameState.survivalCount
        // Feature 2: switch music tier if level crossed a boundary (no-op if same tier)
        SoundManager.shared.startGameAmbient(level: gameState.level)
        scene?.placeBall(atCupIndex: gameState.correctCupIndex)
    }

    private func submitSessionScores() {
        GameCenterManager.shared.submitHighScore(gameState.highScore)
        GameCenterManager.shared.submitSurvivalCount(gameState.survivalCount)

        let playerName = UserDefaults.standard.string(forKey: "cq_player_name") ?? "Anonymous"
        let modeString: String = {
            switch gameState.mode {
            case .solo:     return "solo"
            case .gauntlet: return "gauntlet"
            case .daily:    return "daily"
            }
        }()
        ScoreSubmissionService.shared.submit(
            playerName: playerName,
            score: gameState.score,
            mode: modeString,
            level: gameState.level
        )
    }

    private func handlePlayAgain() {
        levelUpAutoTask?.cancel()
        levelUpAutoTask = nil
        scene?.level = gameState.level
        scene?.resetForNewRound()
        gameState.resetToIdle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            startRound()
        }
    }
}

// MARK: - Coordinator (SpriteKit → SwiftUI bridge)

/// Retained by GameView via @State; held weakly by GameScene.
/// All callbacks are dispatched to the main thread before touching GameState.
private final class Coordinator: ShellGameSceneDelegate {
    private let gameState: GameState
    private weak var scene: GameScene?

    init(gameState: GameState, scene: GameScene) {
        self.gameState = gameState
        self.scene     = scene
    }

    func sceneDidFinishPlacing() {
        DispatchQueue.main.async {
            self.gameState.didFinishPlacing()
            // Brief pause before shuffle so player registers the cup-covering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                self.scene?.performShuffle()
            }
        }
    }

    func sceneDidFinishShuffling() {
        DispatchQueue.main.async {
            self.gameState.didFinishShuffling()
        }
    }

    func sceneDidRevealCup(_ cupIndex: Int) {
        DispatchQueue.main.async {
            self.gameState.playerTappedCup(cupIndex)
        }
    }
}
