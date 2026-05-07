# Nature Pack — Earnable Cup Skins Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 6 earnable "Nature Pack" cup skins to Cup Queen, each unlocked through a different gameplay achievement, with progress counters in CustomizeView and a home-screen badge when a skin unlocks.

**Architecture:** `CosmeticState` gains a `recordRound(mode:)` method that increments gameplay counters and checks Nature Pack unlock thresholds. Unlock feedback flows via the existing milestone-toast pattern in each game mode's result screen, plus a `hasUnseenUnlock` flag that drives a red-dot badge on the Style button in ContentView.

**Tech Stack:** SwiftUI, UserDefaults (persistence), existing `CosmeticState` / `StreakManager` / iCloud sync infrastructure.

---

### Task 1: CosmeticState — 6 new themes, GameMode enum, recordRound, progress, hasUnseenUnlock

**Files:**
- Modify: `ShellGame/CosmeticState.swift`
- Test: `ShellGame/GameStateTests.swift`

---

**Step 1: Write failing tests in GameStateTests.swift**

Append this class at the bottom of `ShellGame/GameStateTests.swift`:

```swift
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
        // Remove any previously-unlocked nature-pack skins so tests start clean
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
        let name = CosmeticState.shared.recordRound(mode: .solo)   // 50th round
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
        // Simulate player who already hit level 10 before Nature Pack shipped.
        UserDefaults.standard.set(10, forKey: "cq_bestLevel")
        CosmeticState.shared.reloadFromDefaults()
        XCTAssertTrue(CosmeticState.shared.unlockedCups.contains("emeraldForest"))
        // Retroactive unlock must NOT set hasUnseenUnlock (don't spam the badge on update)
        XCTAssertFalse(CosmeticState.shared.hasUnseenUnlock)
    }
}
```

**Step 2: Run tests to confirm they all fail**

```bash
cd /Users/minwang/cup_game/ShellGame
xcodebuild test -scheme ShellGame -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "FAIL|error:|CosmeticState"
```

Expected: compile errors — `recordRound`, `reloadFromDefaults`, `clearUnseenUnlock`, `progress(for:)`, `hasUnseenUnlock`, `GameMode` not found.

**Step 3: Add 6 new CupTheme cases to CosmeticState.swift**

In `CosmeticState.swift`, replace line 61:
```swift
    static let all: [CupTheme] = [.classicRed, .gold, .midnight, .crimsonQueen, .diamond, .diamondAnimated]
```
With:
```swift
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
```

**Step 4: Add GameMode enum and new K keys**

In `CosmeticState.swift`, after line 146 (`static let earnableBalls...`), add:

```swift
    // Game mode enum used by recordRound.
    enum GameMode { case solo, daily, gauntlet, duel }
```

Inside the `private enum K` block (after `static let unlockedTables`), add:
```swift
        static let dailyCompleted    = "cq_daily_completed"
        static let gauntletCompleted = "cq_gauntlet_completed"
        static let totalRounds       = "cq_total_rounds"
        static let hasUnseenUnlock   = "cq_has_unseen_unlock"
```

**Step 5: Add hasUnseenUnlock property and Nature Pack methods**

In `CosmeticState.swift`, add after the `@Published private(set) var unlockedTables` line (line 137):

```swift
    @Published private(set) var hasUnseenUnlock: Bool = false
```

Add a new `// MARK: - Nature Pack` section just before `// MARK: - Persistence` (before line 216 `private func load()`):

