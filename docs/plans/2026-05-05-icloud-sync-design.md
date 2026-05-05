# Design: iCloud Key-Value Sync
**Date:** 2026-05-05  
**Status:** Approved  
**Context:** All game progress is local-only (UserDefaults). Players who switch devices or reinstall lose everything. iCloud KV Store solves this with zero registration.

---

## Problem

Player progress (level, high score, prestige, daily streak, etc.) is stored entirely in UserDefaults on one device. A new iPhone, reinstall, or second device means starting over. No account or registration exists.

---

## Solution

Use `NSUbiquitousKeyValueStore` (iCloud Key-Value Store) to mirror all 9 persistence keys to iCloud. Uses the player's existing Apple ID — zero registration, zero backend, zero cost.

---

## Keys Synced

| UserDefaults Key | Type | Description |
|-----------------|------|-------------|
| `cq_wins` | Int | Cumulative solo wins → determines level |
| `cq_highScore` | Int | All-time high score |
| `cq_bestLevel` | Int | Highest level ever reached |
| `cq_ftue_done` | Bool | First-time user experience flag |
| `cq_bestSurvival` | Int | Best consecutive L7 survival count |
| `cq_best_gauntlet` | Int | Best gauntlet run score |
| `cq_prestige` | Int | Prestige count (crown badge) |
| `cq_daily_streak` | Int | Consecutive daily challenge days |
| `cq_daily_last_date` | String | Last daily attempt date (UTC yyyy-MM-dd) |

---

## Architecture

### `iCloudSyncManager` (new singleton)

Wraps `NSUbiquitousKeyValueStore`. Responsibilities:

1. **Write** — after each round, prestige, or daily attempt, push all 9 keys to iCloud
2. **Read** — on app launch and foreground return, pull iCloud values
3. **Conflict detect** — compare iCloud vs local for each key; if any differ, emit a conflict notification

```swift
final class iCloudSyncManager {
    static let shared = iCloudSyncManager()
    private let store = NSUbiquitousKeyValueStore.default
    
    func push()                          // local → iCloud
    func pull() -> Bool                  // iCloud → local; returns true if any value changed
    func hasConflict() -> Bool           // true if any iCloud value ≠ local value
    func applyLocal()                    // overwrite iCloud with all local values
    func applyiCloud()                   // overwrite local with all iCloud values
}
```

### `iCloudConflictView` (new SwiftUI sheet)

Shown from `ContentView` when `iCloudSyncManager.hasConflict()` returns true on appear.

```
┌─────────────────────────────────────┐
│  Your progress differs across       │
│  devices. Which should we keep?     │
├──────────────────┬──────────────────┤
│  THIS DEVICE     │  ICLOUD          │
│  Level 5         │  Level 7         │
│  High Score 340  │  High Score 890  │
│  Best Gauntlet 0 │  Best Gauntlet 120│
│  Prestige 0      │  Prestige 1  👑  │
│  Streak 2 days   │  Streak 5 days   │
├──────────────────┴──────────────────┤
│  [Keep This Device]  [Use iCloud]   │
└─────────────────────────────────────┘
```

One tap resolves all keys — no per-key cherry-picking. After resolution, `ContentView` reloads all `saved*` state vars.

---

## Data Flow

### App Launch
```
App opens
  → iCloudSyncManager.pull()
  → hasConflict()?
      Yes → show iCloudConflictView sheet
      No  → silently apply iCloud values (new device gets remote progress)
  → ContentView loads saved* state vars from UserDefaults
```

### After Each Round / Prestige / Daily
```
GameState updates UserDefaults
  → iCloudSyncManager.push()   // fire-and-forget
```

### App Foreground (ScenePhase.active)
```
Same as App Launch flow
```

---

## Conflict Resolution Rules

- **Conflict defined:** any single key has different values in iCloud vs local UserDefaults
- **Resolution:** player chooses one source; all 9 keys from that source are applied atomically
- **No partial merge:** simpler UX, avoids impossible states (e.g. prestige=1 but wins=0)
- **After resolution:** iCloud and local are identical; no conflict until next divergent write

---

## New Files

| File | Purpose |
|------|---------|
| `iCloudSyncManager.swift` | Singleton wrapping NSUbiquitousKeyValueStore |
| `iCloudConflictView.swift` | Conflict resolution sheet UI |

## Modified Files

| File | Change |
|------|--------|
| `GameState.swift` | Call `iCloudSyncManager.shared.push()` after writes in `playerTappedCup`, `prestige()`, `recordDailyAttempt()` |
| `ContentView.swift` | Check for conflict on `.onAppear` and `.onChange(of: scenePhase)`; show conflict sheet; reload saved* vars after resolution |
| `ShellGameApp.swift` | Enable iCloud KV entitlement check on launch |

## Not In Scope

- Per-key conflict resolution (cherry-picking)
- `cq_score_history` sync (large JSON; Game Center leaderboard is the canonical archive)
- `cq_daily_YYYYMMDD` per-day attempt flags (ephemeral; not worth syncing)
- Push notifications for sync events

---

## Success Criteria

1. Fresh install on Device B shows Device A's progress after iCloud sync (no conflict sheet)
2. Offline divergence on two devices triggers conflict sheet on next launch
3. Choosing "Use iCloud" overwrites local and dismisses sheet; ContentView reflects new values
4. Choosing "Keep This Device" overwrites iCloud and dismisses sheet
5. All existing 38 tests still pass
6. Build succeeds with iCloud entitlement enabled
