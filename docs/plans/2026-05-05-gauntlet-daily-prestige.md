# Gauntlet + Daily Challenge + Prestige Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unlock three new modes (Gauntlet, Daily Challenge, Prestige) when a player first reaches Level 7, giving long-term players new goals and a daily return habit.

**Architecture:** `GameState` gains a `GameMode` enum parameter controlling how wins/level behave. `GauntletView` and `DailyChallengeView` each own their own `GameState(mode:)` + `GameScene` instances, reusing existing animation components. `ModesView` is a fullScreenCover from `ContentView`.

**Tech Stack:** SwiftUI, SpriteKit, UserDefaults (no new dependencies)

---

## Task 1: Add GameMode enum + update GameState

**Files:**
- Modify: `ShellGame/GameState.swift`
- Modify: `ShellGame/GameStateTests.swift`

**Step 1: Add GameMode enum and new PK keys at the top of GameState.swift**

Add after the existing `private enum PK` block:

```swift
enum GameMode {
    case solo       // normal persistent play
    case gauntlet   // single-life L1→L7 run, no persistence
    case daily      // one fixed-seed round per day
}
```

Add to `PK` enum:
```swift
static let bestGauntlet = "cq_best_gauntlet"
static let prestige      = "cq_prestige"
static let dailyStreak   = "cq_daily_streak"
static let dailyLastDate = "cq_daily_last_date"
```

**Step 2: Add new published properties to GameState**

Add after existing `@Published` properties:

```swift
// Gauntlet
@Published private(set) var gauntletLevel: Int = 1       // current level in run (1–7)
@Published private(set) var gauntletOver: Bool = false    // run ended (loss or complete)
@Published private(set) var gauntletComplete: Bool = false // all 7 levels cleared
@Published private(set) var bestGauntlet: Int = 0

// Prestige
@Published private(set) var prestigeCount: Int = 0

// Daily
@Published private(set) var dailyStreak: Int = 0
```

Also add private mode storage:
```swift
private let mode: GameMode
```

**Step 3: Update init to accept mode**

Replace current `init()` with:

```swift
init(mode: GameMode = .solo) {
    self.mode = mode
    wins        = UserDefaults.standard.integer(forKey: PK.wins)
    highScore   = UserDefaults.standard.integer(forKey: PK.highScore)
    bestLevel   = max(1, UserDefaults.standard.integer(forKey: PK.bestLevel))
    bestSurvival = UserDefaults.standard.integer(forKey: PK.bestSurvival)
    bestGauntlet = UserDefaults.standard.integer(forKey: PK.bestGauntlet)
    prestigeCount = UserDefaults.standard.integer(forKey: PK.prestige)
    dailyStreak   = UserDefaults.standard.integer(forKey: PK.dailyStreak)
    // In non-solo modes, level always starts at 1 regardless of persisted wins
    level        = mode == .solo ? min(wins + 1, 7) : 1
    isFTUERound  = !UserDefaults.standard.bool(forKey: PK.ftueDone)
}
```

**Step 4: Write failing tests**

Add to `GameStateTests.swift` in `LevelProgressionTests`:

```swift
func test_gauntletMode_startsAtLevelOne_regardlessOfWins() {
    // Persist some wins first
    UserDefaults.standard.set(6, forKey: "cq_wins")
    let gauntlet = GameState(mode: .gauntlet)
    XCTAssertEqual(gauntlet.level, 1, "Gauntlet always starts at L1")
    XCTAssertEqual(gauntlet.gauntletLevel, 1)
    XCTAssertFalse(gauntlet.gauntletOver)
    XCTAssertFalse(gauntlet.gauntletComplete)
}
```

**Step 5: Run test — expect FAIL**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' \
  -only-testing:ShellGameTests/LevelProgressionTests/test_gauntletMode_startsAtLevelOne_regardlessOfWins \
  2>&1 | grep -E "passed|failed|error"
```
Expected: FAIL ("incorrect argument label" or wrong value)

**Step 6: Implement changes from Steps 1–3, then run test**
```bash
xcodebuild test ... 2>&1 | grep -E "passed|failed"
```
Expected: PASS

**Step 7: Commit**
```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add GameMode enum and non-solo init to GameState"
```

---

## Task 2: Gauntlet win/loss logic in GameState

**Files:**
- Modify: `ShellGame/GameState.swift`
- Modify: `ShellGame/GameStateTests.swift`

**Step 1: Write failing tests**

Add a new `GauntletTests` class to `GameStateTests.swift`:

```swift
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
        let wrong = (state.correctCupIndex + 1) % state.level.cupCount
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
        // bestGauntlet saved on run end — simulate run end via loss
        state.advanceToChoosing()
        let wrong = (state.correctCupIndex + 1) % 4
        state.playerTappedCup(wrong)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cq_best_gauntlet"), scoreAfter3)
    }
}

