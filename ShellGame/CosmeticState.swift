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

    static let all: [CupTheme] = [.classicRed, .gold, .midnight, .crimsonQueen, .diamond, .diamondAnimated]
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

    private enum K {
        static let activeCup    = "cq_cos_cup"
        static let activeBall   = "cq_cos_ball"
        static let activeTable  = "cq_cos_table"
        static let unlockedCups    = "cq_cos_unlocked_cups"
        static let unlockedBalls   = "cq_cos_unlocked_balls"
        static let unlockedTables  = "cq_cos_unlocked_tables"
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

    // MARK: - Persistence

    private func load() {
        let ud = UserDefaults.standard
        if let arr = ud.array(forKey: K.unlockedCups)   as? [String] { unlockedCups   = Set(arr) }
        if let arr = ud.array(forKey: K.unlockedBalls)  as? [String] { unlockedBalls  = Set(arr) }
        if let arr = ud.array(forKey: K.unlockedTables) as? [String] { unlockedTables = Set(arr) }

        if let id = ud.string(forKey: K.activeCup),
           let t  = CupTheme.all.first(where: { $0.id == id }) { activeCup = t }
        if let id = ud.string(forKey: K.activeBall),
           let t  = BallTheme.all.first(where: { $0.id == id }) { activeBall = t }
        if let id = ud.string(forKey: K.activeTable),
           let t  = TableTheme.all.first(where: { $0.id == id }) { activeTable = t }
    }
}
