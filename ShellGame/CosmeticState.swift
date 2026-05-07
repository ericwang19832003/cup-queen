// CosmeticState.swift
// Tracks which cosmetic skins are unlocked and which are active.
// Persisted entirely in UserDefaults. Read by CustomizeView and GameScene.

import SwiftUI

// MARK: - Theme Types

struct CupTheme {
    let id: String
    let name: String
    let unlitTop: Color
    let unlitBot: Color
    let litTop: Color
    let litBot: Color

    // Built-in themes.
    static let classicRed = CupTheme(
        id: "classicRed", name: "Classic Red",
        unlitTop: Color(red: 0.48, green: 0.04, blue: 0.06),
        unlitBot: Color(red: 0.72, green: 0.07, blue: 0.08),
        litTop:   Color(red: 0.82, green: 0.08, blue: 0.10),
        litBot:   Color(red: 1.00, green: 0.16, blue: 0.16)
    )
    static let gold = CupTheme(
        id: "goldCup", name: "Gold Cup",
        unlitTop: Color(red: 0.45, green: 0.30, blue: 0.02),
        unlitBot: Color(red: 0.70, green: 0.52, blue: 0.04),
        litTop:   Color(red: 0.75, green: 0.60, blue: 0.08),
        litBot:   Color(red: 1.00, green: 0.82, blue: 0.15)
    )
    static let midnight = CupTheme(
        id: "midnight", name: "Midnight",
        unlitTop: Color(red: 0.08, green: 0.04, blue: 0.22),
        unlitBot: Color(red: 0.20, green: 0.08, blue: 0.42),
        litTop:   Color(red: 0.28, green: 0.10, blue: 0.60),
        litBot:   Color(red: 0.48, green: 0.18, blue: 0.90)
    )
    static let crimsonQueen = CupTheme(
        id: "crimsonQueen", name: "Crimson Queen",
        unlitTop: Color(red: 0.55, green: 0.02, blue: 0.15),
        unlitBot: Color(red: 0.80, green: 0.04, blue: 0.22),
        litTop:   Color(red: 0.90, green: 0.06, blue: 0.28),
        litBot:   Color(red: 1.00, green: 0.20, blue: 0.40)
    )
    static let diamond = CupTheme(
        id: "diamond", name: "Diamond",
        unlitTop: Color(red: 0.50, green: 0.65, blue: 0.80),
        unlitBot: Color(red: 0.70, green: 0.82, blue: 0.95),
        litTop:   Color(red: 0.75, green: 0.90, blue: 1.00),
        litBot:   Color(red: 0.90, green: 0.97, blue: 1.00)
    )
    static let diamondAnimated = CupTheme(   // same colors, animation handled by CustomizeView
        id: "diamondAnimated", name: "Diamond ✨",
        unlitTop: Color(red: 0.50, green: 0.65, blue: 0.80),
        unlitBot: Color(red: 0.70, green: 0.82, blue: 0.95),
        litTop:   Color(red: 0.75, green: 0.90, blue: 1.00),
        litBot:   Color(red: 0.90, green: 0.97, blue: 1.00)
    )

