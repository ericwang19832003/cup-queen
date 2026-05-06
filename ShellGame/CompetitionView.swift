// CompetitionView.swift
// Cup Queen — Full-screen competition / duel UI.
//
// Architecture:
//   CompetitionView          — root, phase router, lifecycle wiring
//   MatchmakingView          — spinner + cancel
//   CountdownView            — 3 → 2 → 1 → GO!
//   DuelGameView             — SpriteKit canvas + duel HUD + round result overlay
//   MatchResultView          — win/loss final screen
//   DuelCoordinator          — SpriteKit → SwiftUI bridge (ShellGameSceneDelegate)
//
// Swift 5.9+, iOS 16+, no external dependencies.

import SwiftUI
import SpriteKit

// MARK: - CompetitionView

struct CompetitionView: View {

    @StateObject private var matchState = MatchState()
    @Environment(\.dismiss) private var dismiss

    /// Set to true the moment startMatchmaking() is called.
    /// If phase returns to .idle after that, matchmaking failed.
    @State private var matchmakingStarted = false

    var body: some View {
        ZStack {
            casinoBackground

            Group {
                switch matchState.phase {

                case .idle:
                    if matchmakingStarted {
                        // Matchmaking failed (e.g., Game Center not authenticated)
                        MatchmakingUnavailableView { dismiss() }
                    } else {
                        // Transient — onAppear kicks off matchmaking immediately.
                        Color.clear
                    }

                case .matchmaking:
                    MatchmakingView {
                        GameCenterMatchManager.shared.cancelMatchmaking()
                        dismiss()
                    }

                case .countdown:
                    CountdownView {
                        // Countdown finished — signal ready for round 1
                        let nextRound = matchState.currentRound + 1
                        GameCenterMatchManager.shared.sendMessage(.readyForRound(nextRound))
                    }

                case .roundActive, .roundResult:
                    DuelGameView(matchState: matchState)

                case .matchResult(let winner):
                    MatchResultView(
                        winner: winner,
                        competitionWins: matchState.competitionWins,
                        onRematch: {
                            matchState.reset()
                            GameCenterMatchManager.shared.startMatchmaking()
                        },
                        onMainMenu: {
                            GameCenterMatchManager.shared.disconnect()
                            dismiss()
                        }
                    )

                case .disconnected(let forfeitAt):
                    DisconnectedView(forfeitAt: forfeitAt)
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.28)))
        }
        .animation(.easeInOut(duration: 0.28), value: matchState.phase.stableID)
        .ignoresSafeArea()
        .onAppear {
            matchmakingStarted = true
            GameCenterMatchManager.shared.matchState = matchState
            GameCenterMatchManager.shared.startMatchmaking()
            SoundManager.shared.startCompetitionAmbient()   // Feature 3
        }
        // Background → forfeit
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            GameCenterMatchManager.shared.sendMessage(.forfeit)
            GameCenterMatchManager.shared.disconnect()
        }
        // Foregrounding mid-match: local player lost focus — forfeit them
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if matchState.phase.isActiveRound {
                matchState.forfeitMatch(winner: .remote)
            }
        }
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
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - MatchmakingView

private struct MatchmakingView: View {

    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Spinning crown
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.12))
                    .frame(width: 110, height: 110)
                    .blur(radius: 16)

                Image(systemName: "crown.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.8), radius: 14)
            }
            .rotationEffect(.degrees(0))   // static icon; spinner below

            // Activity spinner
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.yellow)

            VStack(spacing: 8) {
                Text("Finding Opponent...")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Searching for a worthy challenger")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    )
            }
            .padding(.bottom, 48)
        }
    }
}

// MARK: - MatchmakingUnavailableView

private struct MatchmakingUnavailableView: View {

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(.yellow.opacity(0.7))
                .shadow(color: .yellow.opacity(0.5), radius: 14)

            VStack(spacing: 10) {
                Text("Game Center Required")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Sign in to Game Center in Settings\nto challenge other players.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Go Back")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 44)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    )
            }
            .padding(.bottom, 52)
        }
        .padding(.horizontal, 36)
    }
}

// MARK: - CountdownView

private struct CountdownView: View {

    let onFinished: () -> Void

    @State private var countValue: Int = 3
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                // Glow halo
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                    .scaleEffect(scale)

                Text(countLabel)
                    .font(.system(size: countValue == 0 ? 64 : 96, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .orange.opacity(0.8), radius: 18, y: 4)
                    .scaleEffect(scale)
                    .opacity(opacity)
            }

            Spacer()

            Text("Get ready to duel!")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .padding(.bottom, 60)
        }
        .onAppear { runCountdown() }
    }

    private var countLabel: String {
        countValue == 0 ? "GO!" : "\(countValue)"
    }

    private var accentColor: Color {
        countValue == 0 ? .green : .yellow
    }

    private func runCountdown() {
        tick(at: 0, value: 3)
    }

    private func tick(at delay: TimeInterval, value: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            countValue = value
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                scale   = 1.0
                opacity = 1.0
            }
            UIImpactFeedbackGenerator(style: value == 0 ? .heavy : .medium).impactOccurred()

            // Fade out after 0.7s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.25)) {
                    scale   = 0.75
                    opacity = 0.0
                }
            }

            if value > 0 {
                tick(at: delay + 1.0, value: value - 1)
            } else {
                // "GO!" shown — fire callback after brief hold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    onFinished()
                }
            }
        }
    }
}

