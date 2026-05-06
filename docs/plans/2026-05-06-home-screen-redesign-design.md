# Home Screen Redesign — Design Document

**Date:** 2026-05-06
**Scope:** `ShellGame/ContentView.swift` only (plus new sub-components inline)
**Approach:** Mission Control — contextual layout swap based on player state

---

## Goal

Differentiate the home screen experience for new vs returning players. New players see a tutorial-flavored screen with animated cup demo. Returning players see a progress-forward dashboard with a compact cup idle animation. Reduce competing elements, improve hierarchy, create immediate pull through cup motion.

---

## Player State Gate

```swift
let isReturningPlayer = savedHighScore > 0
```

Already exists in the codebase (`if savedHighScore > 0 { bestStatsRow }`). The redesign expands this gate to drive the entire layout.

---

## Layout — New Player

Sections top → bottom:

1. **Title block** — "CUP QUEEN" + "FIND THE BALL" subtitle (unchanged)
2. **Challenge badge** — "Only 1% of players beat Level 7" (motivational FOMO)
3. **Animated cup hero** — LARGE (~55% screen height). Demo loop (see Animation spec)
4. **How-to row** — 3 steps: Watch the Ball · Follow Cups · Tap to Win
5. **"Play Now" CTA** — full-width gold pulsing button
6. **Secondary row** — Leaderboard · Duel · Modes (with faint divider above)

---

## Layout — Returning Player

Sections top → bottom:

1. **Title block** — "CUP QUEEN" + "FIND THE BALL" subtitle (unchanged, greeting moves to card)
2. **Progress card** — level, score, progress bar, next milestone, greeting (see Progress Card spec)
3. **Animated cup hero** — COMPACT (~35% screen height). Idle loop (see Animation spec)
4. **Live leaderboard teaser** — moves up here (above CTA) for motivational context
5. **Contextual CTA** — "Continue — Level X" + "Fresh Start" ghost link below
6. **Secondary row** — Leaderboard · Duel · Modes (with faint divider above)
7. **How-to row** — HIDDEN (returning players know how to play)

---

## Progress Card (returning players only)

Replaces: `bestStatsRow` capsule + standalone greeting in `titleSection`.

Visual: `RoundedRectangle(cornerRadius: 20)`, `Color.black.opacity(0.32)` fill, gold-to-purple gradient border (matching `gamePreviewSection` treatment today).

```
┌─────────────────────────────────────────┐
│  👑  Level 5              1,240 pts  ⭐  │
│  ━━━━━━━━━━━━░░░░░░   1 win to L6      │
│                                          │
│  "Welcome back, Alex 👑👑"               │
└─────────────────────────────────────────┘
```

- **Level badge** (leading): `"Level X"` bold gold. At L30: `"MAX"` with crown icon.
- **Score** (trailing): `savedHighScore` with `star.fill` icon.
- **Progress bar**: thin `Capsule`, gold fill. Width = `CGFloat(wins % winsPerLevel) / CGFloat(winsPerLevel)`.
  - `winsPerLevel` derived from current level: each level requires 1 win (per existing logic `level = wins + 1`), so bar always fills to 100% then resets.
  - At L30: bar replaced by `"Survived X in a row"` survival count.
- **Sub-label**: `"X win to L(X+1)"`. At L7+: `"Top 1% — keep going 🔥"`.
- **Greeting line**: `"Welcome back, [name][prestige crowns]"` — moves here from `titleSection`. If no name set: omit line entirely.

---

## Animated Cup Hero

### New Player — Demo Loop (large, ~55% screen height)

Cup size: `width: 88, height: 108` (up from 74×92 today).

Sequence (repeating, ~12s total loop):

| Step | Duration | Action |
|------|----------|--------|
| 1 | 0.8s | Ball visible under centre cup — static hold |
| 2 | 0.4s | Centre cup lowers to cover ball |
| 3 | 0.5s | Pause |
| 4 | 2.5s | 4 shuffles at ~0.55s each (hardcoded pairs: C↔R, L↔C, C↔R, L↔C) |
| 5 | 1.2s | Cups settle. All three bob upward gently ("choose me") |
| 6 | 0.6s | Left cup auto-lifts: empty reveal, drops back (misdirection) |
| 7 | 0.5s | Beat pause — tension |
| 8 | 0.6s | Centre cup lifts: ball revealed. Gold glow burst on ball. |
| 9 | 1.5s | Hold on reveal |
| 10 | 0.5s | Centre cup lowers. Loop restarts. |