    static let oceanTeal = CupTheme(
        id: "oceanTeal", name: "🌊 Ocean Teal",
        unlitTop: Color(red: 0.02, green: 0.22, blue: 0.30),
        unlitBot: Color(red: 0.04, green: 0.35, blue: 0.48),
        litTop:   Color(red: 0.06, green: 0.52, blue: 0.68),
        litBot:   Color(red: 0.12, green: 0.72, blue: 0.88)
    )
    static let emeraldForest = CupTheme(
        id: "emeraldForest", name: "🌿 Emerald Forest",
        unlitTop: Color(red: 0.02, green: 0.22, blue: 0.08),
        unlitBot: Color(red: 0.04, green: 0.38, blue: 0.14),
        litTop:   Color(red: 0.06, green: 0.55, blue: 0.20),
        litBot:   Color(red: 0.15, green: 0.75, blue: 0.32)
    )
    static let roseGold = CupTheme(
        id: "roseGold", name: "🌸 Rose Gold",
        unlitTop: Color(red: 0.45, green: 0.22, blue: 0.22),
        unlitBot: Color(red: 0.62, green: 0.38, blue: 0.32),
        litTop:   Color(red: 0.78, green: 0.55, blue: 0.45),
        litBot:   Color(red: 0.92, green: 0.72, blue: 0.58)
    )
    static let marbleWhite = CupTheme(
        id: "marbleWhite", name: "🤍 Marble White",
        unlitTop: Color(red: 0.55, green: 0.52, blue: 0.50),
        unlitBot: Color(red: 0.72, green: 0.70, blue: 0.68),
        litTop:   Color(red: 0.85, green: 0.83, blue: 0.82),
        litBot:   Color(red: 0.96, green: 0.95, blue: 0.93)
    )
    static let sunsetOrange = CupTheme(
        id: "sunsetOrange", name: "🌅 Sunset Orange",
        unlitTop: Color(red: 0.45, green: 0.18, blue: 0.02),
        unlitBot: Color(red: 0.68, green: 0.30, blue: 0.04),
        litTop:   Color(red: 0.88, green: 0.45, blue: 0.08),
        litBot:   Color(red: 1.00, green: 0.65, blue: 0.15)
    )
    static let arcticIce = CupTheme(
        id: "arcticIce", name: "🧊 Arctic Ice",
        unlitTop: Color(red: 0.20, green: 0.30, blue: 0.42),
        unlitBot: Color(red: 0.35, green: 0.50, blue: 0.65),
        litTop:   Color(red: 0.55, green: 0.72, blue: 0.88),
        litBot:   Color(red: 0.80, green: 0.92, blue: 1.00)
    )

    static let all: [CupTheme] = [
        .classicRed, .gold, .midnight, .crimsonQueen, .diamond, .diamondAnimated,
        .oceanTeal, .emeraldForest, .roseGold, .marbleWhite, .sunsetOrange, .arcticIce
    ]
}

struct BallTheme {
    let id: String
    let name: String
    let color: Color
    let glowColor: Color

    static let golden = BallTheme(
        id: "golden", name: "Golden",
        color: Color(red: 1, green: 0.80, blue: 0.10),
        glowColor: Color(red: 1, green: 0.80, blue: 0.10)
    )
    static let crystal = BallTheme(
        id: "crystal", name: "Crystal",
        color: Color(red: 0.75, green: 0.90, blue: 1.00),
        glowColor: Color(red: 0.55, green: 0.80, blue: 1.00)
    )
    static let flame = BallTheme(
        id: "flame", name: "Flame",
        color: Color(red: 1, green: 0.40, blue: 0.05),
        glowColor: Color(red: 1, green: 0.25, blue: 0.00)
    )
    static let crownQueen = BallTheme(
        id: "crownQueen", name: "Crown Queen 👑",
        color: Color(red: 1, green: 0.85, blue: 0.28),
        glowColor: Color(red: 0.78, green: 0.50, blue: 1.00)
    )

    static let all: [BallTheme] = [.golden, .crystal, .flame, .crownQueen]
}

struct TableTheme {
    let id: String
    let name: String
    let topColor: Color
    let botColor: Color

    static let greenFelt = TableTheme(
        id: "greenFelt", name: "Green Felt",
        topColor: Color(red: 0.08, green: 0.28, blue: 0.14),
        botColor: Color(red: 0.05, green: 0.18, blue: 0.09)
    )
    static let goldFelt = TableTheme(
        id: "goldFelt", name: "Gold Felt",
        topColor: Color(red: 0.35, green: 0.28, blue: 0.02),
        botColor: Color(red: 0.25, green: 0.20, blue: 0.01)
    )
    static let neonPurple = TableTheme(
        id: "neonPurple", name: "Neon Purple",
        topColor: Color(red: 0.20, green: 0.04, blue: 0.38),
        botColor: Color(red: 0.14, green: 0.02, blue: 0.28)
    )
    static let midnightBlue = TableTheme(
        id: "midnightBlue", name: "Midnight Blue",
        topColor: Color(red: 0.04, green: 0.08, blue: 0.30),
        botColor: Color(red: 0.02, green: 0.05, blue: 0.22)
    )

    static let all: [TableTheme] = [.greenFelt, .goldFelt, .neonPurple, .midnightBlue]
}

// MARK: - CosmeticState

final class CosmeticState: ObservableObject {
    static let shared = CosmeticState()

