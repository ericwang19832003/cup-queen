# Continue / Fresh Start Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Continue (Level X) / Fresh Start" segmented picker to `PlayerNameEntryView` so players can choose between continuing from their saved level or starting at Level 1.

**Architecture:** `PlayerNameEntryView` reads saved wins from UserDefaults, shows a segmented control, and passes `startFresh: Bool` back via its `onPlay` closure. `ContentView` stores the choice and passes it to `GameView`, which passes it to `GameState.init`. `GameState.init` gets a new `startFresh: Bool = false` parameter — when `true`, `level = 1` regardless of persisted wins.

**Tech Stack:** SwiftUI, UserDefaults, existing codebase patterns (no new dependencies)

---

### Task 1: Extend GameState.init with startFresh parameter

**Files:**
- Modify: `ShellGame/GameState.swift` (init at line ~99)
- Modify: `ShellGame/GameStateTests.swift` (add tests)

**Current init line (109):**
```swift
level = mode == .solo ? min(wins + 1, 30) : 1
```

**Step 1: Add failing test**

In `GameStateTests.swift`, add a new `StartFreshTests` class:

```swift
final class StartFreshTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Give the player some saved wins so we can tell the difference
        UserDefaults.standard.set(4, forKey: "cq_wins")
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "cq_wins")
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
```

**Step 2: Run tests — expect FAIL** (startFresh parameter doesn't exist yet)

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED|test_startFresh" | tail -20
```

**Step 3: Update GameState.init**

Change the signature from:
```swift
init(mode: GameMode = .solo) {
```
to:
```swift
init(mode: GameMode = .solo, startFresh: Bool = false) {
```

Change line 109 from:
```swift
level = mode == .solo ? min(wins + 1, 30) : 1
```
to:
```swift
level = (mode == .solo && !startFresh) ? min(wins + 1, 30) : 1
```

**Step 4: Run tests — expect PASS**

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "FAILED|PASSED|error:" | tail -10
```

**Step 5: Commit**
```bash
git add ShellGame/GameState.swift ShellGame/GameStateTests.swift
git commit -m "feat: add startFresh parameter to GameState.init"
```

---

### Task 2: Wire startFresh through PlayerNameEntryView → ContentView → GameView

**Files:**
- Modify: `ShellGame/PlayerNameEntryView.swift`
- Modify: `ShellGame/ContentView.swift`
- Modify: `ShellGame/GameView.swift`

**Spec:**

**PlayerNameEntryView:**
- Change `onPlay: () -> Void` to `onPlay: (Bool) -> Void` where the Bool is `startFresh`
- Add `@State private var startFresh: Bool = false`
- Read saved wins: `let savedWins = UserDefaults.standard.integer(forKey: "cq_wins")`, compute `savedLevel = min(savedWins + 1, 30)`
- Add segmented picker BELOW the TextField, ABOVE the Play button:
  - When `savedLevel == 1`: hide the picker entirely (both options would show Level 1 — no choice needed)
  - When `savedLevel > 1`: show two-segment picker:
    - Segment 0: `"Continue  Lv.\(savedLevel)"` → `startFresh = false`
    - Segment 1: `"Fresh Start"` → `startFresh = true`
  - Default selected: segment 0 (Continue)
- Pass `startFresh` to `onPlay(startFresh)` when Play tapped
- Sheet height: increase from `.height(320)` to `.height(360)` to fit the extra control (only when picker is shown; use `.height(savedLevel > 1 ? 360 : 320)`)

Segmented picker styling — match game aesthetic (use `.colorMultiply` or a custom segmented style; a plain `Picker` with `.pickerStyle(.segmented)` is acceptable):
```swift
Picker("Mode", selection: $startFresh) {
    Text("Continue  Lv.\(savedLevel)").tag(false)
    Text("Fresh Start").tag(true)
}
.pickerStyle(.segmented)
.padding(.horizontal, 32)
```

**ContentView:**
- Add `@State private var startFreshSelected: Bool = false`
- In the sheet's `PlayerNameEntryView` `onPlay` closure, capture `startFresh`:
  ```swift
  PlayerNameEntryView { startFresh in
      startFreshSelected = startFresh
      playWasTapped = true
      showNameEntry = false
  }
  ```
- In `.navigationDestination`:
  ```swift
  .navigationDestination(isPresented: $navigateToGame) {
      GameView(startFresh: startFreshSelected)
  }
  ```

**GameView:**
- Add `let startFresh: Bool` stored property (defaulting to `false` for all other call sites — GauntletView, DailyChallengeView use their own GameState(mode:) init and are unaffected)
- Change `@StateObject private var gameState = GameState()` to:
  ```swift
  @StateObject private var gameState: GameState
  init(startFresh: Bool = false) {
      self.startFresh = startFresh
      _gameState = StateObject(wrappedValue: GameState(mode: .solo, startFresh: startFresh))
  }
  ```

**Step 1: Build first to confirm baseline passes**
```bash
xcodebuild build -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

**Step 2: Update PlayerNameEntryView** (as above)

**Step 3: Update ContentView** (as above)

**Step 4: Update GameView** (as above)

**Step 5: Build — expect SUCCEED**
```bash
xcodebuild build -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -5
```

**Step 6: Run all tests — expect all pass**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "FAILED|PASSED|error:" | tail -10
```

**Step 7: Commit**
```bash
git add ShellGame/PlayerNameEntryView.swift ShellGame/ContentView.swift ShellGame/GameView.swift
git commit -m "feat: add Continue/Fresh Start picker to PlayerNameEntryView"
```
