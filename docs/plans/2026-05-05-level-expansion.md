# Level Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand the game from 7 to 30 levels, add a 5-cup tier at L16–30, update the scoring formula to reward harder cup tiers, and move the prestige gate to L30.

**Architecture:** All level data lives in `LevelConfig.config(for:)` in `GameScene.swift` (a switch statement). `GameState.swift` owns the level cap, survival check, and scoring formula. `ModesView.swift` owns the prestige availability gate. Tests in `GameStateTests.swift` must be updated to reflect new thresholds.

**Tech Stack:** Swift, SwiftUI, SpriteKit, XCTest

---

## Context for Implementer

Key facts about the codebase:

- `LevelConfig.config(for:)` in `ShellGame/GameScene.swift` is a `switch` with cases 1–6 and a `default` (L7+). It must expand to explicit cases 1–30 with a new `default` catching anything above 30.
- `LevelConfig` has three computed properties that branch on `cupCount == 4` vs not — these must be upgraded to a 3-way switch for cups 3/4/5.
- `GameState.swift` line 95 and 192: `min(wins + 1, 7)` → `min(wins + 1, 30)`.
- `GameState.swift` line 210: `if level == 7` survival check → `if level == 30`.
- Scoring formula lines 183–184: `let delta = 10 * level * multiplier` → use cup-tier base multiplier.
- `ModesView.swift` line 53: `min(..., 7)` for `currentLevel` → `min(..., 30)`. Line 115: `canPrestige = currentLevel == 7` → `currentLevel >= 30`.
- Tests have hardcoded 7-thresholds that must change: `test_levelCapsAtSeven`, `test_levelProgression_everyWin`, `test_level2HasFourCups`, `test_level3HasMidPause`, `test_level5HasGhostEffect`, `test_level7Config`, `test_clampsAboveLevel7`, and the monotonicity tests covering `1...7`.
- `simulateLoss` helper uses `% 3` — this still works correctly for 4 and 5 cups (verified: no false positives).

---

## Task 1: Update LevelConfig — 30 cases + 5-cup layout

**Files:**
- Modify: `ShellGame/GameScene.swift` (lines 41–81)
- Test: `ShellGame/GameStateTests.swift` (LevelConfigTests class, lines 196–262)

### Step 1: Write failing tests first

Replace the `LevelConfigTests` class in `ShellGame/GameStateTests.swift` with:

```swift
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
        // Check monotonicity within each tier separately.
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
        // Check within each tier (resets at L16).
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
        // Check within each tier (resets at L16).
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
```

### Step 2: Run tests to verify they fail

```bash
cd /Users/minwang/cup_game
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|LevelConfig)" | tail -20
```

Expected: multiple FAILs in LevelConfigTests (L4 not 4 cups, L16 not 5 cups, etc.)

### Step 3: Update `LevelConfig` in `ShellGame/GameScene.swift`

**3a. Replace the three computed properties** (currently binary 4-vs-other checks):

```swift
/// X-positions of the cup slots for this cup count.
var slotXPositions: [CGFloat] {
    switch cupCount {
    case 5:  return [-110, -55, 0, 55, 110]
    case 4:  return [-120, -40, 40, 120]
    default: return [-108, 0, 108]
    }
}

/// Size of each cup sprite for this cup count.
var cupSize: CGSize {
    switch cupCount {
    case 5:  return CGSize(width: 60, height: 74)
    case 4:  return CGSize(width: 70, height: 86)
    default: return CGSize(width: 80, height: 98)
    }
}

/// Horizontal hit-test radius for this cup count.
var hitDX: CGFloat {
    switch cupCount {
    case 5:  return 38
    case 4:  return 45
    default: return 52
    }
}
```

**3b. Replace the `config(for:)` switch** with 30 explicit cases:

