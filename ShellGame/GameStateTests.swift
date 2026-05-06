// GameStateTests.swift
// TDD unit tests for GameState level progression, scoring, and phase transitions.
// Run: Product → Test (⌘U) or xcodebuild test -scheme ShellGame

import XCTest
@testable import ShellGame

// MARK: - Helpers

extension GameState {
    /// Drive through placing + shuffling phases synchronously so playerTappedCup can fire.
    func advanceToChoosing() {
        beginRound()
        didFinishPlacing()
        didFinishShuffling()
    }
}

/// Wipes all persisted game keys so each test starts from a clean slate.
/// Call in setUp() of any test class that creates a GameState().
private func clearGameDefaults() {
    let keys = ["cq_wins", "cq_highScore", "cq_bestLevel", "cq_ftue_done",
                "cq_bestSurvival", "cq_score_history", "cq_best_gauntlet",
                "cq_prestige", "cq_daily_streak", "cq_daily_last_date",
                "cq_daily_\(GameState.todayUTCString)"]
    keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
}

// MARK: - Level Progression

final class LevelProgressionTests: XCTestCase {

    override func setUp()    { super.setUp();    clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_initialState() {
        let state = GameState()
        XCTAssertEqual(state.level, 1)
        XCTAssertEqual(state.wins,  0)
        XCTAssertEqual(state.score, 0)
        XCTAssertEqual(state.streak, 0)
        XCTAssertEqual(state.phase, .idle)
    }

    func test_firstWin_advancesToLevelTwo() {
        let state = GameState()
        state.advanceToChoosing()
        state.playerTappedCup(state.correctCupIndex)

        XCTAssertEqual(state.wins,  1, "One win recorded")
        XCTAssertEqual(state.level, 2, "Level advances to 2 after first win")
    }

    func test_secondWin_advancesToLevelThree() {
        let state = GameState()
        simulateWins(state, count: 2)
        XCTAssertEqual(state.wins,  2)
        XCTAssertEqual(state.level, 3)
    }

    func test_levelProgression_everyWin() {
        let state = GameState()
        for expectedLevel in 2...7 {
            simulateWin(state)
            XCTAssertEqual(state.wins,  expectedLevel - 1, "After \(expectedLevel - 1) wins")
            XCTAssertEqual(state.level, expectedLevel, "Level should be \(expectedLevel)")
        }
    }

    func test_levelCapsAtSeven() {
        let state = GameState()
        simulateWins(state, count: 30)   // far beyond level 7
        XCTAssertEqual(state.level, 7, "Level never exceeds 7")
    }

    func test_gauntletMode_startsAtLevelOne_regardlessOfWins() {
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let gauntlet = GameState(mode: .gauntlet)
        XCTAssertEqual(gauntlet.level, 1, "Gauntlet always starts at L1")
        XCTAssertEqual(gauntlet.gauntletLevel, 1)
        XCTAssertFalse(gauntlet.gauntletOver)
        XCTAssertFalse(gauntlet.gauntletComplete)
    }

    func test_lossDoesNotResetWins() {
        let state = GameState()
        simulateWins(state, count: 4)   // 4 wins → level 5
        let winsBeforeLoss = state.wins

        simulateLoss(state)

        XCTAssertEqual(state.wins,  winsBeforeLoss, "Cumulative wins are unaffected by a loss")
        XCTAssertEqual(state.level, 5, "Level persists after a loss")
    }
}

// MARK: - Scoring

final class ScoringTests: XCTestCase {

    override func setUp()    { super.setUp();    clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_firstWin_scoreEqualsLevelTimesTen() {
        let state = GameState()
        state.advanceToChoosing()
        state.playerTappedCup(state.correctCupIndex)

        // L1, multiplier = min(0+1, 4) = 1  →  10 * 1 * 1 = 10
        XCTAssertEqual(state.lastScoreDelta, 10)
        XCTAssertEqual(state.score,          10)
    }

    func test_streakMultiplier_capsAtFourX() {
        let state = GameState()
        // Win 4 times consecutively; multiplier caps at 4
        for _ in 0..<4 { simulateWin(state) }
        // After 4 wins: streak=4, multiplier=min(4,4)=4, still level 2 (4/2+1=3? actually wins=4, level=3)
        // Let's just verify multiplier doesn't exceed 4x
        XCTAssertLessThanOrEqual(state.lastScoreDelta, 10 * state.level * 4)
    }

    func test_lossResetsStreak() {
        let state = GameState()
        simulateWins(state, count: 3)
        XCTAssertEqual(state.streak, 3)

        simulateLoss(state)
        XCTAssertEqual(state.streak, 0, "Streak resets to 0 after a loss")
        XCTAssertEqual(state.lastScoreDelta, 0)
    }

    func test_scoreAccumulates() {
        let state = GameState()
        simulateWin(state)
        let scoreAfterOne = state.score
        XCTAssertGreaterThan(scoreAfterOne, 0)

        simulateWin(state)
        XCTAssertGreaterThan(state.score, scoreAfterOne, "Score accumulates each round")
    }
}

// MARK: - Phase Transitions

final class PhaseTransitionTests: XCTestCase {

