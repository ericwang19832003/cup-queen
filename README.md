# Magic Cup — Shell Game (MVP)

A Las Vegas magic-show style "find the ball under the cup" game built with **SwiftUI + SpriteKit**.

## File Map

```
ShellGame/
├── ShellGameApp.swift   App entry point + extension hooks (analytics, StoreKit, sounds)
├── ContentView.swift    Start screen — title, host illustration, how-to-play, Play button
├── GameView.swift       Active game — SpriteKit canvas + SwiftUI HUD + result overlay
├── GameScene.swift      SpriteKit scene — cup/ball animation, shuffle logic, touch handling
└── GameState.swift      Game state machine (ObservableObject) — phase, score, streak, level

Assets/
└── AssetsGuide.md       Art brief: placeholder → production mapping, palette, sounds
```

## Xcode Setup (one-time)

1. **New Project** — Xcode → File → New → Project → **iOS App**
   - Product Name: `ShellGame`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck CoreData and tests for MVP

2. **Delete** the auto-generated `ContentView.swift` (move to Trash)

3. **Add files** — drag all five `.swift` files from `ShellGame/` into the Xcode project navigator.
   - Ensure **"Copy items if needed"** is checked
   - Ensure all files are added to the `ShellGame` target

4. **Build** — ⌘B — should compile with 0 errors, 0 warnings

5. **Run** — choose any iOS 16+ simulator — ⌘R

> **No external dependencies.** Zero CocoaPods/SPM packages required.

## Gameplay Loop

```
Start screen
    ↓ Tap "Play Now"
Ball appears under a random cup          [placing phase]
Cup lowers to hide the ball              [placing phase]
    ↓ automatic
Cups shuffle (arc animations)            [shuffling phase]
    ↓ automatic
Player taps a cup                        [choosing phase]
Cup lifts — correct or wrong revealed    [revealing phase]
Result overlay: score delta, Play Again  [result phase]
    ↓ Tap "Play Again"
Loop
```

## Fairness Guarantee

The ball is tracked by **cup identity** (`ballCupIndex` = index into `cupNodes[]`), not by position slot.
Each swap updates the slot↔cup mapping tables (`slotsOccupied`, `cupInSlot`) but never changes
which cup owns the ball. At reveal time, the cup the player tapped is compared directly to `ballCupIndex`.
**The result is always honest.**

## Level Progression

| Level | Swaps | Swap Speed |
|-------|-------|------------|
| 1     | 5     | 0.38 s     |
| 2     | 7     | 0.33 s     |
| 3     | 9     | 0.28 s     |
| 4     | 11    | 0.23 s     |
| 5     | 13    | 0.17 s     |

Level increases every 3 consecutive correct picks (capped at 5).
Streak bonus multiplies score (1× → 2× → 3× → 4× max).

## Extension Points

All future work has `// TODO:` comments in source:

| Tag | Where | What |
|-----|-------|------|
| `ANALYTICS` | `ShellGameApp`, `GameState` | Firebase / Amplitude |
| `SOUNDS` | `GameScene` (×5) | `SoundManager.shared.play(...)` calls |
| `SKINS` | `GameScene.renderCupTexture`, `GameView.hostSection` | Artist assets + `SkinManager` |
| `PARTICLES` | `GameScene.showBallAtCup` | Win confetti `.sks` emitter |
| `STOREKIT` | `GameView.resultOverlay`, `ContentView.footerLinks` | StoreKit 2 purchase flow |
| `ADS` | `GameView.resultOverlay` | AdMob / AppLovin interstitial |
| `GAMECENTER` | `ContentView.footerLinks` | Leaderboard sheet |

## Requirements

- iOS 16+
- Xcode 15+
- No third-party packages
