# Cup Queen — Season 1: Daily Loop Design

**Date:** 2026-05-06
**Approach:** Retention-First ("Daily Loop") — Approach A
**Scope:** Streak system · Cosmetics · Social sharing · Rank badges

---

## Goal

Ship a "Season 1" update that drives daily active users, monetizes existing players through cosmetics and streak shields, and generates organic growth via shareable stat cards. Zero new gameplay modes — everything reinforces the existing core loop.

---

## Competitive Context

No shell/cup game competitor has daily streaks, cosmetics, or social sharing. Cup Queen is already the most feature-rich app in the category. This update builds the retention infrastructure that will compound as the player base grows.

Key research findings:
- Daily streak systems increase daily engagement **2.3×** and reduce 30-day churn by **35%** (Forrester 2024)
- Cosmetics-only IAP is the highest-acceptance purchase type among mobile players
- Shareable stat cards (Wordle model) are the lowest-cost organic growth mechanic available

---

## Section 1: Daily Streak System

### Core Loop

Complete at least one round (any mode — solo, daily challenge, gauntlet, or duel) each calendar day to extend streak. Streak resets at midnight local time if no round completed.

### Home Screen Treatment

Streak counter displayed in `HomeProgressCard` for returning players. Flame icon + number: `🔥 14`. Pulses gold at milestone numbers (7, 30, 100, 365).

### Milestone Rewards

| Day | Reward |
|-----|--------|
| 3 | 3 hints |
| 7 | 1 Streak Shield + "Gold Felt" table theme |
| 14 | 5 hints |
| 30 | "Crimson Cup" skin (milestone-only, never purchasable) |
| 60 | 1 Streak Shield + 10 hints |
| 100 | "Diamond Animated" cup skin (milestone-only) |
| 365 | "Crown Queen" animated ball + permanent prestige badge |

### Streak Shield

- Protects streak for one missed day; consumed automatically
- Earn 1 free shield per week via rewarded ad
- Purchase 3-pack for $0.99 (IAP: `com.shellgame.magiccup.streakshield3`)
- Max 3 shields held at once
- Player notified when a shield is consumed

### Push Notification

One notification at 8 PM local time if no round completed that day:
> "🔥 Don't lose your [N]-day streak!"

No other streak-related notifications. Permission requested on first app launch after update.

### Persistence

- `cq_streak_count: Int` — current streak length
- `cq_streak_last_date: String` — ISO date of last round completion
- `cq_streak_shields: Int` — shields held (max 3)
- `cq_streak_milestones_claimed: [Int]` — which milestones have been awarded
- Synced via existing `iCloudSyncManager` for cross-device consistency

---

## Section 2: Cosmetics System

### Three Axes — Zero Gameplay Impact

#### Cup Skins

| Skin | Unlock |
|------|--------|
| Classic Red | Default |
| Gold Cup | $0.99 or 30-day streak |
| Midnight (black/purple) | $0.99 |
| Crimson Queen | 30-day streak only (never purchasable) |
| Diamond | $1.99 (subtle shimmer) |
| Diamond Animated | 100-day streak only |

#### Ball Designs

| Design | Unlock |
|--------|--------|
| Golden | Default |
| Crystal | $0.99 |
| Flame | Win 25 duels (earnable only) |
| Crown Queen | 365-day streak only |

#### Table Themes

| Theme | Unlock |
|-------|--------|
| Green Felt | Default |
| Gold Felt | 7-day streak milestone |
| Neon Purple | $0.99 |
| Midnight Blue | $1.99 (includes starfield particle effect) |

### IAP Products

| Product ID | Price | Contents |
|-----------|-------|---------|
| `com.shellgame.magiccup.cosmetic.goldcup` | $0.99 | Gold Cup skin |
| `com.shellgame.magiccup.cosmetic.midnight` | $0.99 | Midnight Cup skin |
| `com.shellgame.magiccup.cosmetic.crystal` | $0.99 | Crystal Ball |
| `com.shellgame.magiccup.cosmetic.neonpurple` | $0.99 | Neon Purple Table |
| `com.shellgame.magiccup.cosmetic.diamond` | $1.99 | Diamond Cup (shimmer) |
| `com.shellgame.magiccup.cosmetic.midnightblue` | $1.99 | Midnight Blue Table (starfield) |
| `com.shellgame.magiccup.cosmetic.starterpack` | $2.99 | Gold Cup + Crystal Ball + Neon Purple Table |
| `com.shellgame.magiccup.streakshield3` | $0.99 | 3 Streak Shields |

### Selection UI

"Customize" button added to secondary row on home screen. Opens `CustomizeView` — a sheet with 3 tabs (Cups / Ball / Table). Live preview using existing `PreviewCupView` + `GoldenBallView`. Locked items show lock icon + unlock condition. Purchase flow inline via StoreKit 2 (same pattern as existing Remove Ads IAP).

