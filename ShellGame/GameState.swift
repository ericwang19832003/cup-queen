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

    var submissionKey: String {
        switch self {
        case .solo:     return "solo"
        case .gauntlet: return "gauntlet"
        case .daily:    return "daily"
        }
    }
}

// MARK: - Persistence Keys

enum PK {
    static let wins         = "cq_wins"
    static let highScore    = "cq_highScore"
    static let bestLevel    = "cq_bestLevel"
    static let ftueDone     = "cq_ftue_done"
    static let bestSurvival = "cq_bestSurvival"
    static let bestGauntlet = "cq_best_gauntlet"
    static let prestige      = "cq_prestige"
    static let dailyStreak   = "cq_daily_streak"
    static let dailyLastDate = "cq_daily_last_date"
    static let playerName    = "cq_player_name"
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
    private(set) var mode: GameMode
    private let winOffset: Int       // persisted wins at session start (non-zero on Fresh Start)

    /// The player name entered before the session. Read-only from GameState.
    var playerName: String {
        UserDefaults.standard.string(forKey: PK.playerName) ?? "Anonymous"
    }

    // MARK: - Init

    init(mode: GameMode = .solo, startFresh: Bool = false) {
        self.mode    = mode
        wins         = UserDefaults.standard.integer(forKey: PK.wins)
        highScore    = UserDefaults.standard.integer(forKey: PK.highScore)
        bestLevel    = max(1, UserDefaults.standard.integer(forKey: PK.bestLevel))
        bestSurvival = UserDefaults.standard.integer(forKey: PK.bestSurvival)
        bestGauntlet = UserDefaults.standard.integer(forKey: PK.bestGauntlet)
        prestigeCount = UserDefaults.standard.integer(forKey: PK.prestige)
        dailyStreak   = UserDefaults.standard.integer(forKey: PK.dailyStreak)
        // winOffset anchors level computation to 0 on Fresh Start without discarding persisted wins
        winOffset    = (mode == .solo && startFresh) ? wins : 0
        // In non-solo modes or Fresh Start, level always starts at 1 regardless of persisted wins
        level        = (mode == .solo && !startFresh) ? min(wins + 1, 30) : 1
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
        let effectiveLevel = mode == .gauntlet ? gauntletLevel : level
        correctCupIndex = Int.random(in: 0..<LevelConfig.config(for: effectiveLevel).cupCount)
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
            AnalyticsManager.log(.roundResult(mode: "gauntlet", level: gauntletLevel, correct: correct))
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
            let cupBase: Int = {
                switch LevelConfig.config(for: level).cupCount {
                case 5:  return 17   // 5-cup tier: 1.7× base
                case 4:  return 13   // 4-cup tier: 1.3× base
                default: return 10   // 3-cup tier: 1.0× base
                }
            }()
            let delta = cupBase * level * multiplier
            lastScoreDelta = delta
            score += delta
            streak += 1

            // Level up every win, cap at 30.
            // winOffset is non-zero on Fresh Start — ensures level counts from 1
            // relative to this session's starting point without discarding persisted wins.
            let oldLevel = level
            wins += 1
            level = min(wins - winOffset + 1, 30)

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
                if level == 30 {
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

        iCloudSyncManager.shared.push()

        AnalyticsManager.log(.roundResult(mode: mode.submissionKey, level: level, correct: correct))

        // Advance to result after reveal animation finishes (~1.8 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.phase == .revealing else { return }
            self?.phase = .result
        }
    }

    /// Reset to idle so GameView can restart.
    func resetToIdle() {
        phase = .idle
    }

    /// Called by AdManager trigger — resets lossCount so the cycle repeats every 3 losses.
    func consumeAdTrigger() {
        lossCount = 0
    }

    /// Resets solo progression to L1 and awards a prestige badge.
    /// Keeps: highScore, bestLevel, bestSurvival, bestGauntlet, score history.
    func prestige() {
        UserDefaults.standard.removeObject(forKey: PK.wins)
        UserDefaults.standard.removeObject(forKey: PK.ftueDone)
        prestigeCount += 1
        UserDefaults.standard.set(prestigeCount, forKey: PK.prestige)
        iCloudSyncManager.shared.push()
        wins  = 0
        level = 1
        isFTUERound = true
    }

