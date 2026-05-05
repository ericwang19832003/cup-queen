# iCloud Key-Value Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Mirror all 9 game-progress keys to iCloud KV Store so progress survives device switches, with a conflict-resolution sheet when two devices diverge.

**Architecture:** `iCloudSyncManager` wraps `NSUbiquitousKeyValueStore` and is called from `GameState` after every write. `ContentView` checks for conflicts on appear/foreground and shows `iCloudConflictView` when detected. No backend, no registration — uses the player's existing Apple ID.

**Tech Stack:** SwiftUI, `NSUbiquitousKeyValueStore`, `@Environment(\.scenePhase)`, UserDefaults

---

## ⚠️ Manual Pre-Step: Enable iCloud Capability in Xcode

Before running any code:
1. Open `ShellGame.xcodeproj` in Xcode
2. Select the `ShellGame` target → **Signing & Capabilities**
3. Click **+ Capability** → add **iCloud**
4. Under iCloud, check **Key-value storage**

This adds the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. Without it, `NSUbiquitousKeyValueStore` silently does nothing.

---

## Task 1: Create iCloudSyncManager

**Files:**
- Create: `ShellGame/iCloudSyncManager.swift`
- Modify: `ShellGame.xcodeproj/project.pbxproj`

**Step 1: Create `ShellGame/iCloudSyncManager.swift`**

```swift
// iCloudSyncManager.swift
// Mirrors all game-progress UserDefaults keys to NSUbiquitousKeyValueStore.
// No backend, no registration — uses the player's Apple ID automatically.

import Foundation

final class iCloudSyncManager {

    static let shared = iCloudSyncManager()
    private let store = NSUbiquitousKeyValueStore.default

    /// All keys synced between UserDefaults and iCloud KV Store.
    static let syncKeys: [String] = [
        "cq_wins", "cq_highScore", "cq_bestLevel", "cq_ftue_done",
        "cq_bestSurvival", "cq_best_gauntlet", "cq_prestige",
        "cq_daily_streak", "cq_daily_last_date"
    ]

    private init() {}

    // MARK: - Push (local → iCloud)

    /// Copies all local UserDefaults values to iCloud KV Store.
    /// Call after any UserDefaults write in GameState.
    func push() {
        for key in Self.syncKeys {
            if let val = UserDefaults.standard.object(forKey: key) {
                store.set(val, forKey: key)
            } else {
                store.removeObject(forKey: key)
            }
        }
        store.synchronize()
    }

    // MARK: - Conflict Detection

    /// True if both local and iCloud have a value for any key AND they differ.
    /// A key that exists only on one side is NOT a conflict (it's a new device or key).
    func hasConflict() -> Bool {
        for key in Self.syncKeys {
            guard let remote = store.object(forKey: key),
                  let local  = UserDefaults.standard.object(forKey: key) else { continue }
            if "\(remote)" != "\(local)" { return true }
        }
        return false
    }

    // MARK: - Resolution

    /// Overwrites local UserDefaults with all iCloud values.
    func applyiCloud() {
        for key in Self.syncKeys {
            if let val = store.object(forKey: key) {
                UserDefaults.standard.set(val, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Overwrites iCloud with all local UserDefaults values.
    func applyLocal() {
        push()
    }

    // MARK: - Snapshots (for conflict UI)

    /// Current iCloud values for all sync keys.
    func remoteSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Self.syncKeys {
            if let val = store.object(forKey: key) { out[key] = val }
        }
        return out
    }

    /// Current local UserDefaults values for all sync keys.
    func localSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Self.syncKeys {
            if let val = UserDefaults.standard.object(forKey: key) { out[key] = val }
        }
        return out
    }

    // MARK: - Silent New-Device Apply

    /// Called on app launch when no conflict exists but iCloud has data local doesn't.
    /// Silently brings a fresh device up to speed.
    func silentlyApplyRemoteIfNewer() {
        guard !hasConflict() else { return }
        for key in Self.syncKeys {
            // Only apply if local is missing the key but iCloud has it
            if UserDefaults.standard.object(forKey: key) == nil,
               let remote = store.object(forKey: key) {
                UserDefaults.standard.set(remote, forKey: key)
            }
        }
    }
}
```

**Step 2: Register in project.pbxproj**

In `ShellGame.xcodeproj/project.pbxproj`:

Add to **PBXBuildFile section** (after the `DailyChallengeView` line):
```
AA2000000000000000000018 /* iCloudSyncManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000000000000000000019 /* iCloudSyncManager.swift */; };
```

Add to **PBXFileReference section** (after `DailyChallengeView` line):
```
AA1000000000000000000019 /* iCloudSyncManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = iCloudSyncManager.swift; sourceTree = "<group>"; };
```

Add to **PBXGroup children** (after `DailyChallengeView` line):
```
AA1000000000000000000019 /* iCloudSyncManager.swift */,
```

Add to **PBXSourcesBuildPhase files** (after `DailyChallengeView` line):
```
AA2000000000000000000018 /* iCloudSyncManager.swift in Sources */,
```