```swift
    // MARK: - Nature Pack

    /// Call at end of every completed round. Returns the name of a newly-unlocked
    /// Nature Pack skin, or nil. Sets hasUnseenUnlock when something unlocks.
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

    /// Returns progress toward a Nature Pack skin's unlock condition, or nil if
    /// the skin is not in the Nature Pack (or is already unlocked).
    func progress(for cupID: String) -> (current: Int, required: Int, label: String)? {
        guard !unlockedCups.contains(cupID) else { return nil }
        let ud = UserDefaults.standard
        switch cupID {
        case "oceanTeal":
            return (min(ud.integer(forKey: K.dailyCompleted), 5), 5, "Daily Challenges")
        case "emeraldForest":
            return (min(ud.integer(forKey: "cq_bestLevel"), 10), 10, "Solo Level")
        case "roseGold":
            return (min(ud.integer(forKey: "cq_competition_wins"), 25), 25, "Duel Wins")
        case "marbleWhite":
            return (min(ud.integer(forKey: K.totalRounds), 50), 50, "Rounds Played")
        case "sunsetOrange":
            return (min(ud.integer(forKey: K.gauntletCompleted), 3), 3, "Gauntlets Completed")
        case "arcticIce":
            return (min(ud.integer(forKey: "cq_ps_count"), 14), 14, "Day Streak")
        default:
            return nil
        }
    }

    /// Clears the unseen-unlock badge. Call when CustomizeView appears.
    func clearUnseenUnlock() {
        hasUnseenUnlock = false
        UserDefaults.standard.set(false, forKey: K.hasUnseenUnlock)
    }

    @discardableResult
    private func checkNaturePackUnlocks(announce: Bool) -> String? {
        let ud = UserDefaults.standard
        let thresholds: [(String, String, Bool)] = [
            ("oceanTeal",     "🌊 Ocean Teal",     ud.integer(forKey: K.dailyCompleted) >= 5),
            ("emeraldForest", "🌿 Emerald Forest",  ud.integer(forKey: "cq_bestLevel") >= 10),
            ("roseGold",      "🌸 Rose Gold",       ud.integer(forKey: "cq_competition_wins") >= 25),
            ("marbleWhite",   "🤍 Marble White",    ud.integer(forKey: K.totalRounds) >= 50),
            ("sunsetOrange",  "🌅 Sunset Orange",   ud.integer(forKey: K.gauntletCompleted) >= 3),
            ("arcticIce",     "🧊 Arctic Ice",      ud.integer(forKey: "cq_ps_count") >= 14),
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
```

**Step 6: Call checkNaturePackUnlocks and load hasUnseenUnlock in load()**

In `CosmeticState.swift`, inside `private func load()`, add two lines at the end (after line 233):

```swift
        hasUnseenUnlock = ud.bool(forKey: K.hasUnseenUnlock)
        checkNaturePackUnlocks(announce: false)   // retroactive unlock for existing players, silent
```

**Step 7: Run tests — expect pass**

```bash
cd /Users/minwang/cup_game/ShellGame
xcodebuild test -scheme ShellGame -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "PASS|FAIL|error:|CosmeticState"
```

Expected: all `CosmeticStateNaturePackTests` pass. All previously passing tests still pass.

