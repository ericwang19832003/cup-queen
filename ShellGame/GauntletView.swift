// GauntletView.swift
// Single-life L1→L7 gauntlet run. Reuses GameScene + existing animation stack.
// Uses GameState(mode: .gauntlet) — solo wins/level are never modified.

import SwiftUI
import SpriteKit

struct GauntletView: View {
    @StateObject private var gameState = GameState(mode: .gauntlet)
    @State private var scene: GameScene?
    @State private var coordinator: GauntletCoordinator?
    @State private var showLevelUp = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            casinoBackground

            VStack(spacing: 0) {
                phaseIndicator.padding(.top, 56)

                GeometryReader { geo in
                    if let scene = scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .frame(width: geo.size.width, height: 310)
                    }
                }
                .frame(height: 310)

                gauntletHUD.padding(.top, 10)
                Spacer()
            }

            if showLevelUp { levelUpBadge }
            if gameState.phase == .result || gameState.gauntletOver || gameState.gauntletComplete {
                resultOverlay
            }

            // X dismiss button top-right
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(14)
                    }
                }
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.phase)
        .onAppear(perform: setupScene)
        .onChange(of: gameState.gauntletLevel) { newLevel in
            guard newLevel > 1 && !gameState.gauntletComplete else { return }
            showLevelUp = true
            SoundManager.shared.playLevelUp()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { showLevelUp = false }
        }
    }

    // MARK: - Background
    private var casinoBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.03, blue: 0.18),
                     Color(red: 0.11, green: 0.05, blue: 0.26),
                     Color(red: 0.05, green: 0.03, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    // MARK: - Phase Indicator
    private var phaseIndicator: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(phaseColor.opacity(0.20)).frame(width: 80, height: 80).blur(radius: 12)
                Image(systemName: phaseIcon)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(phaseColor)
                    .shadow(color: phaseColor.opacity(0.85), radius: 12)
            }
            .frame(width: 74, height: 74)
            Text(gameState.hostMessage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Color.yellow.opacity(0.32), lineWidth: 1))
                )
                .padding(.horizontal, 22)
        }
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

    // MARK: - Gauntlet HUD
    private var gauntletHUD: some View {
        VStack(spacing: 8) {
            // Level progress pips
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { lvl in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(lvl < gameState.gauntletLevel
                              ? Color.yellow
                              : lvl == gameState.gauntletLevel
                                ? Color.yellow.opacity(0.55)
                                : Color.white.opacity(0.15))
                        .frame(height: 6)
                }
            }
            .padding(.horizontal, 32)

            HStack(spacing: 0) {
                hudCell(label: "SCORE", value: "\(gameState.score)")
                Rectangle().fill(Color.yellow.opacity(0.35)).frame(width: 1, height: 44)
                hudCell(label: "RUN", value: "L\(min(gameState.gauntletLevel, 7))/7")
                Rectangle().fill(Color.yellow.opacity(0.35)).frame(width: 1, height: 44)
                hudCell(label: "STREAK", value: "\(gameState.streak)")
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.38))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(LinearGradient(
                            colors: [.yellow.opacity(0.65), .orange.opacity(0.35)],
                            startPoint: .leading, endPoint: .trailing), lineWidth: 1.5))
            )
            .padding(.horizontal, 18)
        }
    }

    private func hudCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55)).tracking(1.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Level Up Badge
    private var levelUpBadge: some View {
        let prev = max(gameState.gauntletLevel - 1, 1)
        let cur  = gameState.gauntletLevel
        return VStack(spacing: 6) {
            Text("LEVEL UP!").font(.system(size: 32, weight: .black, design: .rounded)).foregroundColor(.black)
            Text("L\(prev) → L\(cur) 🔥")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.black.opacity(0.75))
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .orange.opacity(0.65), radius: 20, y: 6)
        .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal:   .scale(scale: 1.2).combined(with: .opacity)))
    }

    // MARK: - Result Overlay
    private var resultOverlay: some View {
        let complete = gameState.gauntletComplete
        let emoji    = complete ? "🏆" : "💀"
        let headline = complete ? "PERFECT RUN!" : "Run Over"
        let sub      = complete
            ? "You cleared all 7 levels!"
            : "Fell at Level \(gameState.gauntletLevel)"

        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onAppear {
                    GameCenterManager.shared.submitGauntletScore(gameState.score)
                }

            VStack(spacing: 20) {
                Text(emoji).font(.system(size: 74))
                Text(headline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(complete ? .yellow : Color(red: 1, green: 0.9, blue: 0.9))
                Text(sub)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

                Text("\(gameState.score) pts")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                if gameState.score == gameState.bestGauntlet && gameState.score > 0 {
                    Text("New Personal Best! 🎉")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow)
                }
                Button(action: { dismiss() }) {
                    Text(complete ? "Run Again" : "Try Again")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 36).padding(.vertical, 15)
                        .background(LinearGradient(
                            colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Capsule())
                }
                Button("Done") { dismiss() }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.50))
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.05, blue: 0.24),
                                                  Color(red: 0.14, green: 0.08, blue: 0.34)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(LinearGradient(colors: [.yellow.opacity(0.75), .purple.opacity(0.45)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1.5))
            )
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Setup
    private func setupScene() {
        let s = GameScene(size: CGSize(width: 390, height: 310))
        s.level = 1
        let coord = GauntletCoordinator(gameState: gameState, scene: s)
        s.shellDelegate = coord
        coordinator = coord
        scene = s
        SoundManager.shared.startGameAmbient(level: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { startRound() }
    }

    private func startRound() {
        let isFTUE = gameState.isFTUERound
        gameState.beginRound()
        scene?.level = gameState.gauntletLevel
        scene?.isFTUERound = isFTUE
        scene?.placeBall(atCupIndex: gameState.correctCupIndex)
    }
}

// MARK: - Gauntlet Coordinator
private final class GauntletCoordinator: ShellGameSceneDelegate {
    private let gameState: GameState
    private weak var scene: GameScene?
    init(gameState: GameState, scene: GameScene) { self.gameState = gameState; self.scene = scene }

    func sceneDidFinishPlacing() {
        DispatchQueue.main.async {
            self.gameState.didFinishPlacing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                self.scene?.performShuffle()
            }
        }
    }
    func sceneDidFinishShuffling() {
        DispatchQueue.main.async { self.gameState.didFinishShuffling() }
    }
    func sceneDidRevealCup(_ cupIndex: Int) {
        DispatchQueue.main.async {
            self.gameState.playerTappedCup(cupIndex)
            // After a non-terminal gauntlet win, advance to next level
            if self.gameState.isCorrect == true &&
               !self.gameState.gauntletOver &&
               !self.gameState.gauntletComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.scene?.level = self.gameState.gauntletLevel
                    self.scene?.resetForNewRound()
                    self.gameState.resetToIdle()
                    SoundManager.shared.startGameAmbient(level: self.gameState.gauntletLevel)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                        let isFTUE = self.gameState.isFTUERound
                        self.gameState.beginRound()
                        self.scene?.level = self.gameState.gauntletLevel
                        self.scene?.isFTUERound = isFTUE
                        self.scene?.placeBall(atCupIndex: self.gameState.correctCupIndex)
                    }
                }
            }
        }
    }
}