**Step 3: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**
```bash
git add ShellGame/iCloudSyncManager.swift ShellGame.xcodeproj/project.pbxproj
git commit -m "feat: add iCloudSyncManager with push/pull/conflict detection"
```

---

## Task 2: Create iCloudConflictView

**Files:**
- Create: `ShellGame/iCloudConflictView.swift`
- Modify: `ShellGame.xcodeproj/project.pbxproj`

**Step 1: Create `ShellGame/iCloudConflictView.swift`**

```swift
// iCloudConflictView.swift
// Sheet shown when iCloud and local game progress diverge.
// Player picks one source; all 9 keys are applied from that source atomically.

import SwiftUI

struct iCloudConflictView: View {
    let localSnapshot:  [String: Any]
    let remoteSnapshot: [String: Any]
    let onKeepLocal:  () -> Void
    let onUseRemote:  () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.12, green: 0.04, blue: 0.26)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Icon + headline
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00))
                    .shadow(color: Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.65), radius: 12)

                Text("Progress Conflict")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Your progress differs between this device and iCloud.\nChoose which to keep.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Comparison table
                HStack(spacing: 12) {
                    snapshotColumn(title: "THIS DEVICE",
                                   snapshot: localSnapshot,
                                   accentColor: Color(red: 1, green: 0.72, blue: 0.20))
                    snapshotColumn(title: "ICLOUD",
                                   snapshot: remoteSnapshot,
                                   accentColor: Color(red: 0.30, green: 0.75, blue: 1.00))
                }
                .padding(.horizontal, 20)

                // Buttons
                VStack(spacing: 12) {
                    Button(action: onKeepLocal) {
                        Text("Keep This Device")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color(red: 1, green: 0.85, blue: 0.20),
                                         Color(red: 1, green: 0.65, blue: 0.05)],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    Button(action: onUseRemote) {
                        Text("Use iCloud")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color(red: 0.30, green: 0.75, blue: 1.00),
                                         Color(red: 0.15, green: 0.55, blue: 0.90)],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    // MARK: - Column builder
    private func snapshotColumn(title: String,
                                 snapshot: [String: Any],
                                 accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .tracking(2)

            ForEach(displayRows(from: snapshot), id: \.label) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    Text(row.value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(accentColor.opacity(0.30), lineWidth: 1))
        )
    }

    private struct DisplayRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private func displayRows(from snapshot: [String: Any]) -> [DisplayRow] {
        let wins    = snapshot["cq_wins"]         as? Int ?? 0
        let high    = snapshot["cq_highScore"]    as? Int ?? 0
        let surv    = snapshot["cq_bestSurvival"] as? Int ?? 0
        let gaunt   = snapshot["cq_best_gauntlet"] as? Int ?? 0
        let prest   = snapshot["cq_prestige"]     as? Int ?? 0
        let streak  = snapshot["cq_daily_streak"] as? Int ?? 0
        return [
            DisplayRow(label: "Level",        value: "Level \(min(wins + 1, 7))"),
            DisplayRow(label: "High Score",   value: "\(high) pts"),
            DisplayRow(label: "Best Survival",value: surv > 0 ? "×\(surv)" : "—"),
            DisplayRow(label: "Best Gauntlet",value: gaunt > 0 ? "\(gaunt) pts" : "—"),
            DisplayRow(label: "Prestige",     value: prest > 0 ? "👑 ×\(prest)" : "—"),
            DisplayRow(label: "Daily Streak", value: streak > 0 ? "🔥 \(streak)d" : "—"),
        ]
    }
}
```

**Step 2: Register in project.pbxproj** (same pattern as Task 1, next IDs):

PBXBuildFile:
```
AA2000000000000000000019 /* iCloudConflictView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA100000000000000000001A /* iCloudConflictView.swift */; };
```

PBXFileReference:
```
AA100000000000000000001A /* iCloudConflictView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = iCloudConflictView.swift; sourceTree = "<group>"; };
```

PBXGroup children:
```
AA100000000000000000001A /* iCloudConflictView.swift */,
```

PBXSourcesBuildPhase files:
```
AA2000000000000000000019 /* iCloudConflictView.swift in Sources */,
```

**Step 3: Build to verify**
```bash
xcodebuild ... build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**
```bash
git add ShellGame/iCloudConflictView.swift ShellGame.xcodeproj/project.pbxproj
git commit -m "feat: add iCloudConflictView — conflict resolution sheet UI"
```

---

## Task 3: Wire push() calls into GameState

**Files:**
- Modify: `ShellGame/GameState.swift`

The three write-heavy methods need a single `iCloudSyncManager.shared.push()` call appended after all their UserDefaults writes.

**Step 1: Add push after solo playerTappedCup**

In `playerTappedCup`, find the closing comment `// TODO: ANALYTICS` block (~line 235) and add push **before** it:

```swift
        // Advance to result after reveal animation finishes (~1.8 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.phase == .revealing else { return }
            self?.phase = .result
        }

        // Sync progress to iCloud after each round
        if mode == .solo { iCloudSyncManager.shared.push() }

        // TODO: ANALYTICS — Analytics.log(.roundComplete, correct: correct, level: level)
```