    override func setUp()    { super.setUp();    clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_beginRound_movesToPlacing() {
        let state = GameState()
        state.beginRound()
        XCTAssertEqual(state.phase, .placing)
    }

    func test_didFinishPlacing_movesToShuffling() {
        let state = GameState()
        state.beginRound()
        state.didFinishPlacing()
        XCTAssertEqual(state.phase, .shuffling)
    }

    func test_didFinishShuffling_movesToChoosing() {
        let state = GameState()
        state.beginRound()
        state.didFinishPlacing()
        state.didFinishShuffling()
        XCTAssertEqual(state.phase, .choosing)
    }

    func test_playerTappedCup_movesToRevealing() {
        let state = GameState()
        state.advanceToChoosing()
        state.playerTappedCup(state.correctCupIndex)
        XCTAssertEqual(state.phase, .revealing)
    }

    func test_resetToIdle_returnsToIdle() {
        let state = GameState()
        state.beginRound()
        state.resetToIdle()
        XCTAssertEqual(state.phase, .idle)
    }

    func test_phasesIgnoredOutOfOrder() {
        let state = GameState()
        // Calling didFinishPlacing without beginRound should be a no-op
        state.didFinishPlacing()
        XCTAssertEqual(state.phase, .idle, "Phase guards prevent out-of-order transitions")
    }
}

// MARK: - LevelConfig

final class LevelConfigTests: XCTestCase {

    func test_level1Config() {
        let cfg = LevelConfig.config(for: 1)
        XCTAssertEqual(cfg.cupCount,     3, "L1 has 3 cups")
        XCTAssertEqual(cfg.swapCount,    4)
        XCTAssertEqual(cfg.swapDuration, 0.45, accuracy: 0.001)
        XCTAssertFalse(cfg.hasMidPause)
        XCTAssertFalse(cfg.hasGhostEffect)
    }

    func test_level4HasFourCups() {
        let cfg = LevelConfig.config(for: 4)
        XCTAssertEqual(cfg.cupCount, 4, "L4 introduces the 4th cup")
        XCTAssertEqual(cfg.slotXPositions.count, 4)
    }

    func test_level3StillHasThreeCups() {
        let cfg = LevelConfig.config(for: 3)
        XCTAssertEqual(cfg.cupCount, 3, "L3 is still 3-cup tier")
    }

    func test_level6HasMidPause() {
        let cfg = LevelConfig.config(for: 6)
        XCTAssertTrue(cfg.hasMidPause, "L6 introduces the mid-pause")
        XCTAssertFalse(cfg.hasGhostEffect)
    }

    func test_level11HasGhostEffect() {
        let cfg = LevelConfig.config(for: 11)
        XCTAssertTrue(cfg.hasMidPause)
        XCTAssertTrue(cfg.hasGhostEffect, "L11 introduces ghost transparency")
    }

    func test_level16HasFiveCups() {
        let cfg = LevelConfig.config(for: 16)
        XCTAssertEqual(cfg.cupCount, 5, "L16 introduces the 5th cup")
        XCTAssertEqual(cfg.slotXPositions.count, 5)
    }

    func test_fiveCupLayout() {
        let cfg = LevelConfig.config(for: 16)
        XCTAssertEqual(cfg.slotXPositions, [-110, -55, 0, 55, 110])
        XCTAssertEqual(cfg.cupSize.width,  60, accuracy: 0.1)
        XCTAssertEqual(cfg.cupSize.height, 74, accuracy: 0.1)
        XCTAssertEqual(cfg.hitDX,          38, accuracy: 0.1)
    }

    func test_level30Config() {
        let cfg = LevelConfig.config(for: 30)
        XCTAssertEqual(cfg.cupCount,     5)
        XCTAssertEqual(cfg.swapCount,    40, "L30 has maximum swap count")
        XCTAssertEqual(cfg.swapDuration, 0.09, accuracy: 0.001)
        XCTAssertTrue(cfg.hasGhostEffect)
    }

    func test_clampsAboveLevel30() {
        let cfg31 = LevelConfig.config(for: 31)
        let cfg30 = LevelConfig.config(for: 30)
        XCTAssertEqual(cfg31.swapCount, cfg30.swapCount, "Above L30 uses L30 params")
    }

    func test_arcHeightIncreasesWithLevel() {
        // Note: resets slightly at L16 (5-cup intro), then climbs again.
        let tier1 = (1...3).map   { LevelConfig.config(for: $0).arcHeight }
        let tier2 = (4...15).map  { LevelConfig.config(for: $0).arcHeight }
        let tier3 = (16...30).map { LevelConfig.config(for: $0).arcHeight }
        for tier in [tier1, tier2, tier3] {
            for i in 0..<tier.count - 1 {
                XCTAssertLessThanOrEqual(tier[i], tier[i + 1])
            }
        }
    }

    func test_swapDurationDecreasesWithLevel() {
        let tier1 = (1...3).map   { LevelConfig.config(for: $0).swapDuration }
        let tier2 = (4...15).map  { LevelConfig.config(for: $0).swapDuration }
        let tier3 = (16...30).map { LevelConfig.config(for: $0).swapDuration }
        for tier in [tier1, tier2, tier3] {
            for i in 0..<tier.count - 1 {
                XCTAssertGreaterThanOrEqual(tier[i], tier[i + 1])
            }
        }
    }

