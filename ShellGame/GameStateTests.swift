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
    let keys = [PK.wins, "cq_highScore", "cq_bestLevel", "cq_ftue_done",
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
        XCTAssertEqual(state.wins,  1)
        XCTAssertEqual(state.level, 2)
    }

    func test_levelProgression_firstFiveWins() {
        let state = GameState()
        for expectedLevel in 2...6 {
            simulateWin(state)
            XCTAssertEqual(state.level, expectedLevel, "Level should be \(expectedLevel) after \(expectedLevel - 1) wins")
        }
    }

    func test_levelCapsAtThirty() {
        let state = GameState()
        simulateWins(state, count: 50)   // far beyond level 30
        XCTAssertEqual(state.level, 30, "Level never exceeds 30")
    }

    func test_gauntletMode_startsAtLevelOne_regardlessOfWins() {
        UserDefaults.standard.set(29, forKey: PK.wins)
        let gauntlet = GameState(mode: .gauntlet)
        XCTAssertEqual(gauntlet.level, 1, "Gauntlet always starts at L1")
        XCTAssertEqual(gauntlet.gauntletLevel, 1)
        XCTAssertFalse(gauntlet.gauntletOver)
        XCTAssertFalse(gauntlet.gauntletComplete)
    }

    func test_survivalCountIncrements_atLevelThirty() {
        let state = GameState()
        simulateWins(state, count: 29)   // reach L30
        XCTAssertEqual(state.level, 30)
        let survivalBefore = state.survivalCount
        simulateWin(state)               // win at L30 → survival loop
        XCTAssertEqual(state.survivalCount, survivalBefore + 1, "Survival count increments when winning at L30")
    }

    func test_lossDoesNotResetWins() {
        let state = GameState()
        simulateWins(state, count: 4)
        let winsBeforeLoss = state.wins
        simulateLoss(state)
        XCTAssertEqual(state.wins,  winsBeforeLoss)
        XCTAssertEqual(state.level, 5)
    }
}

// MARK: - Scoring

final class ScoringTests: XCTestCase {

