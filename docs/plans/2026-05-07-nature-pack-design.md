# Cup Queen — Nature Pack: Earnable Cup Skins Design

**Date:** 2026-05-07
**Approach:** 6 free earnable cup skins, mixed achievement unlocks, progress counters in UI
**Scope:** CosmeticState · CustomizeView · ContentView · GameView · GauntletView · DailyChallengeView · iCloudSyncManager

---

## Goal

Add 6 new cup skins (the "Nature Pack") that players earn through gameplay — no IAP. Each skin targets a distinct activity (daily challenges, solo progression, duels, casual play, gauntlet, streaks), driving cross-mode engagement. Progress toward each skin is visible in CustomizeView. Unlock is celebrated with a toast + home screen badge.

---

## The 6 Skins

| Skin | ID | unlitTop | unlitBot | litTop | litBot | Unlock Condition |
|------|----|----------|----------|--------|--------|-----------------|
| 🌊 Ocean Teal | `oceanTeal` | RGB(0.02, 0.22, 0.30) | RGB(0.04, 0.35, 0.48) | RGB(0.06, 0.52, 0.68) | RGB(0.12, 0.72, 0.88) | Complete 5 Daily Challenges |
| 🌿 Emerald Forest | `emeraldForest` | RGB(0.02, 0.22, 0.08) | RGB(0.04, 0.38, 0.14) | RGB(0.06, 0.55, 0.20) | RGB(0.15, 0.75, 0.32) | Reach Level 10 in Solo |
| 🌸 Rose Gold | `roseGold` | RGB(0.45, 0.22, 0.22) | RGB(0.62, 0.38, 0.32) | RGB(0.78, 0.55, 0.45) | RGB(0.92, 0.72, 0.58) | Win 25 Duels |
| 🤍 Marble White | `marbleWhite` | RGB(0.55, 0.52, 0.50) | RGB(0.72, 0.70, 0.68) | RGB(0.85, 0.83, 0.82) | RGB(0.96, 0.95, 0.93) | Play 50 total rounds (any mode) |
| 🌅 Sunset Orange | `sunsetOrange` | RGB(0.45, 0.18, 0.02) | RGB(0.68, 0.30, 0.04) | RGB(0.88, 0.45, 0.08) | RGB(1.00, 0.65, 0.15) | Complete 3 Gauntlet runs |
| 🧊 Arctic Ice | `arcticIce` | RGB(0.20, 0.30, 0.42) | RGB(0.35, 0.50, 0.65) | RGB(0.55, 0.72, 0.88) | RGB(0.80, 0.92, 1.00) | Maintain a 14-day streak |

---

## Persistence

Three new UserDefaults keys:

| Key | Type | Meaning |
|-----|------|---------|
| `cq_daily_completed` | `Int` | Cumulative Daily Challenge completions |
| `cq_gauntlet_completed` | `Int` | Cumulative Gauntlet completions (win only, not loss) |
| `cq_total_rounds` | `Int` | Cumulative rounds played across all modes |

Existing keys reused for threshold checks:
- `cq_bestLevel` — Emerald Forest (Level 10)
- `cq_competition_wins` — Rose Gold (25 duels)
- `cq_ps_count` — Arctic Ice (14-day streak)

All three new keys added to `iCloudSyncManager.syncKeys`.

---

## Architecture

### `CosmeticState` additions

```swift
enum GameMode { case solo, daily, gauntlet, duel }

/// Call at end of every round. Returns name of newly-unlocked Nature Pack skin, or nil.
@discardableResult
func recordRound(mode: GameMode) -> String? { ... }

/// Returns (current, required, conditionLabel) for a locked cup skin, or nil if unlocked/not a nature pack skin.
func progress(for cupID: String) -> (current: Int, required: Int, label: String)? { ... }

/// True when a skin was unlocked since the player last opened CustomizeView.
var hasUnseenUnlock: Bool  // persisted to UserDefaults "cq_has_unseen_unlock"
```

