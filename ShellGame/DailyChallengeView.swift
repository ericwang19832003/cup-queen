// DailyChallengeView.swift
// One fixed-seed puzzle per UTC day. Same shuffle for all players worldwide.
// One attempt per day — no retry.

import SwiftUI
import SpriteKit

struct DailyChallengeView: View {
    @StateObject private var gameState = GameState(mode: .daily)
    @State private var scene: GameScene?
    @State private var coordinator: DailyCoordinator?
    @State private var alreadyAttempted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            casinoBackground
            if alreadyAttempted {
                alreadyAttemptedOverlay
            } else {
                gameContent
                if gameState.phase == .result { resultOverlay }
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
        .onAppear {
            alreadyAttempted = gameState.isDailyAttempted
            if !alreadyAttempted { setupScene() }
        }
    }

    private var casinoBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.06, blue: 0.20),
                     Color(red: 0.04, green: 0.12, blue: 0.30),
                     Color(red: 0.02, green: 0.06, blue: 0.20)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    // MARK: - Already Attempted
    private var alreadyAttemptedOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("📅").font(.system(size: 72))
            Text("Already Played Today")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Come back tomorrow for a new puzzle.")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            if gameState.dailyStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundColor(.orange)
                    Text("\(gameState.dailyStreak)-day streak")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.72, blue: 0.20))
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 48).padding(.vertical, 15)
                .background(LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Game Content
    private var gameContent: some View {
        VStack(spacing: 0) {
            dailyHeader.padding(.top, 56)
            Spacer().frame(height: 8)

            Text(gameState.hostMessage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.40), lineWidth: 1)))
                .padding(.horizontal, 22)

            GeometryReader { geo in
                if let scene = scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])
                        .frame(width: geo.size.width, height: 310)
                }
            }
            .frame(height: 310)
            Spacer()
        }
    }

    private var dailyHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00))
                .shadow(color: Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.70), radius: 10)
            Text("DAILY CHALLENGE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.80))
                .tracking(4)
        }
    }

    // MARK: - Result Overlay
    private var resultOverlay: some View {
        let won = gameState.isCorrect == true
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onAppear {
                    gameState.recordDailyAttempt(won: won)
                    GameCenterManager.shared.submitDailyScore(won ? 1 : 0)
                }
            VStack(spacing: 20) {
                Text(won ? "🎯" : "😮").font(.system(size: 74))
                Text(won ? "You Found It!" : "Better Luck Tomorrow")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(won ? .yellow : .white)
                if won {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundColor(.orange)
                        Text("\(gameState.dailyStreak)-day streak")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.72, blue: 0.20))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 48).padding(.vertical, 15)
                    .background(LinearGradient(
                        colors: [.yellow, Color(red: 1, green: 0.72, blue: 0)],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.08, blue: 0.24),
                                                  Color(red: 0.04, green: 0.12, blue: 0.34)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.50), lineWidth: 1.5))
            )
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Setup
    private func setupScene() {
        let s = GameScene(size: CGSize(width: 390, height: 310))
        s.level = 4   // 4-cup layout matching daily config
        let seed = GameState.dailySeed
        let dailyCorrectCup = Int(seed % 4)
        let coord = DailyCoordinator(gameState: gameState, scene: s,
                                     dailySeed: seed, correctCup: dailyCorrectCup)
        s.shellDelegate = coord
        coordinator = coord
        scene = s
        SoundManager.shared.startGameAmbient(level: 4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            gameState.beginRound()
            s.placeBall(atCupIndex: dailyCorrectCup)
        }
    }
}

// MARK: - Daily Coordinator
private final class DailyCoordinator: ShellGameSceneDelegate {
    private let gameState: GameState
    private weak var scene: GameScene?
    private let dailySeed: UInt64
    private let correctCup: Int

    init(gameState: GameState, scene: GameScene, dailySeed: UInt64, correctCup: Int) {
        self.gameState = gameState; self.scene = scene
        self.dailySeed = dailySeed; self.correctCup = correctCup
    }

    func sceneDidFinishPlacing() {
        DispatchQueue.main.async {
            self.gameState.didFinishPlacing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                self.scene?.shuffleSeed = self.dailySeed
                self.scene?.performShuffle()
            }
        }
    }
    func sceneDidFinishShuffling() {
        DispatchQueue.main.async { self.gameState.didFinishShuffling() }
    }
    func sceneDidRevealCup(_ cupIndex: Int) {
        DispatchQueue.main.async {
            self.gameState.playerTappedCupDaily(cupIndex, correctCup: self.correctCup)
        }
    }
}