**Step 8: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/CosmeticState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add Nature Pack — 6 earnable cup skins with recordRound, progress, and unlock tracking"
```

---

### Task 2: CustomizeView — progress counter on locked Nature Pack cells

**Files:**
- Modify: `ShellGame/CustomizeView.swift`

**Background:** `CupSkinCell` currently shows a plain lock icon for skins that are neither purchasable nor earned (the milestone-only branch, lines 141–146). Nature Pack skins fall into this branch. We'll add a `progress` parameter to show `"X / Y Condition"` for earnable skins.

**Step 1: Add progress parameter to CupSkinCell**

In `CustomizeView.swift`, find `private struct CupSkinCell: View` (line 104). Replace the struct definition and body to add the `progress` parameter and conditional display:

Replace the parameter block (lines 104–110):
```swift
private struct CupSkinCell: View {
    let theme: CupTheme
    let isActive: Bool
    let isUnlocked: Bool
    let isPurchasing: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void
```
With:
```swift
private struct CupSkinCell: View {
    let theme: CupTheme
    let isActive: Bool
    let isUnlocked: Bool
    let isPurchasing: Bool
    let progress: (current: Int, required: Int, label: String)?
    let onSelect: () -> Void
    let onPurchase: () -> Void
```

Then replace the `else` branch at lines 141–146 (the milestone-only lock icon):
```swift
            } else {
                // Milestone-only
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
```
With:
```swift
            } else if let prog = progress {
                VStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                    Text("\(prog.current) / \(prog.required)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                    Text(prog.label)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
            } else {
                // Milestone-only (no progress path)
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
```

**Step 2: Pass progress to CupSkinCell in CustomizeView body**

In `CustomizeView.swift`, find the `CupSkinCell(` call (lines 31–39). Add the `progress:` argument:

```swift
                        ForEach(CupTheme.all, id: \.id) { theme in
                            CupSkinCell(
                                theme: theme,
                                isActive: cosmetics.activeCup.id == theme.id,
                                isUnlocked: cosmetics.unlockedCups.contains(theme.id),
                                isPurchasing: isPurchasing,
                                progress: cosmetics.progress(for: theme.id),
                                onSelect: { cosmetics.selectCup(theme) },
                                onPurchase: { purchase(productID: CosmeticState.purchasableCups[theme.id]) }
                            )
                        }
```

**Step 3: Clear hasUnseenUnlock when CustomizeView appears**

In `CustomizeView.swift`, add `.onAppear` to the outermost `NavigationStack` (after the closing `}` of `.alert`, before line 85's closing `}`):

```swift
        .onAppear {
            CosmeticState.shared.clearUnseenUnlock()
        }
```

**Step 4: Build to verify**

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame/ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/CustomizeView.swift
git commit -m "feat: show Nature Pack progress counters on locked cup cells in CustomizeView"
```

---

### Task 3: ContentView — red dot badge on Style button

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Background:** When `CosmeticState.shared.hasUnseenUnlock` is true, show a small red dot at `.topTrailing` of the Style button. The dot disappears when CustomizeView is opened (Task 2 already calls `clearUnseenUnlock()` there). ContentView needs to observe CosmeticState to react to the published `hasUnseenUnlock` property.

**Step 1: Add @StateObject for CosmeticState in ContentView**

In `ContentView.swift`, find the `@State private var showCustomize: Bool = false` line (line 44). Add directly before it:

```swift
    @StateObject private var cosmeticState = CosmeticState.shared
```

**Step 2: Add red dot overlay to Style button**

In `ContentView.swift`, find the Style button block (lines 652–669):

```swift
            // Style
            Button { showCustomize = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Style")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(red: 1, green: 0.60, blue: 0.80))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.35, green: 0.05, blue: 0.20).opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(red: 1, green: 0.60, blue: 0.80).opacity(0.40), lineWidth: 1.5))
                )
            }
```

Replace the outer `Button` block with:

```swift
            // Style
            Button { showCustomize = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Style")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(red: 1, green: 0.60, blue: 0.80))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.35, green: 0.05, blue: 0.20).opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(red: 1, green: 0.60, blue: 0.80).opacity(0.40), lineWidth: 1.5))
                )
                .overlay(alignment: .topTrailing) {
                    if cosmeticState.hasUnseenUnlock {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: -6, y: 6)
                    }
                }
            }
```

**Step 3: Build to verify**

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame/ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/ContentView.swift
git commit -m "feat: show red dot badge on Style button when a new Nature Pack skin is unlocked"
```

---

### Task 4: GameView — recordRound(.solo) and cosmetic unlock toast

**Files:**
- Modify: `ShellGame/GameView.swift`

**Background:** GameView already calls `StreakManager.shared.recordRound()` when the phase transitions to `.result` (lines 146–154). We add `CosmeticState.shared.recordRound(mode: .solo)` right after. If a skin unlocks AND no streak milestone is toasting, display the skin name in `milestoneToast` (reuses existing toast infrastructure).

**Step 1: Add cosmetic unlock call in the phase-transition handler**

In `GameView.swift`, find lines 145–154:

```swift
            // Streak: record round completion and surface any milestone toast
            if newPhase == .result {
                let newMilestones = StreakManager.shared.recordRound()
                if let day = newMilestones.sorted().first,
                   let reward = StreakManager.milestoneRewards[day] {
                    withAnimation {
                        milestoneToast = "🔥 Day \(day) streak!\n\(reward) unlocked"
                    }
                }
            }
```

Replace with:

```swift
            // Streak + cosmetic: record round completion and surface any toast
            if newPhase == .result {
                let newMilestones = StreakManager.shared.recordRound()
                if let day = newMilestones.sorted().first,
                   let reward = StreakManager.milestoneRewards[day] {
                    withAnimation {
                        milestoneToast = "🔥 Day \(day) streak!\n\(reward) unlocked"
                    }
                }
                // Nature Pack unlock check (only toast if no streak milestone showing)
                if milestoneToast == nil,
                   let skinName = CosmeticState.shared.recordRound(mode: .solo) {
                    withAnimation { milestoneToast = "\(skinName) unlocked!" }
                }
            }
```

**Step 2: Build to verify**

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame/ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/GameView.swift
git commit -m "feat: call CosmeticState.recordRound(.solo) on result phase, show skin unlock toast"
```

---

### Task 5: GauntletView — recordRound(.gauntlet) and toast on completion

**Files:**
- Modify: `ShellGame/GauntletView.swift`

**Background:** GauntletView has its own `resultOverlay` computed property. We only record a gauntlet "completion" (toward Sunset Orange) when `gameState.gauntletComplete == true` — losing doesn't count. The view needs a `cosmeticToast` @State and toast UI inside the result ZStack.

**Step 1: Add @State cosmeticToast to GauntletView**

Find `struct GauntletView: View {` in `GauntletView.swift`. In the body of the struct, after the existing `@State` declarations, add:

```swift
    @State private var cosmeticToast: String? = nil
```

**Step 2: Add toast display inside resultOverlay**

In `GauntletView.swift`, find the ZStack inside `resultOverlay` (the one that starts at `return ZStack {` around line 193). After the `VStack(spacing: 20) { ... }` block (the main result content) and before the closing `}` of the ZStack, add:

```swift
            // Cosmetic unlock toast
            if let toast = cosmeticToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(Color(red: 0.10, green: 0.06, blue: 0.28).opacity(0.92)))
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: cosmeticToast) {
                    guard cosmeticToast != nil else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { cosmeticToast = nil }
                }
            }
```

**Step 3: Call recordRound(.gauntlet) in the result onAppear**

In `GauntletView.swift`, find the `.onAppear` on `Color.black.opacity(0.72)` inside `resultOverlay` (around line 195):

```swift
                .onAppear {
                    GameCenterManager.shared.submitGauntletScore(gameState.score)
                }
```

Replace with:

```swift
                .onAppear {
                    GameCenterManager.shared.submitGauntletScore(gameState.score)
                    if gameState.gauntletComplete,
                       let skinName = CosmeticState.shared.recordRound(mode: .gauntlet) {
                        withAnimation { cosmeticToast = "\(skinName) unlocked!" }
                    }
                }
```

**Step 4: Build to verify**

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame/ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/GauntletView.swift
git commit -m "feat: record gauntlet completion in CosmeticState, show skin unlock toast on perfect run"
```

---

### Task 6: DailyChallengeView — recordRound(.daily) and toast

**Files:**
- Modify: `ShellGame/DailyChallengeView.swift`

**Background:** Same pattern as Task 5. Daily Challenge's result overlay fires for both wins and losses. We call `recordRound(.daily)` unconditionally (completing the challenge counts regardless of outcome — it's about showing up, not winning).

**Step 1: Add @State cosmeticToast to DailyChallengeView**

In `DailyChallengeView.swift`, find the `@State` declarations at the top of the struct. Add:

```swift
    @State private var cosmeticToast: String? = nil
```

**Step 2: Add toast display inside resultOverlay**

In `DailyChallengeView.swift`, find the ZStack inside `resultOverlay` (around line 132). After the main `VStack(spacing: 20)` block and before the ZStack's closing `}`, add:

```swift
            // Cosmetic unlock toast
            if let toast = cosmeticToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(Color(red: 0.02, green: 0.08, blue: 0.28).opacity(0.92)))
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: cosmeticToast) {
                    guard cosmeticToast != nil else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { cosmeticToast = nil }
                }
            }