    override func setUp()    { super.setUp();    clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_firstWin_L1_score() {
        let state = GameState()
        state.advanceToChoosing()
        state.playerTappedCup(state.correctCupIndex)
        // L1: 3 cups → cupBase=10, level=1, streakMult=1  →  10*1*1 = 10
        XCTAssertEqual(state.lastScoreDelta, 10)
        XCTAssertEqual(state.score,          10)
    }

    func test_fourCupLevel_usesHigherBase() {
        // 4 wins: wins 1-3 at L1-L3 (3-cup), win 4 at L4 (4-cup tier)
        // Win 4: level=4, streak=3, streakMult=min(4,4)=4  →  13*4*4 = 208
        let state = GameState()
        simulateWins(state, count: 4)
        XCTAssertEqual(state.level, 5)
        // cupBase=13, level=4, streakMult=4  →  13*4*4 = 208
        XCTAssertEqual(state.lastScoreDelta, 208)
    }

    func test_fiveCupLevel_usesHighestBase() {
        // 16 wins: wins 1-15 at L1-L15, win 16 at L16 (5-cup tier)
        // Win 16: level=16, streak=15 → capped at 4  →  17*16*4 = 1088
        let state = GameState()
        simulateWins(state, count: 16)
        XCTAssertEqual(state.level, 17)
        // cupBase=17, level=16, streakMult=4  →  17*16*4 = 1088
        XCTAssertEqual(state.lastScoreDelta, 1088)
    }

    func test_streakMultiplier_capsAtFourX() {
        let state = GameState()
        simulateWins(state, count: 10)
        let cup = LevelConfig.config(for: state.level).cupCount
        let expectedBase = cup == 5 ? 17 : cup == 4 ? 13 : 10
        XCTAssertLessThanOrEqual(state.lastScoreDelta, expectedBase * state.level * 4,
            "Score delta never exceeds cupBase * level * 4")
    }

    func test_lossResetsStreak() {
        let state = GameState()
        simulateWins(state, count: 3)
        XCTAssertEqual(state.streak, 3)
        simulateLoss(state)
        XCTAssertEqual(state.streak, 0)
        XCTAssertEqual(state.lastScoreDelta, 0)
    }

    func test_scoreAccumulates() {
        let state = GameState()
        simulateWin(state)
        let scoreAfterOne = state.score
        XCTAssertGreaterThan(scoreAfterOne, 0)
        simulateWin(state)
        XCTAssertGreaterThan(state.score, scoreAfterOne)
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

    func test_level16And17GhostEffectReset() {
        // 5-cup intro grace period: ghost turns off for L16–17 to ease the transition
        XCTAssertFalse(LevelConfig.config(for: 16).hasGhostEffect, "L16 grace: ghost off")
        XCTAssertFalse(LevelConfig.config(for: 17).hasGhostEffect, "L17 grace: ghost off")
        XCTAssertTrue(LevelConfig.config(for: 18).hasGhostEffect,  "L18 ghost resumes")
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
        UserDefaults.standard.set(6, forKey: PK.wins)
        let state = GameState()
        XCTAssertEqual(state.level, 7)
        state.prestige()
        let fresh = GameState()
        XCTAssertEqual(fresh.level, 1)
        XCTAssertEqual(fresh.wins, 0)
    }

    func test_prestige_keepsHighScore() {
        UserDefaults.standard.set(500, forKey: "cq_highScore")
        UserDefaults.standard.set(6, forKey: PK.wins)
        let state = GameState()
        state.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_highScore"), 500)
    }

    func test_prestige_incrementsPrestigeCount() {
        UserDefaults.standard.set(6, forKey: PK.wins)
        let state = GameState()
        state.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_prestige"), 1)

        UserDefaults.standard.set(6, forKey: PK.wins)
        let state2 = GameState()
        state2.prestige()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_prestige"), 2)
    }

    func test_prestige_resetsFTUE() {
        UserDefaults.standard.set(true, forKey: "cq_ftue_done")
        UserDefaults.standard.set(6, forKey: PK.wins)
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
    let cupCount = LevelConfig.config(for: state.level).cupCount
    let wrongCup = (state.correctCupIndex + 1) % cupCount
    state.playerTappedCup(wrongCup)
}

private func simulateWins(_ state: GameState, count: Int) {
    for _ in 0..<count { simulateWin(state) }
}

// MARK: - ScoreQueueTests

final class ScoreQueueTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Start every test with an empty queue
        UserDefaults.standard.removeObject(forKey: "cq_pending_scores")
    }

    func test_enqueue_addsEntryToQueue() {
        let entry: [String: Any] = [
            "player_name": "Alice",
            "score": 500,
            "mode": "solo",
            "level": 3
        ]
        ScoreSubmissionService.shared.enqueue(entry)
        // enqueue() dispatches async to the serial queue; wait for it to settle
        Thread.sleep(forTimeInterval: 0.1)
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.count, 1)
        XCTAssertEqual(queue?.first?["player_name"] as? String, "Alice")
    }

    func test_enqueue_preservesOrder() {
        ScoreSubmissionService.shared.enqueue(["player_name": "A", "score": 100, "mode": "solo", "level": 1])
        ScoreSubmissionService.shared.enqueue(["player_name": "B", "score": 200, "mode": "solo", "level": 2])
        // enqueue() dispatches async to the serial queue; wait for both to settle
        Thread.sleep(forTimeInterval: 0.1)
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.first?["player_name"] as? String, "A")
        XCTAssertEqual(queue?.last?["player_name"]  as? String, "B")
    }

    func test_dequeue_removesFirstEntry() {
        ScoreSubmissionService.shared.enqueue(["player_name": "A", "score": 100, "mode": "solo", "level": 1])
        ScoreSubmissionService.shared.enqueue(["player_name": "B", "score": 200, "mode": "solo", "level": 2])
        // enqueue() dispatches async to the serial queue; wait for both to settle
        Thread.sleep(forTimeInterval: 0.1)
        let first = ScoreSubmissionService.shared.dequeue()
        XCTAssertEqual(first?["player_name"] as? String, "A")
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.count, 1)
    }

    func test_dequeue_returnsNilWhenEmpty() {
        let result = ScoreSubmissionService.shared.dequeue()
        XCTAssertNil(result)
    }
}