**Step 2: Add push after prestige()**

At the end of `prestige()`:

```swift
    func prestige() {
        UserDefaults.standard.removeObject(forKey: PK.wins)
        UserDefaults.standard.removeObject(forKey: PK.ftueDone)
        prestigeCount += 1
        UserDefaults.standard.set(prestigeCount, forKey: PK.prestige)
        wins  = 0
        level = 1
        isFTUERound = true
        iCloudSyncManager.shared.push()
    }
```

**Step 3: Add push after recordDailyAttempt()**

At the end of `recordDailyAttempt(won:)`:

```swift
        UserDefaults.standard.set(dailyStreak, forKey: PK.dailyStreak)
        UserDefaults.standard.set(today, forKey: PK.dailyLastDate)
        iCloudSyncManager.shared.push()
    }
```

**Step 4: Build**
```bash
xcodebuild ... build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 5: Run full test suite**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' 2>&1 | grep "Executed"
```
Expected: 38 tests, 0 failures (`push()` is a no-op in simulator without entitlement — tests are unaffected)

**Step 6: Commit**
```bash
git add ShellGame/GameState.swift
git commit -m "feat: push progress to iCloud after each solo round, prestige, and daily attempt"
```

---

## Task 4: Update ContentView — conflict detection + sheet

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Step 1: Add new state variables** (in the `@State` block, after `modesUnlocked`):

```swift
@State private var showConflict    = false
@State private var localSnap:  [String: Any] = [:]
@State private var remoteSnap: [String: Any] = [:]
```

Also add scene phase environment at the top of `ContentView`:
```swift
@Environment(\.scenePhase) private var scenePhase
```

**Step 2: Add conflict check helper**

Add a private method to `ContentView`:

```swift
private func checkiCloudConflict() {
    let mgr = iCloudSyncManager.shared
    mgr.silentlyApplyRemoteIfNewer()   // handles fresh device (no conflict)
    if mgr.hasConflict() {
        localSnap  = mgr.localSnapshot()
        remoteSnap = mgr.remoteSnapshot()
        showConflict = true
    }
}
```

**Step 3: Add reload helper** (consolidate existing onAppear reads):

```swift
private func reloadStats() {
    savedHighScore    = UserDefaults.standard.integer(forKey: "cq_highScore")
    savedBestLevel    = max(1, UserDefaults.standard.integer(forKey: "cq_bestLevel"))
    savedBestSurvival = UserDefaults.standard.integer(forKey: "cq_bestSurvival")
    savedPrestige     = UserDefaults.standard.integer(forKey: "cq_prestige")
    modesUnlocked     = savedBestLevel >= 7
}
```

**Step 4: Update `.onAppear` to use the new helpers**

Replace the existing `.onAppear` block:

```swift
.onAppear {
    startAnimations()
    checkiCloudConflict()
    reloadStats()
    SoundManager.shared.startHomeAmbient()
}
```

**Step 5: Add `.onChange(of: scenePhase)` for foreground re-check**

After the existing `.onChange(of: showDuelLobby)` block:

```swift
.onChange(of: scenePhase) { phase in
    if phase == .active {
        checkiCloudConflict()
        reloadStats()
    }
}
```

**Step 6: Add the conflict sheet**

After the `.fullScreenCover(isPresented: $showModes)` block:

```swift
.sheet(isPresented: $showConflict) {
    iCloudConflictView(
        localSnapshot:  localSnap,
        remoteSnapshot: remoteSnap,
        onKeepLocal: {
            iCloudSyncManager.shared.applyLocal()
            showConflict = false
            reloadStats()
        },
        onUseRemote: {
            iCloudSyncManager.shared.applyiCloud()
            showConflict = false
            reloadStats()
        }
    )
}
```

**Step 7: Build**
```bash
xcodebuild ... build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 8: Run full test suite**
```bash
xcodebuild test ... 2>&1 | grep "Executed"
```
Expected: 38 tests, 0 failures

**Step 9: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: show iCloud conflict sheet on launch and foreground; reload stats after resolution"
```

---

## Task 5: Final build + push

**Step 1: Full build**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 2: Full test suite**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' 2>&1 | grep "Executed"
```
Expected: 38 tests, 0 failures

**Step 3: Final commit + push**
```bash
git add -A
git commit -m "feat: iCloud KV sync — cross-device progress with conflict resolution"
git push origin main
```

---

## Success Criteria Checklist

- [ ] `iCloudSyncManager.push()` is called after every UserDefaults write in GameState
- [ ] Fresh device silently receives iCloud progress (no conflict sheet)
- [ ] Diverged devices show the conflict sheet with a two-column comparison
- [ ] "Keep This Device" overwrites iCloud; "Use iCloud" overwrites local; both dismiss the sheet
- [ ] ContentView `saved*` vars reload correctly after conflict resolution
- [ ] All 38 existing tests pass
- [ ] `BUILD SUCCEEDED` with no errors