### Technical Implementation

`CupTheme` struct holds top/bottom gradient colors + optional animation flag. `PreviewCupView.drawCup()` is parameterized to accept `CupTheme` instead of hardcoded red gradient. `GameScene` reads `CosmeticState.shared.activeCupTheme` on init. `CosmeticState` persists unlock registry to UserDefaults.

---

## Section 3: Social Sharing + Rank Badges

### Shareable Stat Card

Generated via SwiftUI `ImageRenderer` — no server, no third-party SDK.

```
┌──────────────────────────────┐
│  👑 CUP QUEEN                │
│                              │
│  Level 7 · Survived 23 🔥    │
│  Score: 4,820  ·  14d streak │
│                              │
│  Can you beat me?            │
│  apps.apple.com/...          │
└──────────────────────────────┘
```

Card adopts player's active cosmetic theme (Gold Cup player gets gold border).

**Trigger conditions** (share button appears automatically):
- New personal best score or survival record
- Duel win
- Any survival run > 10 rounds

**Never** shown automatically on a loss. Player can always tap a manual "Share" button on the result screen.

Uses `UIActivityViewController` — native iOS share sheet, no extra dependencies.

### Rank Badges

Visible in `HomeProgressCard` and on the stat share card. Rank only ever increases — no demotion, no seasons.

| Badge | Requirement |
|-------|------------|
| 🥉 Bronze | Any returning player (savedHighScore > 0) |
| 🥈 Silver | Win 10 duels |
| 🥇 Gold | Win 50 duels |
| 💎 Diamond | Win 150 duels |
| 👑 Master | Win 300 duels + reach Level 7 |

Persisted as `cq_rank: Int` (0–4) in UserDefaults. Computed from `cq_competition_wins` (already persisted) + `cq_bestLevel` on each app launch.

---

## Section 4: Architecture

### New Files (4)

| File | Purpose |
|------|---------|
| `ShellGame/StreakManager.swift` | Streak state machine — increment, reset, shield logic, milestone detection, push notification scheduling. `@Observable` singleton. |
| `ShellGame/CosmeticState.swift` | Active skin selection + unlock registry. `@Observable` singleton. StoreKit 2 purchase handling for cosmetic IAPs. |
| `ShellGame/CustomizeView.swift` | 3-tab cosmetics picker sheet with live preview and inline IAP purchase flow. |
| `ShellGame/ShareCardView.swift` | SwiftUI view rendered to PNG via `ImageRenderer`. Accepts session stats + cosmetic theme. |

### Modified Files (6)

| File | Change |
|------|--------|
| `ShellGame/ContentView.swift` | Streak flame + rank badge in `HomeProgressCard`. "Customize" button in secondary row. |
| `ShellGame/GameView.swift` | Call `StreakManager.shared.recordRound()` on round complete. Show share button on result screen trigger conditions. |
| `ShellGame/GameScene.swift` | Read `CosmeticState.shared` on scene init to apply cup + ball theme colors. |
| `ShellGame/AdManager.swift` | Add `requestShieldRewardedAd()` — awards 1 streak shield on rewarded ad completion. |
| `ShellGame/ShellGameApp.swift` | Request `UNUserNotificationCenter` permission. `StreakManager` handles scheduling. |
| `PreviewCupView` (in ContentView.swift) | Accept optional `CupTheme` param; default = Classic Red for backwards compat. |

### No New Dependencies

- `ImageRenderer` — SwiftUI built-in (iOS 16+) ✓
- `UNUserNotificationCenter` — `UserNotifications` framework (already on device) ✓
- StoreKit 2 — already in project ✓
- `iCloudSyncManager` — already in project ✓

---

## Success Criteria

- [ ] Streak increments on first round completion each day, resets correctly at midnight
- [ ] Streak Shield consumed automatically on missed day; player notified
- [ ] All 6 milestone rewards delivered exactly once at the correct streak day
- [ ] Push notification fires at 8 PM if no round completed; not shown if streak already maintained
- [ ] Cosmetic skins applied consistently in home screen preview AND in-game (GameScene)
- [ ] Purchasing a cosmetic unlocks it permanently; survives app restart
- [ ] Starter Pack IAP correctly unlocks all 3 items
- [ ] Milestone-only cosmetics (Crimson Queen, Diamond Animated, Crown Queen) are not purchasable
- [ ] Stat card generates correctly with active cosmetic theme and correct stats
- [ ] Rank badge updates on app launch after crossing a duel win threshold
- [ ] BUILD SUCCEEDED, 0 errors
- [ ] All existing tests pass