// MARK: - DuelGameView

private struct DuelGameView: View {

    @ObservedObject var matchState: MatchState

    @State private var scene:       GameScene?
    @State private var coordinator: DuelCoordinator?
    @State private var correctCupIndex: Int = 0
    @State private var isInteractive:   Bool = false
    @State private var showRoundResult: Bool = false

    // Round-result state derived from phase
    @State private var roundResultWinner: PlayerSide = .local

    // Ready-handshake: track whether both sides are ready
    @State private var localReady:  Bool = false
    @State private var remoteReady: Bool = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {

                // ── Opponent wins HUD ─────────────────────────────────────
                winsRow(wins: matchState.remoteRoundWins, label: "OPPONENT", side: .remote)
                    .padding(.top, 56)

                Spacer()

                // ── SpriteKit canvas ──────────────────────────────────────
                GeometryReader { geo in
                    if let scene = scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .frame(width: geo.size.width, height: 310)
                            .allowsHitTesting(isInteractive)
                    }
                }
                .frame(height: 310)

                Spacer()

                // ── Local wins HUD ────────────────────────────────────────
                winsRow(wins: matchState.localRoundWins, label: "YOU", side: .local)
                    .padding(.bottom, 52)
            }

            // ── Round result overlay ──────────────────────────────────────
            if showRoundResult {
                roundResultOverlay
                    .transition(.asymmetric(
                        insertion:  .opacity.combined(with: .scale(scale: 0.88)),
                        removal:    .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showRoundResult)
        .onAppear { setupScene() }
        // Phase changes
        .onChange(of: matchState.phase.stableID) { _ in
            handlePhaseChange()
        }
        // Opponent ready notification
        .onReceive(NotificationCenter.default.publisher(for: .duelOpponentReadyForRound)) { notif in
            guard let round = notif.userInfo?["round"] as? Int,
                  round == matchState.currentRound + 1 else { return }
            remoteReady = true
            checkBothReady()
        }
        // Non-host seed notification
        .onReceive(NotificationCenter.default.publisher(for: .duelShuffleSeedReceived)) { notif in
            guard let seed = notif.userInfo?["seed"] as? UInt64 else { return }
            scene?.shuffleSeed = seed
        }
    }

    // MARK: - Wins Row

    private func winsRow(wins: Int, label: String, side: PlayerSide) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .tracking(2)

            HStack(spacing: 8) {
                ForEach(0..<matchState.winsNeeded, id: \.self) { i in
                    Circle()
                        .fill(i < wins ? Color.yellow : Color.white.opacity(0.18))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    i < wins ? Color.orange.opacity(0.6) : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: i < wins ? Color.yellow.opacity(0.7) : .clear,
                            radius: 5
                        )
                        .animation(.spring(response: 0.35), value: wins)
                }
            }
        }
    }

    // MARK: - Round Result Overlay

    private var roundResultOverlay: some View {
        let isLocalWin = roundResultWinner == .local
        return ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(isLocalWin ? "⚡" : "😮")
                    .font(.system(size: 68))

                Text(isLocalWin ? "You got it!" : "They got it!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(isLocalWin ? .yellow : Color(red: 1, green: 0.9, blue: 0.9))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.05, blue: 0.24),
                            Color(red: 0.14, green: 0.08, blue: 0.34)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.yellow.opacity(0.7), .purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 24)
        }
    }

    // MARK: - Setup

    private func setupScene() {
        let s = GameScene(size: CGSize(width: 390, height: 310))
        s.level = 1   // visual level; actual config injected via LevelConfig.competition
        let coord = DuelCoordinator(
            scene: s,
            onShuffleFinished: { isInteractive = true },
            onCupRevealed: handleCupRevealed
        )
        s.shellDelegate = coord
        coordinator = coord
        scene = s

        // Kick off round 1 handshake once scene is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            initiateRoundHandshake()
        }
    }

    private func initiateRoundHandshake() {
        let nextRound = matchState.currentRound + 1
        localReady  = true
        remoteReady = false
        GameCenterMatchManager.shared.sendMessage(.readyForRound(nextRound))
        checkBothReady()
    }

    private func checkBothReady() {
        guard localReady && remoteReady else { return }
        localReady  = false
        remoteReady = false
        beginRound()
    }

    // MARK: - Round lifecycle

    private func beginRound() {
        isInteractive = false
        showRoundResult = false

        // Host generates and broadcasts the seed; non-host receives via notification
        if GameCenterMatchManager.shared.isHost {
            let seed = UInt64.random(in: 1...UInt64.max)
            scene?.shuffleSeed = seed
            GameCenterMatchManager.shared.sendMessage(.shuffleSeed(seed))
        }
        // (Non-host seed set via .onReceive above)

        correctCupIndex = Int.random(in: 0..<4)   // 4 cups in competition mode
        matchState.startRound()
        scene?.resetForNewRound()
        scene?.placeBall(atCupIndex: correctCupIndex)
    }

    private func handleCupRevealed(_ tappedIndex: Int) {
        guard isInteractive else { return }
        isInteractive = false

        scene?.revealTappedCup(tappedIndex)

        if tappedIndex == correctCupIndex {
            // Local player won this round
            SoundManager.shared.playWin()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            GameCenterMatchManager.shared.sendMessage(.roundWon(by: .local))
            matchState.recordRoundWin(for: .local)
        } else {
            // Wrong tap — opponent may still win; wait for phase change
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func handlePhaseChange() {
        switch matchState.phase {

        case .roundResult(let winner):
            roundResultWinner = winner
            withAnimation { showRoundResult = true }
            // Auto-advance after 1.8 s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard case .roundResult = matchState.phase else { return }
                withAnimation { showRoundResult = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    initiateRoundHandshake()
                }
            }

        case .matchResult:
            withAnimation { showRoundResult = false }

        default:
            break
        }
    }
}

