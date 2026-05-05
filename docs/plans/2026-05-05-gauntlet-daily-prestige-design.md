# Design: Gauntlet + Daily Challenge + Prestige
**Date:** 2026-05-05  
**Status:** Approved  
**Context:** Players who reach Level 7 have no new content to pursue. This design unlocks three new modes at L7 to provide long-term retention goals.

---

## Problem

Once a player reaches Level 7, they are permanently stuck at that level. The endless survival mode (escalating swap count) exists but is invisible and resets each session. There is no explicit new content, no reason to return daily, and no way to voluntarily restart as a meaningful gameplay choice. Players feel "done."

---

## Solution Overview

Three interlocking features, all gated behind first L7 reach:

| Feature | Core Loop | Retention Driver |
|---------|-----------|-----------------|
| **Gauntlet** | Single-life L1→L7 run | Skill mastery, perfect run chase |
| **Daily Challenge** | One attempt per day, global leaderboard | Daily return habit |
| **Prestige** | Voluntary reset to L1, earns crown badge | Replayability, identity/status |

---

## Unlock Gate

- `cq_modes_unlocked` (UserDefaults `Bool`) — set `true` when `bestLevel >= 7`
- Checked in `ContentView` to show/gray the Modes button
- Once unlocked, never re-locks (even after Prestige)

---

## Navigation

`ContentView` adds a **"Modes"** button between the Duel button and the footer.
- **Locked state:** grayed capsule, label "🔒 Unlock at Level 7"
- **Unlocked state:** purple/gold capsule, label "✦ Modes"
- Tapping opens `ModesView` as a `fullScreenCover`

`ModesView` is a single screen with three cards stacked vertically:
1. Gauntlet
2. Daily Challenge  
3. Prestige

---

## Feature 1: Gauntlet Mode

### Concept
A single-life sequential run from Level 1 through Level 7. One round per level. One mistake ends the run.

### Game Config
- Level N round uses `LevelConfig.config(for: N)` exactly — same difficulty as solo play
- Correct pick → advance to next level
- Wrong pick → run ends immediately, show result screen
- Completing all 7 levels = "Perfect Run"

### State
`GameMode.gauntlet` added to `GameState`. New properties:
- `gauntletLevel: Int` — current level in the run (1–7), separate from solo `level`
- `gauntletScore: Int` — accumulates using existing scoring formula
- `cq_best_gauntlet: Int` (UserDefaults) — best gauntlet score ever

### HUD
During gauntlet, the score HUD changes:
- SCORE: same
- STREAK: same  
- LEVEL → **RUN**: shows `L\(gauntletLevel)/7` with a pip progress bar beneath the 3-cell HUD

### Result Screen
- **On failure:** "Fell at Level \(gauntletLevel)" + score + "Try Again" button (restarts from L1)
- **On Perfect Run:** "Perfect Run! 🏆" + confetti + score + Game Center submission
- No interstitial ads during a run; one ad fires on the run-end screen only

### Leaderboard
- Game Center leaderboard ID: `cq.leaderboard.gauntlet`
- Score submitted on run end (even partial runs)
- `cq_best_gauntlet` persisted locally and shown on the Gauntlet card in ModesView

### View
`GauntletView` — thin wrapper that owns a `GameState(mode: .gauntlet)` and a `GameScene`. Reuses all existing animation/HUD components. Adds gauntlet-specific result overlay.

---

## Feature 2: Daily Challenge

### Concept
One fixed-seed puzzle per UTC day. Same shuffle sequence for all players worldwide. One attempt per day.

### Seed
```swift
let seed = UInt64(floor(Date().timeIntervalSince1970 / 86400))
```
Deterministic, timezone-independent (UTC), changes at midnight UTC.

### Config
Fixed `LevelConfig`: 4 cups, 15 swaps, 0.20s duration, arcHeight 60, hasMidPause: true, hasGhostEffect: false. Accessible but non-trivial — harder than L3, easier than L7.