Implementation: pure SwiftUI. Three `@State var cupOffset: CGFloat` values driven by a `Task { try await Task.sleep(...) }` sequence in `.onAppear`. `GoldenBallView` opacity toggles on step 2/8. No SpriteKit.

Shuffle visual: animate `cupOffset` (horizontal) on each swap pair — cups slide past each other using `.animation(.easeInOut(duration: 0.50))`. Ball tracks with its cup's offset (ball owner index tracked as `@State var ballOwner: Int`).

### Returning Player — Idle Loop (compact, ~35% screen height)

Cup size: unchanged (74×92). Ball visible under centre cup throughout.

Sequence (repeating, ~3s loop):
- Left cup bobs up 8pt then down — 0.35s
- 0.3s gap
- Centre cup bobs up 8pt then down — 0.35s
- 0.3s gap
- Right cup bobs up 8pt then down — 0.35s
- 1.2s rest
- Repeat

Implementation: three staggered `.animation(.easeInOut(duration: 0.35))` on `cupYOffset` driven by a repeating timer or `TimelineView`.

---

## CTA — Returning Player

```
[  ▶  Continue — Level 5  ]    ← full-width gold button, same style as today
         Fresh Start             ← ghost text: .system(size: 13), white.opacity(0.40), centered
```

- `"Continue — Level X"` passes `startFresh: false` to `GameView` (existing flow).
- `"Fresh Start"` is a `Button` with `.plain` style — taps `showNameEntry = true` with `startFreshSelected = true`. Not a button shape, just styled text.
- Both lead through existing `PlayerNameEntryView` sheet flow unchanged.

---

## CTA — New Player

Unchanged: `"Play Now"`, full-width gold, pulsing glow shadow.

---

## Secondary Row

No visual changes. One addition: a `Divider()` with `.background(Color.white.opacity(0.15))` between CTA and secondary row in both layouts. Clarifies hierarchy: primary action above, secondary options below.

---

## What Is Removed (returning player layout)

| Element | Reason |
|---------|--------|
| `bestStatsRow` | Absorbed into progress card |
| Greeting line in `titleSection` | Moved into progress card |
| `challengeBadge` | Redundant for returning players who've accepted the challenge |
| `howToPlayRow` | Returning players know the rules |

---

## Files In Scope

- **Modify**: `ShellGame/ContentView.swift` — all changes live here
- No new files required; new sub-views (`HomeProgressCard`, `DemoShuffleView`, `IdleCupsView`) defined inline in `ContentView.swift`

---

## Component Map

| New component | Replaces | Notes |
|---------------|----------|-------|
| `HomeProgressCard` | `bestStatsRow` + greeting in title | New inline struct |
| `DemoShuffleView` | `gamePreviewSection` (new player) | SwiftUI-only animation |
| `IdleCupsView` | `gamePreviewSection` (returning player) | SwiftUI-only animation |
| `freshStartLink` | Part of `playNowButton` (returning only) | Ghost text button |

`HostCharacterView`, `PreviewCupView`, `GoldenBallView` — reused unchanged.

---

## Success Criteria

- [ ] New player sees: title → challenge badge → large animated demo → how-to → Play Now → secondary row
- [ ] Returning player sees: title → progress card → compact idle cups → leaderboard teaser → Continue CTA → secondary row (no how-to, no challenge badge)
- [ ] Demo loop completes full sequence (ball show → hide → shuffle → misdirection → reveal) on repeat without drift
- [ ] Idle loop bobs smoothly with no jank on iPhone 16 Pro and iPhone SE
- [ ] `"Fresh Start"` ghost link correctly routes through existing `startFresh: true` flow
- [ ] Progress bar shows correct fill for current wins-toward-next-level
- [ ] L30 players see survival count instead of progress bar
- [ ] BUILD SUCCEEDED, 0 errors