```swift
static func config(for level: Int) -> LevelConfig {
    switch level {
    // ── 3-cup tier (L1–3) ──────────────────────────────────────────────
    case 1:  return LevelConfig(cupCount: 3, swapCount: 4,  swapDuration: 0.45, arcHeight: 40, hasMidPause: false, hasGhostEffect: false)
    case 2:  return LevelConfig(cupCount: 3, swapCount: 6,  swapDuration: 0.38, arcHeight: 44, hasMidPause: false, hasGhostEffect: false)
    case 3:  return LevelConfig(cupCount: 3, swapCount: 8,  swapDuration: 0.30, arcHeight: 50, hasMidPause: false, hasGhostEffect: false)
    // ── 4-cup tier (L4–15) ─────────────────────────────────────────────
    case 4:  return LevelConfig(cupCount: 4, swapCount: 10, swapDuration: 0.26, arcHeight: 54, hasMidPause: false, hasGhostEffect: false)
    case 5:  return LevelConfig(cupCount: 4, swapCount: 12, swapDuration: 0.23, arcHeight: 58, hasMidPause: false, hasGhostEffect: false)
    case 6:  return LevelConfig(cupCount: 4, swapCount: 14, swapDuration: 0.20, arcHeight: 62, hasMidPause: true,  hasGhostEffect: false)
    case 7:  return LevelConfig(cupCount: 4, swapCount: 16, swapDuration: 0.18, arcHeight: 66, hasMidPause: true,  hasGhostEffect: false)
    case 8:  return LevelConfig(cupCount: 4, swapCount: 18, swapDuration: 0.16, arcHeight: 68, hasMidPause: true,  hasGhostEffect: false)
    case 9:  return LevelConfig(cupCount: 4, swapCount: 20, swapDuration: 0.15, arcHeight: 70, hasMidPause: true,  hasGhostEffect: false)
    case 10: return LevelConfig(cupCount: 4, swapCount: 22, swapDuration: 0.14, arcHeight: 72, hasMidPause: true,  hasGhostEffect: false)
    case 11: return LevelConfig(cupCount: 4, swapCount: 24, swapDuration: 0.13, arcHeight: 74, hasMidPause: true,  hasGhostEffect: true)
    case 12: return LevelConfig(cupCount: 4, swapCount: 26, swapDuration: 0.12, arcHeight: 76, hasMidPause: true,  hasGhostEffect: true)
    case 13: return LevelConfig(cupCount: 4, swapCount: 27, swapDuration: 0.11, arcHeight: 78, hasMidPause: true,  hasGhostEffect: true)
    case 14: return LevelConfig(cupCount: 4, swapCount: 28, swapDuration: 0.11, arcHeight: 80, hasMidPause: true,  hasGhostEffect: true)
    case 15: return LevelConfig(cupCount: 4, swapCount: 30, swapDuration: 0.10, arcHeight: 82, hasMidPause: true,  hasGhostEffect: true)
    // ── 5-cup tier (L16–30) ────────────────────────────────────────────
    case 16: return LevelConfig(cupCount: 5, swapCount: 20, swapDuration: 0.22, arcHeight: 60, hasMidPause: true,  hasGhostEffect: false)
    case 17: return LevelConfig(cupCount: 5, swapCount: 22, swapDuration: 0.20, arcHeight: 62, hasMidPause: true,  hasGhostEffect: false)
    case 18: return LevelConfig(cupCount: 5, swapCount: 24, swapDuration: 0.18, arcHeight: 64, hasMidPause: true,  hasGhostEffect: true)
    case 19: return LevelConfig(cupCount: 5, swapCount: 26, swapDuration: 0.17, arcHeight: 66, hasMidPause: true,  hasGhostEffect: true)
    case 20: return LevelConfig(cupCount: 5, swapCount: 28, swapDuration: 0.16, arcHeight: 68, hasMidPause: true,  hasGhostEffect: true)
    case 21: return LevelConfig(cupCount: 5, swapCount: 30, swapDuration: 0.15, arcHeight: 70, hasMidPause: true,  hasGhostEffect: true)
    case 22: return LevelConfig(cupCount: 5, swapCount: 32, swapDuration: 0.14, arcHeight: 72, hasMidPause: true,  hasGhostEffect: true)
    case 23: return LevelConfig(cupCount: 5, swapCount: 33, swapDuration: 0.13, arcHeight: 74, hasMidPause: true,  hasGhostEffect: true)
    case 24: return LevelConfig(cupCount: 5, swapCount: 34, swapDuration: 0.12, arcHeight: 76, hasMidPause: true,  hasGhostEffect: true)
    case 25: return LevelConfig(cupCount: 5, swapCount: 35, swapDuration: 0.11, arcHeight: 78, hasMidPause: true,  hasGhostEffect: true)
    case 26: return LevelConfig(cupCount: 5, swapCount: 36, swapDuration: 0.11, arcHeight: 80, hasMidPause: true,  hasGhostEffect: true)
    case 27: return LevelConfig(cupCount: 5, swapCount: 37, swapDuration: 0.10, arcHeight: 82, hasMidPause: true,  hasGhostEffect: true)
    case 28: return LevelConfig(cupCount: 5, swapCount: 38, swapDuration: 0.10, arcHeight: 84, hasMidPause: true,  hasGhostEffect: true)
    case 29: return LevelConfig(cupCount: 5, swapCount: 39, swapDuration: 0.09, arcHeight: 86, hasMidPause: true,  hasGhostEffect: true)
    case 30: return LevelConfig(cupCount: 5, swapCount: 40, swapDuration: 0.09, arcHeight: 88, hasMidPause: true,  hasGhostEffect: true)
    default: return LevelConfig(cupCount: 5, swapCount: 40, swapDuration: 0.09, arcHeight: 88, hasMidPause: true,  hasGhostEffect: true)
    }
}
```