// Add helper extension
extension Int {
    var cupCount: Int { self >= 2 ? 4 : 3 }
}
```

**Step 2: Run tests — expect FAIL**
```bash
xcodebuild test ... -only-testing:ShellGameTests/GauntletTests 2>&1 | grep -E "passed|failed"
```

**Step 3: Update playerTappedCup in GameState**

In `playerTappedCup`, replace the existing `if correct { ... } else { ... }` block with mode branching. Add at the top of the method, before the existing logic:

```swift
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
```

Keep the existing solo/daily logic below (guard `mode == .solo || mode == .daily`).

**Step 4: Run gauntlet tests**
```bash
xcodebuild test ... -only-testing:ShellGameTests/GauntletTests 2>&1 | grep -E "passed|failed"
```
Expected: all 4 PASS

**Step 5: Run full test suite to check no regressions**
```bash
xcodebuild test ... 2>&1 | grep "Executed"
```
Expected: 29 tests, 0 failures

**Step 6: Commit**
```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add gauntlet win/loss logic to GameState"
```

---

## Task 3: Prestige logic in GameState

**Files:**
- Modify: `ShellGame/GameState.swift`
- Modify: `ShellGame/GameStateTests.swift`

**Step 1: Write failing tests**

Add to `GameStateTests.swift`:

```swift
final class PrestigeTests: XCTestCase {
    override func setUp()    { super.setUp(); clearGameDefaults() }
    override func tearDown() { super.tearDown(); clearGameDefaults() }

    func test_prestige_resetsLevelToOne() {
        // Set up L7 state
        UserDefaults.standard.set(6, forKey: "cq_wins")
        let state = GameState()
        XCTAssertEqual(state.level, 7)

        state.prestige()

        // New GameState should now start at L1
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
```

**Step 2: Run tests — expect FAIL**

**Step 3: Add prestige() method to GameState**

Add after `consumeAdTrigger()`:

```swift
/// Resets solo progression to L1 and awards a prestige badge.
/// Keeps: highScore, bestLevel, bestSurvival, bestGauntlet, score history.
func prestige() {
    UserDefaults.standard.removeObject(forKey: PK.wins)
    UserDefaults.standard.removeObject(forKey: PK.ftueDone)
    prestigeCount += 1
    UserDefaults.standard.set(prestigeCount, forKey: PK.prestige)
    wins  = 0
    level = 1
    isFTUERound = true
}
```

**Step 4: Run tests — expect PASS**

**Step 5: Run full suite**
```bash
xcodebuild test ... 2>&1 | grep "Executed"
```
Expected: 33 tests, 0 failures

**Step 6: Commit**
```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add prestige() to GameState with full test coverage"
```

---

## Task 4: Daily Challenge logic in GameState

**Files:**
- Modify: `ShellGame/GameState.swift`
- Modify: `ShellGame/GameStateTests.swift`

**Step 1: Add daily helpers to GameState**

Add a new public computed property and method:

```swift
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

/// Records today's daily attempt result (call after round ends in daily mode).
func recordDailyAttempt(won: Bool) {
    let today = GameState.todayUTCString
    UserDefaults.standard.set(true, forKey: "cq_daily_\(today)")

    // Update streak
    let lastDate = UserDefaults.standard.string(forKey: PK.dailyLastDate) ?? ""
    let yesterday = { () -> String in
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date().addingTimeInterval(-86400))
    }()
    if lastDate == yesterday {
        dailyStreak += 1
    } else if lastDate != today {
        dailyStreak = 1
    }
    UserDefaults.standard.set(dailyStreak, forKey: PK.dailyStreak)
    UserDefaults.standard.set(today, forKey: PK.dailyLastDate)
}
```

**Step 2: Write daily tests**

```swift
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
        // Simulate yesterday being recorded
        let yesterday = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return f.string(from: Date().addingTimeInterval(-86400))
        }()
        UserDefaults.standard.set(yesterday, forKey: "cq_daily_last_date")
        UserDefaults.standard.set(3, forKey: "cq_daily_streak")

        let state = GameState()
        state.recordDailyAttempt(won: true)
        XCTAssertEqual(state.dailyStreak, 4, "Streak increments when previous day was also played")
    }
}
```

**Step 3: Run — expect PASS (logic is pure, no UI dependency)**

**Step 4: Run full suite**
Expected: 37 tests, 0 failures

**Step 5: Commit**
```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add daily challenge helpers and streak logic to GameState"
```

---

## Task 5: Create ModesView

**Files:**
- Create: `ShellGame/ModesView.swift`

**Step 1: Create ModesView.swift**

```swift
// ModesView.swift
// fullScreenCover shown from ContentView when player taps "Modes".
// Three cards: Gauntlet, Daily Challenge, Prestige.

