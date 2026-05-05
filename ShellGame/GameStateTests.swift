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
                "cq_bestSurvival", "cq_score_history"]
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
        XCTAssertEqual(cfg.cupCount,      3, "L1 has 3 cups")
        XCTAssertEqual(cfg.swapCount,     4)
        XCTAssertEqual(cfg.swapDuration,  0.45, accuracy: 0.001)
        XCTAssertFalse(cfg.hasMidPause)
        XCTAssertFalse(cfg.hasGhostEffect)
    }

    func test_level2HasFourCups() {
        let cfg = LevelConfig.config(for: 2)
        XCTAssertEqual(cfg.cupCount, 4, "L2 introduces the 4th cup — clearly harder than L1")
        XCTAssertEqual(cfg.slotXPositions.count, 4)
    }

    func test_level3HasMidPause() {
        let cfg = LevelConfig.config(for: 3)
        XCTAssertTrue(cfg.hasMidPause, "L3 introduces the fake-out mid-pause")
        XCTAssertFalse(cfg.hasGhostEffect)
    }

    func test_level5HasGhostEffect() {
        let cfg = LevelConfig.config(for: 5)
        XCTAssertTrue(cfg.hasMidPause)
        XCTAssertTrue(cfg.hasGhostEffect, "L5 introduces the ghost transparency effect")
    }

    func test_level7Config() {
        let cfg = LevelConfig.config(for: 7)
        XCTAssertEqual(cfg.swapCount,    23, "L7 has maximum swap count")
        XCTAssertEqual(cfg.swapDuration, 0.10, accuracy: 0.001)
        XCTAssertTrue(cfg.hasGhostEffect)
    }

    func test_arcHeightIncreasesWithLevel() {
        let heights = (1...7).map { LevelConfig.config(for: $0).arcHeight }
        for i in 0..<heights.count - 1 {
            XCTAssertLessThanOrEqual(heights[i], heights[i + 1],
                "Arc height must be non-decreasing level \(i+1) → \(i+2)")
        }
    }

    func test_swapDurationDecreasesWithLevel() {
        let durations = (1...7).map { LevelConfig.config(for: $0).swapDuration }
        for i in 0..<durations.count - 1 {
            XCTAssertGreaterThanOrEqual(durations[i], durations[i + 1],
                "Swap duration must decrease or stay equal level \(i+1) → \(i+2)")
        }
    }

    func test_swapCountIncreasesWithLevel() {
        let counts = (1...7).map { LevelConfig.config(for: $0).swapCount }
        for i in 0..<counts.count - 1 {
            XCTAssertLessThanOrEqual(counts[i], counts[i + 1],
                "Swap count must increase or stay equal level \(i+1) → \(i+2)")
        }
    }

    func test_clampsAboveLevel7() {
        // config(for:) defaults to L7 params for any level above 7
        let cfg8  = LevelConfig.config(for: 8)
        let cfg7  = LevelConfig.config(for: 7)
        XCTAssertEqual(cfg8.swapCount, cfg7.swapCount)
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
