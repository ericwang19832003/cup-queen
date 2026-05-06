# Design: Level Expansion (7 → 30 Levels)
**Date:** 2026-05-05
**Status:** Approved

---

## Problem

The game currently has 7 levels. Only L1 uses 3 cups; L2–7 all use 4 cups. Players reach the level cap (L7) after just 6 wins, making the game feel short. There is no long-term progression challenge.

---

## Solution

Expand to 30 levels with three cup tiers, a new 5-cup layout, updated scoring, and a moved prestige gate.

---

## Cup Tier Structure

| Tier | Levels | Cups | Purpose |
|------|--------|------|---------|
| Warm-up | L1–3 | 3 | Tutorial feel, gentle ramp |
| Main | L4–15 | 4 | Core progression |
| Expert | L16–30 | 5 | Endgame challenge |

---

## Gates

| Event | Level | Notes |
|-------|-------|-------|
| Modes unlock | L7 | Unchanged — keeps early hook |
| Survival loop | L30 | Was L7; now the true endgame |
| Prestige unlock | L30 | Was L7; must complete full ladder |

---

## Full Level Table

| Level | Cups | Swaps | Speed (s) | Arc | Mid-Pause | Ghost |
|-------|------|-------|-----------|-----|-----------|-------|
| 1  | 3 | 4  | 0.45 | 40 | — | — |
| 2  | 3 | 6  | 0.38 | 44 | — | — |
| 3  | 3 | 8  | 0.30 | 50 | — | — |
| 4  | 4 | 10 | 0.26 | 54 | — | — |
| 5  | 4 | 12 | 0.23 | 58 | — | — |
| 6  | 4 | 14 | 0.20 | 62 | ✓ | — |
| 7  | 4 | 16 | 0.18 | 66 | ✓ | — |
| 8  | 4 | 18 | 0.16 | 68 | ✓ | — |
| 9  | 4 | 20 | 0.15 | 70 | ✓ | — |
| 10 | 4 | 22 | 0.14 | 72 | ✓ | — |
| 11 | 4 | 24 | 0.13 | 74 | ✓ | ✓ |
| 12 | 4 | 26 | 0.12 | 76 | ✓ | ✓ |
| 13 | 4 | 27 | 0.11 | 78 | ✓ | ✓ |
| 14 | 4 | 28 | 0.11 | 80 | ✓ | ✓ |
| 15 | 4 | 30 | 0.10 | 82 | ✓ | ✓ |
| 16 | 5 | 20 | 0.22 | 60 | ✓ | — |
| 17 | 5 | 22 | 0.20 | 62 | ✓ | — |
| 18 | 5 | 24 | 0.18 | 64 | ✓ | ✓ |
| 19 | 5 | 26 | 0.17 | 66 | ✓ | ✓ |
| 20 | 5 | 28 | 0.16 | 68 | ✓ | ✓ |
| 21 | 5 | 30 | 0.15 | 70 | ✓ | ✓ |
| 22 | 5 | 32 | 0.14 | 72 | ✓ | ✓ |
| 23 | 5 | 33 | 0.13 | 74 | ✓ | ✓ |
| 24 | 5 | 34 | 0.12 | 76 | ✓ | ✓ |
| 25 | 5 | 35 | 0.11 | 78 | ✓ | ✓ |
| 26 | 5 | 36 | 0.11 | 80 | ✓ | ✓ |
| 27 | 5 | 37 | 0.10 | 82 | ✓ | ✓ |
| 28 | 5 | 38 | 0.10 | 84 | ✓ | ✓ |
| 29 | 5 | 39 | 0.09 | 86 | ✓ | ✓ |
| 30 | 5 | 40 | 0.09 | 88 | ✓ | ✓ |

Note: L16 resets pace slightly — 5 cups is harder to track, so the difficulty curve resets then climbs again through L30.

---

## Scoring Formula

```
delta = 10 × level × cupMultiplier × streakMultiplier
```

| Cups | cupMultiplier |
|------|--------------|
| 3 | 1.0 |
| 4 | 1.3 |
| 5 | 1.7 |

`streakMultiplier = min(streak + 1, 4)` — unchanged.

**Example wins at max streak (4×):**
- L3 (3 cups): 10 × 3 × 1.0 × 4 = **120**
- L7 (4 cups): 10 × 7 × 1.3 × 4 = **364**
- L15 (4 cups): 10 × 15 × 1.3 × 4 = **780**
- L16 (5 cups): 10 × 16 × 1.7 × 4 = **1,088** ← tier-change jump
- L30 (5 cups): 10 × 30 × 1.7 × 4 = **2,040**

---

## 5-Cup Layout (GameScene)

New values for `cupCount == 5`:

| Property | Value |
|----------|-------|
| `slotXPositions` | `[-110, -55, 0, 55, 110]` |
| `cupSize` | `60 × 74` |
| `hitDX` | `38` |

The `slotXPositions`, `cupSize`, and `hitDX` computed properties in `LevelConfig` must add a `cupCount == 5` branch alongside the existing 3-vs-4 binary check.

---

## Modified Files

| File | Change |
|------|--------|
| `GameScene.swift` | Expand `LevelConfig.config(for:)` switch to 30 cases; add 5-cup layout values |
| `GameState.swift` | Change level cap `7 → 30`; move survival check `== 7 → == 30`; add `cupMultiplier` to score delta; gate prestige on `bestLevel >= 30` |
| `ModesView.swift` | Gate prestige card on `bestLevel >= 30`; update locked label |
| `ContentView.swift` | `modesUnlocked = savedBestLevel >= 7` unchanged |
| `GameStateTests.swift` | Update hardcoded `7` thresholds to `30`; add scoring tests for cup multiplier |

---

## Not In Scope

- Gauntlet mode level count (gauntlet has its own 7-level structure, unchanged)
- Daily challenge (uses a fixed seed, not affected by level count)
- Competition/Duel mode (uses `LevelConfig.competition` fixed config, unchanged)
- Per-level achievement badges
- Animated tier-transition announcement (L4, L16 cup count changes)