import SwiftUI

struct ModesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showGauntlet = false
    @State private var showDaily    = false
    @State private var showPrestigeAlert = false

    // Stats read from UserDefaults
    @State private var bestGauntlet: Int  = 0
    @State private var prestigeCount: Int = 0
    @State private var dailyStreak: Int   = 0
    @State private var dailyAttempted: Bool = false
    @State private var currentLevel: Int  = 1

    var body: some View {
        ZStack {
            casinoBackground
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                header
                Spacer().frame(height: 24)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        gauntletCard
                        dailyCard
                        prestigeCard
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { loadStats() }
        .fullScreenCover(isPresented: $showGauntlet, onDismiss: loadStats) {
            GauntletView()
        }
        .fullScreenCover(isPresented: $showDaily, onDismiss: loadStats) {
            DailyChallengeView()
        }
    }

    private func loadStats() {
        bestGauntlet   = UserDefaults.standard.integer(forKey: "cq_best_gauntlet")
        prestigeCount  = UserDefaults.standard.integer(forKey: "cq_prestige")
        dailyStreak    = UserDefaults.standard.integer(forKey: "cq_daily_streak")
        dailyAttempted = GameState().isDailyAttempted
        currentLevel   = min(UserDefaults.standard.integer(forKey: "cq_wins") + 1, 7)
    }

    // MARK: - Background
    private var casinoBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                     Color(red: 0.12, green: 0.04, blue: 0.26),
                     Color(red: 0.05, green: 0.02, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text("MODES")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.80))
                .tracking(5)
            Spacer()
            Color.clear.frame(width: 24)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Gauntlet Card
    private var gauntletCard: some View {
        modeCard(
            icon: "flame.fill",
            iconColor: Color(red: 1, green: 0.45, blue: 0.15),
            title: "Gauntlet",
            subtitle: "One life. L1 → L7. No retries.",
            stat: bestGauntlet > 0 ? "Best: \(bestGauntlet) pts" : "Not attempted",
            ctaLabel: "Start Run",
            ctaAction: { showGauntlet = true },
            accentColor: Color(red: 1, green: 0.45, blue: 0.15)
        )
    }

    // MARK: - Daily Card
    private var dailyCard: some View {
        modeCard(
            icon: "calendar",
            iconColor: Color(red: 0.30, green: 0.75, blue: 1.00),
            title: "Daily Challenge",
            subtitle: dailyAttempted ? "Come back tomorrow!" : "Today's puzzle awaits.",
            stat: dailyStreak > 0 ? "🔥 \(dailyStreak)-day streak" : "No streak yet",
            ctaLabel: dailyAttempted ? "Attempted" : "Play Today",
            ctaAction: dailyAttempted ? nil : { showDaily = true },
            accentColor: Color(red: 0.30, green: 0.75, blue: 1.00)
        )
    }

    // MARK: - Prestige Card
    private var prestigeCard: some View {
        let canPrestige = currentLevel == 7
        return modeCard(
            icon: "crown.fill",
            iconColor: Color(red: 1, green: 0.80, blue: 0.22),
            title: "Prestige",
            subtitle: canPrestige
                ? "Reset to L1. Keep your records. Earn a crown."
                : "Reach Level 7 to prestige.",
            stat: prestigeCount > 0 ? "👑 × \(prestigeCount)" : "Not yet prestiged",
            ctaLabel: canPrestige ? "Prestige Now" : "Not Available",
            ctaAction: canPrestige ? { showPrestigeAlert = true } : nil,
            accentColor: Color(red: 1, green: 0.80, blue: 0.22)
        )
        .alert("Prestige?", isPresented: $showPrestigeAlert) {
            Button("Prestige", role: .destructive) {
                let state = GameState()
                state.prestige()
                loadStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reset to Level 1 and earn 👑 Prestige \(prestigeCount + 1). Your high score, survival record, and gauntlet best are kept.")
        }
    }

    // MARK: - Reusable Card Builder
    private func modeCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        stat: String,
        ctaLabel: String,
        ctaAction: (() -> Void)?,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(iconColor)
                    .shadow(color: iconColor.opacity(0.60), radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Text(stat)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor.opacity(0.80))
            }
            if let action = ctaAction {
                Button(action: action) {
                    Text(ctaLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
            } else {
                Text(ctaLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
```

**Step 2: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED (after registering the file in Task 8)

---

## Task 6: Create GauntletView

**Files:**
- Create: `ShellGame/GauntletView.swift`

**Step 1: Create GauntletView.swift**

```swift
// GauntletView.swift
// Single-life L1→L7 gauntlet run. Reuses GameScene + existing animation stack.
// Uses GameState(mode: .gauntlet) — solo wins/level are never modified.

import SwiftUI
import SpriteKit
import GameKit

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
                phaseIndicator.padding(.top, 12)

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
            if gameState.phase == .result { resultOverlay }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.phase)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
        }
        .onAppear(perform: setupScene)
        .onChange(of: gameState.level) { _ in
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

    // MARK: - Phase Indicator (reuse GameView's style)
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

    // MARK: - Gauntlet HUD (progress bar + score)
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

            // Score + level label
            HStack(spacing: 0) {
                hudCell(label: "SCORE", value: "\(gameState.score)")
                Rectangle().fill(Color.yellow.opacity(0.35)).frame(width: 1, height: 44)
                hudCell(label: "RUN", value: "L\(gameState.gauntletLevel)/7")
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
        VStack(spacing: 6) {
            Text("LEVEL UP!").font(.system(size: 32, weight: .black, design: .rounded)).foregroundColor(.black)
            Text("L\(gameState.gauntletLevel - 1) → L\(gameState.gauntletLevel) 🔥")
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
        let won = gameState.isCorrect == true
        let complete = gameState.gauntletComplete
        let emoji    = complete ? "🏆" : won ? "✨" : "💀"
        let headline = complete ? "PERFECT RUN!" : won ? "Advancing..." : "Run Over"
        let sub      = complete
            ? "You cleared all 7 levels!"
            : won
                ? "Level \(gameState.gauntletLevel - 1) cleared!"
                : "Fell at Level \(gameState.gauntletLevel)"

        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onAppear {
                    if complete || gameState.gauntletOver {
                        GameCenterManager.shared.submitGauntletScore(gameState.score)
                    }
                    // Auto-advance to next gauntlet level on non-terminal win
                    if won && !complete && !gameState.gauntletOver {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { handleNextLevel() }
                    }
                }

            VStack(spacing: 20) {
                Text(emoji).font(.system(size: 74))
                Text(headline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(won ? .yellow : Color(red: 1, green: 0.9, blue: 0.9))
                Text(sub)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))

                if gameState.gauntletOver || complete {
                    Text("\(gameState.score) pts")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    if gameState.score == gameState.bestGauntlet && gameState.score > 0 {
                        Text("New Personal Best! 🎉")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    Button(action: { handleRestart() }) {
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
        // Use gauntletLevel for scene difficulty
        scene?.level = gameState.gauntletLevel
        scene?.isFTUERound = isFTUE
        scene?.placeBall(atCupIndex: gameState.correctCupIndex)
    }

    private func handleNextLevel() {
        scene?.level = gameState.gauntletLevel
        scene?.resetForNewRound()
        gameState.resetToIdle()
        SoundManager.shared.startGameAmbient(level: gameState.gauntletLevel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { startRound() }
    }

    private func handleRestart() {
        // Dismiss and reopen — simplest way to reset a fresh GameState
        dismiss()
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
        DispatchQueue.main.async { self.gameState.playerTappedCup(cupIndex) }
    }
}
```

**Step 2: Add `submitGauntletScore` to GameCenterManager**

Open `ShellGame/GameCenterMatchManager.swift` (or wherever `GameCenterManager` lives — find with grep) and add:

```swift
func submitGauntletScore(_ score: Int) {
    guard isAuthenticated, score > 0 else { return }
    GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
        leaderboardIDs: ["cq.leaderboard.gauntlet"]) { _ in }
}
```

**Step 3: Build check**
```bash
xcodebuild ... build 2>&1 | tail -3
```

---

## Task 7: Create DailyChallengeView

**Files:**
- Create: `ShellGame/DailyChallengeView.swift`

**Step 1: Create DailyChallengeView.swift**

```swift
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

    /// Fixed config for every daily challenge — consistent difficulty worldwide.
    private static let dailyConfig = LevelConfig(
        cupCount: 4, swapCount: 15, swapDuration: 0.20,
        arcHeight: 60, hasMidPause: true, hasGhostEffect: false
    )

    var body: some View {
        ZStack {
            casinoBackground
            if alreadyAttempted {
                alreadyAttemptedOverlay
            } else {
                gameContent
                if gameState.phase == .result { resultOverlay }
            }
        }
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gameState.phase)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
        }
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

            // Host message bubble
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
        // Override the scene's config by controlling level via a special value
        // We use level=4 as proxy since dailyConfig matches that difficulty range.
        // The coordinator sets shuffleSeed to today's deterministic seed.
        let s = GameScene(size: CGSize(width: 390, height: 310))
        s.level = 4   // 4-cup layout; config overridden via seed + fixed swapCount from coordinator
        let seed = GameState.dailySeed
        // correctCupIndex also seeded so all players face same starting position
        let dailyCorrectCup = Int(seed % 4)
        let coord = DailyCoordinator(gameState: gameState, scene: s,
                                     dailySeed: seed, correctCup: dailyCorrectCup)
        s.shellDelegate = coord
        coordinator = coord
        scene = s
        SoundManager.shared.startGameAmbient(level: 4)
        // Manually set correctCupIndex via beginRound then override
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            gameState.beginRound()
            // Force the correct cup to the seeded index
            // (beginRound sets a random one; coordinator overrides scene placement)
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
                // Inject today's deterministic seed so all players get same shuffle
                self.scene?.shuffleSeed = self.dailySeed
                self.scene?.performShuffle()
            }
        }
    }
    func sceneDidFinishShuffling() {
        DispatchQueue.main.async { self.gameState.didFinishShuffling() }
    }
    func sceneDidRevealCup(_ cupIndex: Int) {
        // Override correctCupIndex comparison with our seeded value
        DispatchQueue.main.async {
            // Directly call the phase transition — result determined by seeded cup
            self.gameState.playerTappedCupDaily(cupIndex, correctCup: self.correctCup)
        }
    }
}
```

**Step 2: Add `playerTappedCupDaily` to GameState**

In `GameState.swift`, add after `playerTappedCup`:

```swift
/// Daily mode variant — correctCupIndex is caller-supplied (seeded), not the internal random value.
func playerTappedCupDaily(_ cupIndex: Int, correctCup: Int) {
    guard phase == .choosing else { return }
    phase = .revealing
    let correct = cupIndex == correctCup
    isCorrect = correct
    lastScoreDelta = correct ? 10 * 4 * 1 : 0   // fixed L4 equivalent, no streak
    if !correct { hostMessage = HostMessages.lose.randomElement()! }
    else        { hostMessage = "You found it! 🎯" }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
        guard self?.phase == .revealing else { return }
        self?.phase = .result
    }
}
```

**Step 3: Add `submitDailyScore` to GameCenterManager**

```swift
func submitDailyScore(_ score: Int) {
    guard isAuthenticated else { return }
    GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
        leaderboardIDs: ["cq.leaderboard.daily"]) { _ in }
}
```

---

## Task 8: Update ContentView (Modes button + prestige crown)

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Step 1: Add state variables**

In `ContentView`, add to the `@State` block:

```swift
@State private var showModes       = false
@State private var savedPrestige: Int = 0
@State private var modesUnlocked: Bool = false
```

**Step 2: Add Modes button to body VStack**

After `duelButton` / before `footerText`:

```swift
modesButton
Spacer().frame(height: 6)
```

**Step 3: Add prestige crown to titleSection**

In `titleSection`, wrap the existing `ZStack(alignment: .topTrailing)` — add a prestige crown in `.topLeading`:

```swift
// Prestige crowns — shown when savedPrestige > 0
if savedPrestige > 0 {
    HStack(spacing: 2) {
        ForEach(0..<min(savedPrestige, 3), id: \.self) { _ in
            Text("👑").font(.system(size: 13))
        }
    }
    .offset(x: -4, y: 2)
}
```

Place this inside the `ZStack(alignment: .topTrailing)` as a leading-aligned sibling, or add it below the title `VStack`.

**Step 4: Add `modesButton` computed property**

```swift
private var modesButton: some View {
    Button {
        if modesUnlocked { showModes = true }
    } label: {
        HStack(spacing: 8) {
            Image(systemName: modesUnlocked ? "star.circle.fill" : "lock.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(modesUnlocked ? "✦ Modes" : "Unlock at Level 7")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .foregroundColor(modesUnlocked
            ? Color(red: 0.78, green: 0.58, blue: 1.00)
            : .white.opacity(0.28))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(modesUnlocked
                      ? Color(red: 0.35, green: 0.10, blue: 0.60).opacity(0.22)
                      : Color.white.opacity(0.05))
                .overlay(Capsule().strokeBorder(
                    modesUnlocked
                        ? Color(red: 0.65, green: 0.40, blue: 1.00).opacity(0.45)
                        : Color.white.opacity(0.10),
                    lineWidth: 1.2))
        )
    }
    .disabled(!modesUnlocked)
}
```

**Step 5: Add `.fullScreenCover` for ModesView**

After the existing `.fullScreenCover(isPresented: $showDuelLobby)`:

```swift
.fullScreenCover(isPresented: $showModes) {
    ModesView()
}
```

**Step 6: Update `onAppear` to load new stats**

```swift
savedPrestige   = UserDefaults.standard.integer(forKey: "cq_prestige")
modesUnlocked   = UserDefaults.standard.integer(forKey: "cq_bestLevel") >= 7
```

**Step 7: Update `resetProgress()` to also clear prestige prompt**

The existing `resetProgress()` already calls `ScoreStore.shared.clear()`. Also add:
```swift
ud.removeObject(forKey: "cq_prestige")
savedPrestige = 0
modesUnlocked = false
```

---

## Task 9: Register new files in project.pbxproj

**Files:**
- Modify: `ShellGame.xcodeproj/project.pbxproj`

**Step 1: Add 3 new PBXBuildFile entries** (after existing AA2000000000000000000014 line):

```
AA2000000000000000000015 /* ModesView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000000000000000000016 /* ModesView.swift */; };
AA2000000000000000000016 /* GauntletView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000000000000000000017 /* GauntletView.swift */; };
AA2000000000000000000017 /* DailyChallengeView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000000000000000000018 /* DailyChallengeView.swift */; };
```

**Step 2: Add 3 new PBXFileReference entries** (after existing AA1000000000000000000015 line):

```
AA1000000000000000000016 /* ModesView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ModesView.swift; sourceTree = "<group>"; };
AA1000000000000000000017 /* GauntletView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GauntletView.swift; sourceTree = "<group>"; };
AA1000000000000000000018 /* DailyChallengeView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DailyChallengeView.swift; sourceTree = "<group>"; };
```

**Step 3: Add to PBXGroup children** (after AA1000000000000000000015 ScoreboardView line):

```
AA1000000000000000000016 /* ModesView.swift */,
AA1000000000000000000017 /* GauntletView.swift */,
AA1000000000000000000018 /* DailyChallengeView.swift */,
```

**Step 4: Add to PBXSourcesBuildPhase files** (after AA2000000000000000000014 line):

```
AA2000000000000000000015 /* ModesView.swift in Sources */,
AA2000000000000000000016 /* GauntletView.swift in Sources */,
AA2000000000000000000017 /* DailyChallengeView.swift in Sources */,
```

---

## Task 10: Build, test, commit

**Step 1: Full build**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 2: Full test suite**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' 2>&1 | grep "Executed"
```
Expected: ≥37 tests, 0 failures

**Step 3: Final commit**
```bash
git add ShellGame/ ShellGame.xcodeproj/
git commit -m "feat: add Gauntlet, Daily Challenge, and Prestige modes (unlocked at L7)"
```

---

## Success Criteria Checklist

- [ ] `GameState(mode: .gauntlet)` initializes at level 1 regardless of persisted wins
- [ ] Gauntlet win advances `gauntletLevel`, loss sets `gauntletOver = true`
- [ ] Gauntlet never modifies solo `wins` or `highScore`
- [ ] `bestGauntlet` persisted and shown in ModesView card
- [ ] Daily seed is identical on same UTC day across fresh `GameState` instances
- [ ] Second daily attempt blocked by `isDailyAttempted` gate
- [ ] Daily streak increments on consecutive days
- [ ] `prestige()` resets wins/ftueDone, increments `cq_prestige`, keeps highScore
- [ ] Modes button locked below L7, unlocked at L7 (permanent)
- [ ] 👑 crown shows in ContentView title area after first prestige
- [ ] All existing 25 tests pass, new tests ≥12 all pass
- [ ] BUILD SUCCEEDED with 0 errors