// MARK: - PlayerNameTests

final class PlayerNameTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "cq_player_name")
    }

    func test_savedName_defaultsToEmptyString() {
        let name = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
        XCTAssertEqual(name, "")
    }

    func test_saveName_persistsToUserDefaults() {
        UserDefaults.standard.set("Zara", forKey: "cq_player_name")
        let loaded = UserDefaults.standard.string(forKey: "cq_player_name")
        XCTAssertEqual(loaded, "Zara")
    }

    func test_nameCappedAt20Characters() {
        let longName = String(repeating: "X", count: 25)
        let capped = String(longName.prefix(20))
        XCTAssertEqual(capped.count, 20)
    }
}

// MARK: - StartFreshTests

final class StartFreshTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(4, forKey: PK.wins)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: PK.wins)
    }

    func test_startFresh_true_startsAtLevel1() {
        let state = GameState(mode: .solo, startFresh: true)
        XCTAssertEqual(state.level, 1)
    }

    func test_startFresh_false_continuesFromSavedLevel() {
        let state = GameState(mode: .solo, startFresh: false)
        XCTAssertEqual(state.level, 5) // wins=4 → level=5
    }

    func test_startFresh_defaultIsFalse() {
        let state = GameState(mode: .solo)
        XCTAssertEqual(state.level, 5) // unchanged default behaviour
    }
}

// MARK: - StreakManagerTests

final class StreakManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Wipe all streak keys so each test starts clean.
        ["cq_ps_count", "cq_ps_last_day", "cq_ps_shields", "cq_ps_milestones"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
        // Reset shields to 0 directly via UserDefaults (avoids negative-clamp side effects).
        UserDefaults.standard.set(0, forKey: "cq_ps_shields")
        // Reload the singleton's in-memory state from the now-cleared defaults.
        StreakManager.shared.reloadFromDefaults()
    }

    func test_firstRound_setsStreakToOne() {
        let milestones = StreakManager.shared.recordRound()
        XCTAssertEqual(StreakManager.shared.streakCount, 1)
        XCTAssertTrue(milestones.isEmpty, "No milestones at day 1")
    }

    func test_sameDay_isIdempotent() {
        StreakManager.shared.recordRound()
        let before = StreakManager.shared.streakCount
        StreakManager.shared.recordRound()
        XCTAssertEqual(StreakManager.shared.streakCount, before)
    }

    func test_addShield_cappedAtThree() {
        StreakManager.shared.addShields(5)
        XCTAssertEqual(StreakManager.shared.shields, StreakManager.maxShields)
    }

    func test_addShields_incrementsCorrectly() {
        StreakManager.shared.addShields(2)
        XCTAssertEqual(StreakManager.shared.shields, 2)
    }

    func test_milestoneRewards_containsExpectedDays() {
        let days = Set(StreakManager.milestoneRewards.keys)
        XCTAssertTrue(days.contains(3))
        XCTAssertTrue(days.contains(7))
        XCTAssertTrue(days.contains(30))
        XCTAssertTrue(days.contains(100))
        XCTAssertTrue(days.contains(365))
    }
}

// MARK: - CosmeticStateNaturePackTests

final class CosmeticStateNaturePackTests: XCTestCase {

    private let naturePack = ["oceanTeal", "emeraldForest", "roseGold",
                              "marbleWhite", "sunsetOrange", "arcticIce"]
    private let extraKeys  = ["cq_daily_completed", "cq_gauntlet_completed",
                              "cq_total_rounds", "cq_has_unseen_unlock",
                              "cq_bestLevel", "cq_competition_wins", "cq_ps_count"]

    override func setUp() {
        super.setUp()
        for k in extraKeys { UserDefaults.standard.removeObject(forKey: k) }
        if var cups = UserDefaults.standard.array(forKey: "cq_cos_unlocked_cups") as? [String] {
            cups.removeAll { naturePack.contains($0) }
            UserDefaults.standard.set(cups, forKey: "cq_cos_unlocked_cups")
        }
        CosmeticState.shared.reloadFromDefaults()
    }