### Step 4: Run tests to verify LevelConfigTests pass

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|LevelConfig)" | tail -20
```

Expected: all LevelConfigTests PASS. Other test suites may still have failures (fixed in later tasks).

### Step 5: Commit

```bash
git add ShellGame/GameScene.swift ShellGame/GameStateTests.swift
git commit -m "feat: expand LevelConfig to 30 levels with 5-cup tier

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Update GameState — level cap, survival check, level progression tests

**Files:**
- Modify: `ShellGame/GameState.swift` (lines 95, 192, 210–216)
- Modify: `ShellGame/GameStateTests.swift` (LevelProgressionTests class)

### Step 1: Write failing tests

Replace `LevelProgressionTests` in `ShellGame/GameStateTests.swift`:

```swift
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
        UserDefaults.standard.set(29, forKey: "cq_wins")
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
```

### Step 2: Run tests to verify they fail

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|LevelProgression)" | tail -20
```

Expected: `test_levelCapsAtThirty` and `test_survivalCountIncrements_atLevelThirty` FAIL.

### Step 3: Update `GameState.swift`

**3a.** Line 95 — change level cap in `init`:
```swift
level = mode == .solo ? min(wins + 1, 30) : 1
```

**3b.** Line 192 — change level cap in `playerTappedCup`:
```swift
level = min(wins + 1, 30)
```

**3c.** Line 210 — change survival check:
```swift
if level == 30 {
```

**3d.** Line 216 — update comment:
```swift
hostMessage = HostMessages.survival[min(survivalCount - 1, HostMessages.survival.count - 1)]
```
(Comment on previous line: `// Level 30 survival loop — keep winning forever`)

### Step 4: Run tests to verify they pass

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|LevelProgression|Prestige)" | tail -20
```

Expected: all LevelProgressionTests PASS. Note: PrestigeTests will now fail (`test_prestige_resetsLevelToOne` expects `state.level == 7` — fix in same step below).

**3e.** Also update `PrestigeTests` in `GameStateTests.swift` — `test_prestige_resetsLevelToOne` currently sets wins=6 to reach L7. It still works for testing prestige mechanics (prestige can be called regardless of level — the gate is in the UI). Just update the assertion comment:

In `test_prestige_resetsLevelToOne`, change:
```swift
UserDefaults.standard.set(6, forKey: "cq_wins")
let state = GameState()
XCTAssertEqual(state.level, 7)   // ← was L7 gate, now just any non-L1 level for test purposes
```
to:
```swift
UserDefaults.standard.set(6, forKey: "cq_wins")
let state = GameState()
XCTAssertEqual(state.level, 7)   // 6 wins → L7, used to verify prestige resets correctly
```
(No functional change needed — `wins=6` still gives `level=7` under the new cap of 30. The test still passes as written.)

### Step 5: Run full test suite

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "Executed|FAIL" | tail -5
```