    // Active selections (IDs stored in UserDefaults).
    @Published private(set) var activeCup:   CupTheme   = .classicRed
    @Published private(set) var activeBall:  BallTheme  = .golden
    @Published private(set) var activeTable: TableTheme = .greenFelt

    // Unlocked item IDs.
    @Published private(set) var unlockedCups:   Set<String> = ["classicRed"]
    @Published private(set) var unlockedBalls:  Set<String> = ["golden"]
    @Published private(set) var unlockedTables: Set<String> = ["greenFelt"]
    @Published private(set) var hasUnseenUnlock: Bool = false

    private enum K {
        static let activeCup    = "cq_cos_cup"
        static let activeBall   = "cq_cos_ball"
        static let activeTable  = "cq_cos_table"
        static let unlockedCups    = "cq_cos_unlocked_cups"
        static let unlockedBalls   = "cq_cos_unlocked_balls"
        static let unlockedTables  = "cq_cos_unlocked_tables"
        static let dailyCompleted    = "cq_daily_completed"
        static let gauntletCompleted = "cq_gauntlet_completed"
        static let totalRounds       = "cq_total_rounds"
        static let hasUnseenUnlock   = "cq_has_unseen_unlock"

        // Read-only keys owned by other systems — referenced here for unlock checks.
        static let bestLevel        = "cq_bestLevel"
        static let competitionWins  = "cq_competition_wins"
        static let streakCount      = "cq_ps_count"
    }

    // Which cup/ball/table IDs require IAP (vs. milestone-only or free).
    static let purchasableCups:   [String: String] = [
        "goldCup":  "com.shellgame.magiccup.cosmetic.goldcup",
        "midnight": "com.shellgame.magiccup.cosmetic.midnight",
        "diamond":  "com.shellgame.magiccup.cosmetic.diamond"
    ]
    static let purchasableBalls: [String: String] = [
        "crystal": "com.shellgame.magiccup.cosmetic.crystal"
    ]
    static let purchasableTables: [String: String] = [
        "neonPurple":   "com.shellgame.magiccup.cosmetic.neonpurple",
        "midnightBlue": "com.shellgame.magiccup.cosmetic.midnightblue"
    ]

    // Milestone-only (never purchasable) — unlocked by StreakManager.
    static let milestoneCups:   Set<String> = ["crimsonQueen", "diamondAnimated"]
    static let milestoneBalls:  Set<String> = ["crownQueen"]
    static let milestoneTables: Set<String> = ["goldFelt"]    // also available via milestone

    // Earnable via duel wins (not IAP, not milestone).
    static let earnableBalls: Set<String> = ["flame"]

    // Game mode enum used by recordRound.
    enum GameMode { case solo, daily, gauntlet, duel }

    private init() { load() }

    // MARK: - Selection

    func selectCup(_ theme: CupTheme) {
        guard unlockedCups.contains(theme.id) else { return }
        activeCup = theme
        UserDefaults.standard.set(theme.id, forKey: K.activeCup)
    }

    func selectBall(_ theme: BallTheme) {
        guard unlockedBalls.contains(theme.id) else { return }
        activeBall = theme
        UserDefaults.standard.set(theme.id, forKey: K.activeBall)
    }

    func selectTable(_ theme: TableTheme) {
        guard unlockedTables.contains(theme.id) else { return }
        activeTable = theme
        UserDefaults.standard.set(theme.id, forKey: K.activeTable)
    }

    // MARK: - Unlock

    func unlockCup(id: String) {
        unlockedCups.insert(id)
        UserDefaults.standard.set(Array(unlockedCups), forKey: K.unlockedCups)
    }

    func unlockBall(id: String) {
        unlockedBalls.insert(id)
        UserDefaults.standard.set(Array(unlockedBalls), forKey: K.unlockedBalls)
    }

    func unlockTable(id: String) {
        unlockedTables.insert(id)
        UserDefaults.standard.set(Array(unlockedTables), forKey: K.unlockedTables)
    }

    /// Grants starter pack: Gold Cup + Crystal Ball + Neon Purple Table.
    func unlockStarterPack() {
        unlockCup(id: "goldCup")
        unlockBall(id: "crystal")
        unlockTable(id: "neonPurple")
    }

    // MARK: - Nature Pack