    override func tearDown() {
        for k in extraKeys { UserDefaults.standard.removeObject(forKey: k) }
        CosmeticState.shared.reloadFromDefaults()
        super.tearDown()
    }

    func test_recordRound_incrementsTotalRounds() {
        CosmeticState.shared.recordRound(mode: .solo)
        CosmeticState.shared.recordRound(mode: .solo)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_total_rounds"), 2)
    }

    func test_recordRound_daily_incrementsDailyCompleted() {
        CosmeticState.shared.recordRound(mode: .daily)
        CosmeticState.shared.recordRound(mode: .daily)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_daily_completed"), 2)
    }

    func test_recordRound_gauntlet_incrementsGauntletCompleted() {
        CosmeticState.shared.recordRound(mode: .gauntlet)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_gauntlet_completed"), 1)
    }

    func test_marbleWhite_unlocksAt50TotalRounds() {
        for _ in 0..<49 { CosmeticState.shared.recordRound(mode: .solo) }
        XCTAssertFalse(CosmeticState.shared.unlockedCups.contains("marbleWhite"))
        let name = CosmeticState.shared.recordRound(mode: .solo)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("marbleWhite"))
        XCTAssertEqual(name, "🤍 Marble White")
        XCTAssertTrue(CosmeticState.shared.hasUnseenUnlock)
    }

    func test_oceanTeal_unlocksAt5DailyChallenges() {
        for _ in 0..<4 { CosmeticState.shared.recordRound(mode: .daily) }
        XCTAssertFalse(CosmeticState.shared.unlockedCups.contains("oceanTeal"))
        CosmeticState.shared.recordRound(mode: .daily)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("oceanTeal"))
    }

    func test_sunsetOrange_unlocksAt3Gauntlets() {
        for _ in 0..<2 { CosmeticState.shared.recordRound(mode: .gauntlet) }
        XCTAssertFalse(CosmeticState.shared.unlockedCups.contains("sunsetOrange"))
        CosmeticState.shared.recordRound(mode: .gauntlet)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("sunsetOrange"))
    }

    func test_emeraldForest_unlocksWhenLevel10Reached() {
        UserDefaults.standard.set(10, forKey: "cq_bestLevel")
        CosmeticState.shared.recordRound(mode: .solo)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("emeraldForest"))
    }

    func test_roseGold_unlocksWhen25DuelWins() {
        UserDefaults.standard.set(25, forKey: "cq_competition_wins")
        CosmeticState.shared.recordRound(mode: .duel)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("roseGold"))
    }

    func test_arcticIce_unlocksAt14DayStreak() {
        UserDefaults.standard.set(14, forKey: "cq_ps_count")
        CosmeticState.shared.recordRound(mode: .solo)
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("arcticIce"))
    }

    func test_clearUnseenUnlock_clearsFlag() {
        UserDefaults.standard.set(14, forKey: "cq_ps_count")
        CosmeticState.shared.recordRound(mode: .solo)
        XCTAssertTrue(CosmeticState.shared.hasUnseenUnlock)
        CosmeticState.shared.clearUnseenUnlock()
        XCTAssertFalse(CosmeticState.shared.hasUnseenUnlock)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "cq_has_unseen_unlock"))
    }

    func test_progress_oceanTeal_returnsCorrectTuple() {
        UserDefaults.standard.set(3, forKey: "cq_daily_completed")
        CosmeticState.shared.reloadFromDefaults()
        let p = CosmeticState.shared.progress(for: "oceanTeal")
        XCTAssertEqual(p?.current, 3)
        XCTAssertEqual(p?.required, 5)
        XCTAssertEqual(p?.label, "Daily Challenges")
    }

    func test_retroactiveUnlock_onLoad_silently() {
        UserDefaults.standard.set(10, forKey: "cq_bestLevel")
        CosmeticState.shared.reloadFromDefaults()
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("emeraldForest"))
        XCTAssertFalse(CosmeticState.shared.hasUnseenUnlock)
    }
}