### One-Attempt Gate
- Attempt flag: `cq_daily_YYYYMMDD` (UserDefaults `Bool`) where date is UTC `yyyy-MM-dd`
- Checked on entry to `DailyChallengeView`
- If already attempted today: show result from `cq_daily_result_YYYYMMDD` (stored score or "failed")
- If not yet attempted: show the challenge

### Result
- **Win:** Score submitted to `cq.leaderboard.daily`. Store `cq_daily_result_YYYYMMDD = score`.
- **Lose:** Store `cq_daily_result_YYYYMMDD = 0`. Show "Come back tomorrow."
- No retry in either case.
- Result screen shows estimated rank ("Today's Rank: #N") based on Game Center leaderboard.

### Streak Counter
- `cq_daily_streak: Int` (UserDefaults) — consecutive days with a daily attempt
- `cq_daily_last_date: String` (UserDefaults) — last date attempted (UTC `yyyy-MM-dd`)
- On each attempt: if `lastDate == yesterday` → streak+1, else streak=1
- Streak shown on the Daily Challenge card in ModesView

### View
`DailyChallengeView` — owns a `GameState(mode: .daily)`. Shows one-attempt warning before starting. Reuses all game components. Custom result overlay with streak display.

---

## Feature 3: Prestige

### Concept
Voluntary reset to Level 1 that rewards players with a permanent crown badge. Kept stats signal achievement; reset stats provide fresh progression.

### Trigger
Prestige button appears in `ModesView` Prestige card **only when `level == 7`**. Tapping shows a confirmation alert.

### What Resets
- `cq_wins` → 0 (level returns to 1)
- `cq_ftue_done` → false (slow first round replays — feels fresh)
- Session score/streak (natural on new `GameState` init)

### What Is Kept (Permanent Achievements)
- `cq_highScore`
- `cq_bestLevel` (stays at 7)
- `cq_bestSurvival`
- `cq_best_gauntlet`
- `cq_score_history` (leaderboard archive)
- `cq_modes_unlocked` (stays true)

### Prestige Counter
- `cq_prestige: Int` (UserDefaults) — increments on each prestige
- Displayed as 👑×N on the home screen title area (hidden when 0)
- Future: crown color changes at 3 (silver), 5 (gold), 10 (rainbow)

### No Gameplay Changes Per Prestige
Prestige is purely cosmetic and identity-driven. No difficulty multipliers, no special configs. The reward is the crown and the fresh journey.

---

## New Files

| File | Purpose |
|------|---------|
| `ModesView.swift` | fullScreenCover with 3 mode cards |
| `GauntletView.swift` | Gauntlet game wrapper + result overlay |
| `DailyChallengeView.swift` | Daily challenge wrapper + one-attempt gate |

## Modified Files

| File | Change |
|------|--------|
| `GameState.swift` | Add `GameMode` enum, `gauntletLevel`, `gauntletScore`, `cq_best_gauntlet`, `cq_prestige` keys |
| `ContentView.swift` | Add Modes button, prestige crown display, `savedPrestige` state |
| `GameScene.swift` | No changes required — all configs passed externally |
| `project.pbxproj` | Register 3 new Swift files |

## Not In Scope

- Per-prestige difficulty multipliers
- Crown color variants (future)
- Gauntlet "lives" system (future)
- Daily Challenge replay purchase (future)
- Push notifications for daily reminder (future)

---

## Success Criteria

1. L7 player sees unlocked Modes button on home screen
2. Gauntlet runs L1→L7, ends on first wrong pick, submits score
3. Daily Challenge generates same shuffle for all players on same UTC day
4. Daily attempt blocked after first use until next UTC day
5. Prestige resets level to 1, keeps highScore/survival/gauntlet bests
6. Crown badge appears on home screen after first prestige
7. All existing 25 tests still pass