Expected: all tests pass (38+ tests, 0 failures).

### Step 6: Commit

```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: raise level cap to 30, move survival loop to L30

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Update scoring formula — cup-tier multiplier

**Files:**
- Modify: `ShellGame/GameState.swift` (lines 182–186, solo scoring block)
- Modify: `ShellGame/GameStateTests.swift` (ScoringTests class)

### Step 1: Write failing scoring tests

Replace `ScoringTests` in `ShellGame/GameStateTests.swift`:

```swift
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
        // Simulate 3 wins to reach L4 (4-cup tier)
        let state = GameState()
        simulateWins(state, count: 3)   // L4, streak=3, streakMult=min(4,4)=4
        XCTAssertEqual(state.level, 4)
        // cupBase=13, level=4, streakMult=4  →  13*4*4 = 208
        XCTAssertEqual(state.lastScoreDelta, 208)
    }

    func test_fiveCupLevel_usesHighestBase() {
        // Reach L16 (5-cup tier): needs 15 wins
        let state = GameState()
        simulateWins(state, count: 15)  // L16, streak=15 → capped at 4
        XCTAssertEqual(state.level, 16)
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
```

### Step 2: Run tests to verify they fail

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|Scoring)" | tail -20
```

Expected: `test_fourCupLevel_usesHigherBase` and `test_fiveCupLevel_usesHighestBase` FAIL (formula not updated yet).

### Step 3: Update scoring formula in `GameState.swift`

Find the solo scoring block (around line 183). Replace:

```swift
let multiplier = min(streak + 1, 4)          // max 4× streak bonus
let delta = 10 * level * multiplier
```

with:

```swift
let multiplier = min(streak + 1, 4)          // max 4× streak bonus
let cupBase: Int = {
    switch LevelConfig.config(for: level).cupCount {
    case 5:  return 17   // 5-cup tier: 1.7× base
    case 4:  return 13   // 4-cup tier: 1.3× base
    default: return 10   // 3-cup tier: 1.0× base
    }
}()
let delta = cupBase * level * multiplier
```

### Step 4: Run tests to verify ScoringTests pass

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "(PASS|FAIL|Scoring)" | tail -20
```

Expected: all ScoringTests PASS.

### Step 5: Run full test suite

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "Executed|FAIL" | tail -5
```

Expected: all tests pass, 0 failures.

### Step 6: Commit

```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add cup-tier score multiplier (3→1.0×, 4→1.3×, 5→1.7×)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Update ModesView — prestige gate at L30

**Files:**
- Modify: `ShellGame/ModesView.swift` (lines 53, 115, 122, 136)

### Step 1: Update `loadStats()` in `ModesView.swift`

Line 53 — change level cap:
```swift
currentLevel = min(UserDefaults.standard.integer(forKey: "cq_wins") + 1, 30)
```

### Step 2: Update `prestigeCard` computed property

Line 115 — change gate condition:
```swift
let canPrestige = currentLevel >= 30
```

Line 122 — update locked subtitle:
```swift
: "Reach Level 30 to prestige.",
```

Line 136 — update alert message:
```swift
Text("Reset to Level 1 and earn 👑 Prestige \(prestigeCount + 1). Your high score, survival record, and gauntlet best are kept.")
```
(No change to alert body text needed — it's already level-agnostic.)

### Step 3: Build to verify it compiles

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' build 2>&1 \
  | grep -E "(error:|BUILD)" | tail -5
```

Expected: BUILD SUCCEEDED.

### Step 4: Run full test suite one final time

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=9D462949-D99F-446A-863B-6660FC351194' 2>&1 \
  | grep -E "Executed|FAIL" | tail -5
```

Expected: all tests pass, 0 failures.

### Step 5: Commit

```bash
git add ShellGame/ModesView.swift
git commit -m "feat: move prestige gate to L30

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