    // MARK: - Daily Challenge

    /// UTC date string for today: "yyyy-MM-dd"
    static var todayUTCString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Deterministic seed for today's daily challenge (changes at UTC midnight).
    static var dailySeed: UInt64 {
        UInt64(floor(Date().timeIntervalSince1970 / 86400))
    }

    /// True if the player has already attempted today's daily challenge.
    var isDailyAttempted: Bool {
        UserDefaults.standard.bool(forKey: "cq_daily_\(GameState.todayUTCString)")
    }

    /// Records today's daily attempt result.
    func recordDailyAttempt(won: Bool) {
        let today = GameState.todayUTCString
        UserDefaults.standard.set(true, forKey: "cq_daily_\(today)")

        let lastDate = UserDefaults.standard.string(forKey: PK.dailyLastDate) ?? ""
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let yesterday = f.string(from: Date().addingTimeInterval(-86400))

        if lastDate == yesterday {
            dailyStreak += 1
        } else if lastDate != today {
            dailyStreak = 1
        }
        UserDefaults.standard.set(dailyStreak, forKey: PK.dailyStreak)
        UserDefaults.standard.set(today, forKey: PK.dailyLastDate)
        iCloudSyncManager.shared.push()
    }

    /// Daily mode variant — correctCupIndex is caller-supplied (seeded), not the internal random value.
    func playerTappedCupDaily(_ cupIndex: Int, correctCup: Int) {
        guard phase == .choosing else { return }
        phase = .revealing
        let correct = cupIndex == correctCup
        isCorrect = correct
        lastScoreDelta = correct ? 10 * 4 * 1 : 0
        hostMessage = correct ? "You found it! 🎯" : HostMessages.lose.randomElement()!
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.phase == .revealing else { return }
            self?.phase = .result
        }
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

    /// One entry per level-up event: entering L2…L30 (indices 0–28)
    static let levelUp = [
        "You're warming up — Level 2! 🔥",          // L2
        "Getting tricky! Level 3 now! 💫",           // L3
        "Expert territory! Level 4! 👀",             // L4
        "Master class! Level 5 — brace yourself! ⚡", // L5
        "Legendary! Only few reach Level 6! 🌟",     // L6
        "Level 7 — you're on a roll! 🎯",            // L7
        "Level 8 — the 4-cup gauntlet begins! 🏆",   // L8
        "Level 9 — eyes like a hawk! 🦅",            // L9
        "Level 10 — double digits! Impressive! 🔟",  // L10
        "Level 11 — the ghost effect kicks in! 👻",  // L11
        "Level 12 — barely blink! 💨",               // L12
        "Level 13 — unlucky? Not you! 🍀",           // L13
        "Level 14 — near-superhuman! ⚡",             // L14
        "Level 15 — last of the 4-cup tier! 🔥",     // L15
        "Level 16 — FIVE CUPS! 🖐️ New challenge!",  // L16
        "Level 17 — five cups and counting! 👁️",    // L17
        "Level 18 — ghost cups return! 👻🖐️",       // L18
        "Level 19 — elite territory! 🌟",            // L19
        "Level 20 — halfway to legend! 🏅",          // L20
        "Level 21 — only 5% reach here! 🎖️",        // L21
        "Level 22 — machine-like precision! 🤖",     // L22
        "Level 23 — almost inhuman! ⚡",              // L23
        "Level 24 — the 1% zone! 💎",                // L24
        "Level 25 — quarter-century of cups! 🏆",    // L25
        "Level 26 — a true master! 👑",              // L26
        "Level 27 — legend status! 🌠",              // L27
        "Level 28 — two away from the top! 🔥",      // L28
        "Level 29 — one step from glory! ✨",         // L29 + L30 (reused via min clamp)
    ]
}
