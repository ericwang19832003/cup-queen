// GameState.swift
// Single source of truth for all game state.
// Drives both SpriteKit scene instructions and SwiftUI HUD reactivity.

import Foundation
import Combine

// MARK: - Phase Enum

/// Ordered phases of one game round.
enum GamePhase: Equatable {
    case idle        // Between rounds / first launch
    case placing     // Ball being shown then hidden under cup
    case shuffling   // Cups are moving
    case choosing    // Player may tap a cup
    case revealing   // Tapped cup being lifted
    case result      // Round over — show overlay
}

// MARK: - Game Mode

enum GameMode {
    case solo       // normal persistent play
    case gauntlet   // single-life L1→L7 run, no persistence
    case daily      // one fixed-seed round per day
}

// MARK: - Persistence Keys

private enum PK {
    static let wins         = "cq_wins"
    static let highScore    = "cq_highScore"
    static let bestLevel    = "cq_bestLevel"
    static let ftueDone     = "cq_ftue_done"
    static let bestSurvival = "cq_bestSurvival"
    static let bestGauntlet = "cq_best_gauntlet"
    static let prestige      = "cq_prestige"
    static let dailyStreak   = "cq_daily_streak"
    static let dailyLastDate = "cq_daily_last_date"
}

// MARK: - GameState

final class GameState: ObservableObject {

    // MARK: Published (drive SwiftUI)
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var score: Int = 0
    @Published private(set) var streak: Int = 0
    @Published private(set) var level: Int = 1
    @Published private(set) var isCorrect: Bool? = nil
    @Published private(set) var hostMessage: String = "Watch closely... 👀"
    @Published private(set) var lastScoreDelta: Int = 0
    @Published private(set) var leveledUp: Bool = false

    // MARK: Persisted stats (read by ContentView home screen)
    @Published private(set) var highScore: Int = 0
    @Published private(set) var bestLevel: Int = 1
    @Published private(set) var bestSurvival: Int = 0

    // MARK: Gauntlet
    @Published private(set) var gauntletLevel: Int = 1
    @Published private(set) var gauntletOver: Bool = false
    @Published private(set) var gauntletComplete: Bool = false
    @Published private(set) var bestGauntlet: Int = 0

    // MARK: Prestige
    @Published private(set) var prestigeCount: Int = 0

    // MARK: Daily
    @Published private(set) var dailyStreak: Int = 0

    // MARK: Internal (read by GameScene / GameView)
    private(set) var correctCupIndex: Int = 0
    private(set) var isFTUERound: Bool = false      // true exactly once — the first ever round
    @Published private(set) var survivalCount: Int = 0  // consecutive L7 wins this session; resets on loss
    private(set) var lossCount: Int = 0             // cumulative losses this session; resets after ad fires

    // MARK: Private
    private(set) var wins: Int = 0   // cumulative wins; never resets on loss
    private let mode: GameMode

    // MARK: - Init

    init(mode: GameMode = .solo) {
        self.mode    = mode
        wins         = UserDefaults.standard.integer(forKey: PK.wins)
        highScore    = UserDefaults.standard.integer(forKey: PK.highScore)
        bestLevel    = max(1, UserDefaults.standard.integer(forKey: PK.bestLevel))
        bestSurvival = UserDefaults.standard.integer(forKey: PK.bestSurvival)
        bestGauntlet = UserDefaults.standard.integer(forKey: PK.bestGauntlet)
        prestigeCount = UserDefaults.standard.integer(forKey: PK.prestige)
        dailyStreak   = UserDefaults.standard.integer(forKey: PK.dailyStreak)
        // In non-solo modes, level always starts at 1 regardless of persisted wins
        level        = mode == .solo ? min(wins + 1, 7) : 1
        isFTUERound  = !UserDefaults.standard.bool(forKey: PK.ftueDone)
    }

    // MARK: - Round Lifecycle

    /// Called by GameView to kick off a new round.
    func beginRound() {
        // Consume FTUE flag — slow-mo applies this round only, never again
        if isFTUERound {
            isFTUERound = false
            UserDefaults.standard.set(true, forKey: PK.ftueDone)
        }
        correctCupIndex = Int.random(in: 0..<LevelConfig.config(for: level).cupCount)
        isCorrect = nil
        lastScoreDelta = 0
        leveledUp = false
        phase = .placing
        hostMessage = HostMessages.placing.randomElement()!
    }

    /// Called by Coordinator when placing animation finishes.
    func didFinishPlacing() {
        guard phase == .placing else { return }
        phase = .shuffling
        hostMessage = HostMessages.shuffling.randomElement()!
    }

    /// Called by Coordinator when all shuffle swaps complete.
    func didFinishShuffling() {
        guard phase == .shuffling else { return }
        phase = .choosing
        hostMessage = HostMessages.choosing.randomElement()!
    }