```

**Step 3: Call recordRound(.daily) in result onAppear**

In `DailyChallengeView.swift`, find the `.onAppear` inside `resultOverlay` (lines 134–137):

```swift
                .onAppear {
                    gameState.recordDailyAttempt(won: won)
                    GameCenterManager.shared.submitDailyScore(won ? 1 : 0)
                }
```

Replace with:

```swift
                .onAppear {
                    gameState.recordDailyAttempt(won: won)
                    GameCenterManager.shared.submitDailyScore(won ? 1 : 0)
                    if let skinName = CosmeticState.shared.recordRound(mode: .daily) {
                        withAnimation { cosmeticToast = "\(skinName) unlocked!" }
                    }
                }
```

**Step 4: Build to verify**

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame/ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/DailyChallengeView.swift
git commit -m "feat: record daily challenge completion in CosmeticState, show skin unlock toast"
```

---

### Task 7: iCloudSyncManager — add 3 new keys

**Files:**
- Modify: `ShellGame/iCloudSyncManager.swift`

**Background:** The three new counters (`cq_daily_completed`, `cq_gauntlet_completed`, `cq_total_rounds`) must sync across devices so unlock progress isn't lost when switching iPhone to iPad. `cq_has_unseen_unlock` is intentionally excluded — it's per-device UI state.