`recordRound(mode:)` logic:
1. Increment `cq_total_rounds`
2. Increment mode-specific counter (`cq_daily_completed` for `.daily`, `cq_gauntlet_completed` for `.gauntlet`)
3. Check all 6 Nature Pack thresholds against current values
4. For each newly-crossed threshold: call `unlockCup(id:)`, set `hasUnseenUnlock = true`
5. Return name of first newly-unlocked skin (or `nil`)

### Call sites

| File | Where | Call |
|------|-------|------|
| `GameView.swift` | Result phase `.onAppear` (alongside existing `StreakManager.shared.recordRound()`) | `CosmeticState.shared.recordRound(mode: .solo)` |
| `DailyChallengeView.swift` | `resultOverlay.onAppear` (alongside existing `recordDailyAttempt` + `submitDailyScore`) | `CosmeticState.shared.recordRound(mode: .daily)` |
| `GauntletView.swift` | `resultOverlay.onAppear` when `gameState.gauntletComplete == true` only | `CosmeticState.shared.recordRound(mode: .gauntlet)` |

Duel wins already tracked in `cq_competition_wins` — Rose Gold threshold checked against this existing key in `recordRound()` without needing a new counter.

---

## UI Changes

### CustomizeView — progress counter on locked cups

Locked cup cells currently show a lock icon + condition text. Add a progress line below:

```
🔒  [Marble White preview]
    Play 50 rounds
    ████░░░  32 / 50        ← new line
```

`CosmeticState.progress(for: "marbleWhite")` returns `(32, 50, "rounds played")`.

### ContentView — red dot badge on Style button

When `CosmeticState.shared.hasUnseenUnlock == true`, overlay a filled red circle (8pt, system red) at `.topTrailing` of the Style button. Cleared when `CustomizeView` appears (set `hasUnseenUnlock = false`).

### GameView / GauntletView / DailyChallengeView — unlock toast

`recordRound()` returns newly-unlocked skin name → set `cosmeticUnlockToast: String?` state → reuses existing `.task(id: cosmeticUnlockToast)` toast pattern (3s auto-dismiss). Toast text: `"🌊 Ocean Teal unlocked!"`.

---

## Files Modified (6)

| File | Change |
|------|--------|
| `CosmeticState.swift` | 6 new CupTheme cases; `GameMode` enum; `recordRound(mode:)`; `progress(for:)`; `hasUnseenUnlock` |
| `CustomizeView.swift` | Progress counter (`X / Y label`) on locked cup cells; clear `hasUnseenUnlock` on `.onAppear` |
| `ContentView.swift` | Red dot badge overlay on Style button conditional on `hasUnseenUnlock` |
| `GameView.swift` | `recordRound(.solo)` call; `cosmeticUnlockToast` state + toast UI |
| `GauntletView.swift` | `recordRound(.gauntlet)` on `gauntletComplete` in result overlay |
| `DailyChallengeView.swift` | `recordRound(.daily)` in result overlay |
| `iCloudSyncManager.swift` | 3 new keys added to `syncKeys` |

---

## Success Criteria

- [ ] All 6 Nature Pack skins appear in CustomizeView with lock icon + progress counter
- [ ] Completing a Daily Challenge increments `cq_daily_completed`; Ocean Teal unlocks at 5
- [ ] Reaching Level 10 in Solo unlocks Emerald Forest (checked on `recordRound(.solo)`)
- [ ] 25 duel wins unlocks Rose Gold (checked against existing `cq_competition_wins`)
- [ ] 50 total rounds unlocks Marble White
- [ ] Completing (not losing) a Gauntlet run increments `cq_gauntlet_completed`; Sunset Orange unlocks at 3
- [ ] 14-day streak unlocks Arctic Ice (checked against existing `cq_ps_count`)
- [ ] Toast appears on result screen when a skin unlocks
- [ ] Red dot badge appears on Style button after unlock; clears when CustomizeView opened
- [ ] Skins apply correctly in home preview and in-game (GameScene)
- [ ] Progress counters survive app restart
- [ ] iCloud syncs all three new keys
- [ ] BUILD SUCCEEDED, 0 errors, all existing tests pass