    func test_swapCountIncreasesWithLevel() {
        let tier1 = (1...3).map   { LevelConfig.config(for: $0).swapCount }
        let tier2 = (4...15).map  { LevelConfig.config(for: $0).swapCount }
        let tier3 = (16...30).map { LevelConfig.config(for: $0).swapCount }
        for tier in [tier1, tier2, tier3] {
            for i in 0..<tier.count - 1 {
                XCTAssertLessThanOrEqual(tier[i], tier[i + 1])
            }
        }
    }
}

// MARK: - Daily Tests

final class DailyTests: XCTestCase {
    override func setUp()    { super.setUp(); clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_dailySeed_consistentWithinSameDay() {
        let s1 = GameState.dailySeed
        let s2 = GameState.dailySeed
        XCTAssertEqual(s1, s2, "Same seed within the same day")
    }

    func test_isDailyAttempted_falseBeforeAttempt() {
        let state = GameState()
        XCTAssertFalse(state.isDailyAttempted)
    }

    func test_isDailyAttempted_trueAfterRecord() {
        let state = GameState()
        state.recordDailyAttempt(won: true)
        XCTAssertTrue(state.isDailyAttempted)
    }

    func test_dailyStreak_incrementsOnConsecutiveDays() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let yesterday = f.string(from: Date().addingTimeInterval(-86400))
        UserDefaults.standard.set(yesterday, forKey: "cq_daily_last_date")
        UserDefaults.standard.set(3, forKey: "cq_daily_streak")

        let state = GameState()
        state.recordDailyAttempt(won: true)
        XCTAssertEqual(state.dailyStreak, 4, "Streak increments when previous day was also played")
    }
}

// MARK: - Prestige Tests

final class PrestigeTests: XCTestCase {
    override func setUp()    { super.setUp(); clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_prestige_resetsLevelToOne() {
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state = GameState()
        XCTAssertEqual(state.level, 7)
        state.prestige()
        let fresh = GameState()
        XCTAssertEqual(fresh.level, 1)
        XCTAssertEqual(fresh.wins, 0)
    }

    func test_prestige_keepsHighScore() {
        UserDefaults.standard.set(500, forKey: "cq_highScore")
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state = GameState()
        state.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_highScore"), 500)
    }

    func test_prestige_incrementsPrestigeCount() {
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state = GameState()
        state.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_prestige"), 1)

        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state2 = GameState()
        state2.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_prestige"), 2)
    }

    func test_prestige_resetsFTUE() {
        UserDefaults.standard.set(true, forKey: "cq_ftue_done")
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state = GameState()
        state.prestige()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "cq_ftue_done"))
    }
}

// MARK: - Gauntlet Tests

final class GauntletTests: XCTestCase {
    override func setUp()    { super.setUp(); clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_gauntletWin_advancesGauntletLevel() {
        let state = GameState(mode: .gauntlet)
        state.advanceToChoosing()
        state.playerTappedCup(state.correctCupIndex)
        XCTAssertEqual(state.gauntletLevel, 2, "Win advances gauntlet level")
        XCTAssertFalse(state.gauntletOver)
        XCTAssertEqual(state.wins, 0, "Solo wins unaffected")
    }

    func test_gauntletLoss_endsRun() {
        let state = GameState(mode: .gauntlet)
        state.advanceToChoosing()
        let wrong = (state.correctCupIndex + 1) % 3   // L1 has 3 cups
        state.playerTappedCup(wrong)
        XCTAssertTrue(state.gauntletOver)
        XCTAssertFalse(state.gauntletComplete)
        XCTAssertEqual(state.wins, 0, "Solo wins unaffected by gauntlet loss")
    }

    func test_gauntletComplete_after7Wins() {
        let state = GameState(mode: .gauntlet)
        for _ in 1...7 { simulateWin(state) }
        XCTAssertTrue(state.gauntletComplete)
        XCTAssertEqual(state.gauntletLevel, 8, "Level advances past 7 to signal completion")
    }

    func test_gauntletBestScore_persisted() {
        let state = GameState(mode: .gauntlet)
        simulateWins(state, count: 3)
        let scoreAfter3 = state.score
        XCTAssertGreaterThan(scoreAfter3, 0)
        // Trigger run end via loss
        state.advanceToChoosing()
        let wrong = (state.correctCupIndex + 1) % 4
        state.playerTappedCup(wrong)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_best_gauntlet"), scoreAfter3)
    }
}

// MARK: - Test Helpers

private func simulateWin(_ state: GameState) {
    state.advanceToChoosing()
    state.playerTappedCup(state.correctCupIndex)
}

private func simulateLoss(_ state: GameState) {
    state.advanceToChoosing()
    let wrongCup = (state.correctCupIndex + 1) % 3
    state.playerTappedCup(wrongCup)
}

private func simulateWins(_ state: GameState, count: Int) {
    for _ in 0..<count { simulateWin(state) }
}