**Step 1: Add the 3 keys to syncKeys**

In `iCloudSyncManager.swift`, find line 20:

```swift
        "cq_cos_cup", "cq_cos_ball", "cq_cos_table",
        "cq_cos_unlocked_cups", "cq_cos_unlocked_balls", "cq_cos_unlocked_tables"
    ]
```

Replace with:

```swift
        "cq_cos_cup", "cq_cos_ball", "cq_cos_table",
        "cq_cos_unlocked_cups", "cq_cos_unlocked_balls", "cq_cos_unlocked_tables",
        "cq_daily_completed", "cq_gauntlet_completed", "cq_total_rounds"
    ]
```

**Step 2: Build and run all tests**

```bash
cd /Users/minwang/cup_game
xcodebuild test -scheme ShellGame -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`, `** TEST SUCCEEDED **`

**Step 3: Commit**

```bash
cd /Users/minwang/cup_game
git add ShellGame/iCloudSyncManager.swift
git commit -m "feat: sync Nature Pack progress counters via iCloud KV store"
```

---

### Task 8: Final build verification

**Files:** None (read-only verification)

**Step 1: Run full test suite**

```bash
cd /Users/minwang/cup_game
xcodebuild test -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test Suite|PASS|FAIL|error:"
```

Expected: All test suites pass. 0 failures.

**Step 2: Check all 6 Nature Pack skins visible in CupTheme.all**

```bash
grep -c "oceanTeal\|emeraldForest\|roseGold\|marbleWhite\|sunsetOrange\|arcticIce" \
  /Users/minwang/cup_game/ShellGame/CosmeticState.swift
```

Expected: at least 12 (6 definitions × 2 references each in thresholds + all array).

**Step 3: Verify iCloud syncKeys count**

```bash
grep -c "cq_" /Users/minwang/cup_game/ShellGame/iCloudSyncManager.swift
```

Expected: 23 (was 19, added 3 Nature Pack counters = 22, plus the grep pattern hits `cq_` once per key).

**Step 4: Verify design doc success criteria**

Review `docs/plans/2026-05-07-nature-pack-design.md` success criteria checklist against the implementation.

**Step 5: Final commit**

```bash
cd /Users/minwang/cup_game
git add .
git commit -m "chore: Nature Pack implementation complete — 6 earnable cup skins with progress tracking and unlock feedback"
```