    @discardableResult
    func recordRound(mode: GameMode) -> String? {
        let ud = UserDefaults.standard
        ud.set(ud.integer(forKey: K.totalRounds) + 1, forKey: K.totalRounds)
        switch mode {
        case .daily:
            ud.set(ud.integer(forKey: K.dailyCompleted) + 1, forKey: K.dailyCompleted)
        case .gauntlet:
            ud.set(ud.integer(forKey: K.gauntletCompleted) + 1, forKey: K.gauntletCompleted)
        case .solo, .duel:
            break
        }
        return checkNaturePackUnlocks(announce: true)
    }

    func progress(for cupID: String) -> (current: Int, required: Int, label: String)? {
        guard !unlockedCups.contains(cupID) else { return nil }
        let ud = UserDefaults.standard
        switch cupID {
        case "oceanTeal":
            return (min(ud.integer(forKey: K.dailyCompleted), 5), 5, "Daily Challenges")
        case "emeraldForest":
            return (min(ud.integer(forKey: K.bestLevel), 10), 10, "Solo Level")
        case "roseGold":
            return (min(ud.integer(forKey: K.competitionWins), 25), 25, "Duel Wins")
        case "marbleWhite":
            return (min(ud.integer(forKey: K.totalRounds), 50), 50, "Rounds Played")
        case "sunsetOrange":
            return (min(ud.integer(forKey: K.gauntletCompleted), 3), 3, "Gauntlets Completed")
        case "arcticIce":
            return (min(ud.integer(forKey: K.streakCount), 14), 14, "Day Streak")
        default:
            return nil
        }
    }

    func clearUnseenUnlock() {
        hasUnseenUnlock = false
        UserDefaults.standard.set(false, forKey: K.hasUnseenUnlock)
    }

    @discardableResult
    private func checkNaturePackUnlocks(announce: Bool) -> String? {
        let ud = UserDefaults.standard
        let thresholds: [(String, String, Bool)] = [
            ("oceanTeal",     "🌊 Ocean Teal",     ud.integer(forKey: K.dailyCompleted) >= 5),
            ("emeraldForest", "🌿 Emerald Forest",  ud.integer(forKey: K.bestLevel) >= 10),
            ("roseGold",      "🌸 Rose Gold",       ud.integer(forKey: K.competitionWins) >= 25),
            ("marbleWhite",   "🤍 Marble White",    ud.integer(forKey: K.totalRounds) >= 50),
            ("sunsetOrange",  "🌅 Sunset Orange",   ud.integer(forKey: K.gauntletCompleted) >= 3),
            ("arcticIce",     "🧊 Arctic Ice",      ud.integer(forKey: K.streakCount) >= 14),
        ]
        var firstName: String? = nil
        for (id, name, met) in thresholds where met && !unlockedCups.contains(id) {
            unlockCup(id: id)
            if announce && firstName == nil { firstName = name }
        }
        if announce && firstName != nil {
            hasUnseenUnlock = true
            UserDefaults.standard.set(true, forKey: K.hasUnseenUnlock)
        }
        return firstName
    }

    #if DEBUG
    func reloadFromDefaults() { load() }
    #endif

    // MARK: - Persistence

    private func load() {
        let ud = UserDefaults.standard
        if let arr = ud.array(forKey: K.unlockedCups)   as? [String] { unlockedCups   = Set(arr).union(["classicRed"]) }
        if let arr = ud.array(forKey: K.unlockedBalls)  as? [String] { unlockedBalls  = Set(arr).union(["golden"]) }
        if let arr = ud.array(forKey: K.unlockedTables) as? [String] { unlockedTables = Set(arr).union(["greenFelt"]) }

        if let id = ud.string(forKey: K.activeCup),
           let t  = CupTheme.all.first(where: { $0.id == id }) { activeCup = t }
        if let id = ud.string(forKey: K.activeBall),
           let t  = BallTheme.all.first(where: { $0.id == id }) { activeBall = t }
        if let id = ud.string(forKey: K.activeTable),
           let t  = TableTheme.all.first(where: { $0.id == id }) { activeTable = t }

        if !unlockedCups.contains(activeCup.id)     { activeCup   = .classicRed }
        if !unlockedBalls.contains(activeBall.id)   { activeBall  = .golden }
        if !unlockedTables.contains(activeTable.id) { activeTable = .greenFelt }

        hasUnseenUnlock = ud.bool(forKey: K.hasUnseenUnlock)
        checkNaturePackUnlocks(announce: false)
    }
}