    /// Called by Coordinator when the player taps a cup.
    /// - Parameter cupIndex: Identity index of the tapped cup node.
    func playerTappedCup(_ cupIndex: Int) {
        guard phase == .choosing else { return }

        // --- Gauntlet mode ---
        if mode == .gauntlet {
            phase = .revealing
            let correct = cupIndex == correctCupIndex
            isCorrect = correct
            if correct {
                let multiplier = min(streak + 1, 4)
                let delta = 10 * gauntletLevel * multiplier
                lastScoreDelta = delta
                score += delta
                streak += 1
                gauntletLevel += 1
                if gauntletLevel > 7 {
                    gauntletComplete = true
                    gauntletOver = true
                    if score > bestGauntlet {
                        bestGauntlet = score
                        UserDefaults.standard.set(bestGauntlet, forKey: PK.bestGauntlet)
                    }
                }
                hostMessage = gauntletComplete
                    ? "PERFECT RUN! 🏆"
                    : HostMessages.win.randomElement()!
            } else {
                streak = 0
                lastScoreDelta = 0
                gauntletOver = true
                if score > bestGauntlet {
                    bestGauntlet = score
                    UserDefaults.standard.set(bestGauntlet, forKey: PK.bestGauntlet)
                }
                hostMessage = HostMessages.lose.randomElement()!
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard self?.phase == .revealing else { return }
                self?.phase = .result
            }
            return
        }

        // --- Solo / Daily mode ---
        phase = .revealing

        let correct = cupIndex == correctCupIndex
        isCorrect = correct

        if correct {
            let multiplier = min(streak + 1, 4)          // max 4× streak bonus
            let delta = 10 * level * multiplier
            lastScoreDelta = delta
            score += delta
            streak += 1

            // Level up every win, cap at 7
            let oldLevel = level
            wins += 1
            level = min(wins + 1, 7)

            // Persist progress
            UserDefaults.standard.set(wins, forKey: PK.wins)
            if score > highScore {
                highScore = score
                UserDefaults.standard.set(highScore, forKey: PK.highScore)
            }
            if level > bestLevel {
                bestLevel = level
                UserDefaults.standard.set(bestLevel, forKey: PK.bestLevel)
            }

            if level > oldLevel {
                leveledUp = true
                hostMessage = HostMessages.levelUp[min(level - 2, HostMessages.levelUp.count - 1)]
            } else {
                leveledUp = false
                if level == 7 {
                    survivalCount += 1
                    if survivalCount > bestSurvival {
                        bestSurvival = survivalCount
                        UserDefaults.standard.set(bestSurvival, forKey: PK.bestSurvival)
                    }
                    hostMessage = HostMessages.survival[min(survivalCount - 1, HostMessages.survival.count - 1)]
                } else {
                    hostMessage = HostMessages.win.randomElement()!
                }
            }
        } else {
            streak = 0
            survivalCount = 0
            lossCount += 1
            lastScoreDelta = 0
            hostMessage = HostMessages.lose.randomElement()!
        }

        // Advance to result after reveal animation finishes (~1.8 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.phase == .revealing else { return }
            self?.phase = .result
        }

        // TODO: ANALYTICS — Analytics.log(.roundComplete, correct: correct, level: level)
    }

    /// Reset to idle so GameView can restart.
    func resetToIdle() {
        phase = .idle
    }

    /// Called by AdManager trigger — resets lossCount so the cycle repeats every 3 losses.
    func consumeAdTrigger() {
        lossCount = 0
    }
}

// MARK: - Host Message Bank

private enum HostMessages {
    static let placing = [
        "Watch closely... 👀",
        "Don't blink! ✨",
        "Follow the ball... 🔮"
    ]
    static let shuffling = [
        "Keep your eyes on it! 🎩",
        "Can you track it? 💫",
        "Stay focused! ⚡"
    ]
    static let choosing = [
        "Where is it? Tap! 🔮",
        "Pick your cup! ✨",
        "Trust your gut! 🎯"
    ]
    static let win = [
        "Yes! Sharp eyes! ✨",
        "Incredible! 🌟",
        "Nailed it! 🎊",
        "You're on fire! 🔥"
    ]
    static let lose = [
        "So close! 😮",
        "The cups fooled you! 💫",
        "Try again! 🎩",
        "Don't give up! ✨"
    ]
    /// Endless mode survival wins at L7 (loops on last entry for long runs)
    static let survival = [
        "Survived! Can you go further? 👑",
        "2 in a row! You're dangerous! 🔥",
        "3 straight! Legendary focus! ⚡",
        "Still here?! Unstoppable! 🌟",
        "You're in the 1% of the 1%! 👑"
    ]

    /// One entry per level-up event: entering L2…L7 (indices 0–5)
    static let levelUp = [
        "You're warming up — Level 2! 🔥",
        "Getting tricky! Level 3 now! 💫",
        "Expert territory! Level 4! 👀",
        "Master class! Level 5 — brace yourself! ⚡",
        "Legendary! Only few reach Level 6! 🌟",
        "Level 7 — only 1% ever get here! 👑"
    ]
}