// MARK: - MatchResultView

private struct MatchResultView: View {

    let winner: PlayerSide
    let competitionWins: Int
    let onRematch: () -> Void
    let onMainMenu: () -> Void

    var body: some View {
        let isWin = winner == .local

        VStack(spacing: 24) {
            Spacer()

            // Trophy / grimace
            Text(isWin ? "👑" : "😤")
                .font(.system(size: 84))

            Text(isWin ? "You Won!" : "They Won")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(isWin ? .yellow : Color(red: 1, green: 0.85, blue: 0.85))
                .shadow(color: isWin ? .yellow.opacity(0.6) : .clear, radius: 12)

            // Competition win tally (only meaningful on win)
            if isWin {
                HStack(spacing: 7) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.yellow)
                    Text("Total Wins: \(competitionWins)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.yellow.opacity(0.14))
                .clipShape(Capsule())
            }

            Spacer()

            VStack(spacing: 14) {
                // Rematch
                Button(action: onRematch) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Rematch")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.55), radius: 12, y: 4)
                }

                // Main menu
                Button("Main Menu", action: onMainMenu)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.bottom, 52)
        }
        .onAppear {
            if !isWin {
                Task { await AdManager.shared.requestATTThenShowInterstitial() }
            }
            if isWin {
                SoundManager.shared.playWin()
            } else {
                SoundManager.shared.playLoss()
            }
        }
    }
}

// MARK: - DisconnectedView

private struct DisconnectedView: View {

    let forfeitAt: Date

    @State private var secondsLeft: Int = 10

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(.orange)
                .shadow(color: .orange.opacity(0.7), radius: 12)

            Text("Opponent disconnected...")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Forfeiting in \(max(0, secondsLeft))s")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35), value: secondsLeft)

            Spacer()
        }
        .onAppear { startCountdown() }
    }

    private func startCountdown() {
        let total = max(0, Int(forfeitAt.timeIntervalSinceNow.rounded(.up)))
        secondsLeft = total
        guard total > 0 else { return }

        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) + 1) {
                secondsLeft = max(0, secondsLeft - 1)
            }
        }
    }
}

// MARK: - DuelCoordinator (SpriteKit → SwiftUI bridge)

/// Retained by DuelGameView via @State; held weakly by GameScene.
/// All callbacks dispatch to the main thread.
private final class DuelCoordinator: ShellGameSceneDelegate {

    private weak var scene: GameScene?
    private let onShuffleFinished: () -> Void
    private let onCupRevealed: (Int) -> Void

    init(
        scene: GameScene,
        onShuffleFinished: @escaping () -> Void,
        onCupRevealed: @escaping (Int) -> Void
    ) {
        self.scene            = scene
        self.onShuffleFinished = onShuffleFinished
        self.onCupRevealed    = onCupRevealed
    }

    func sceneDidFinishPlacing() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.scene?.performShuffle()
        }
    }

    func sceneDidFinishShuffling() {
        DispatchQueue.main.async { [weak self] in
            self?.onShuffleFinished()
        }
    }

    func sceneDidRevealCup(_ cupIndex: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.onCupRevealed(cupIndex)
        }
    }
}

// MARK: - MatchPhase helpers

private extension MatchPhase {

    /// Stable string ID for driving SwiftUI `.onChange` without Equatable conformance.
    var stableID: String {
        switch self {
        case .idle:                return "idle"
        case .matchmaking:         return "matchmaking"
        case .countdown:           return "countdown"
        case .roundActive:         return "roundActive"
        case .roundResult(let w):  return "roundResult-\(w.rawValue)"
        case .matchResult(let w):  return "matchResult-\(w.rawValue)"
        case .disconnected:        return "disconnected"
        }
    }

    /// True while a round is in progress (used to detect backgrounding mid-match).
    var isActiveRound: Bool {
        switch self {
        case .roundActive, .roundResult, .countdown: return true
        default: return false
        }
    }
}
