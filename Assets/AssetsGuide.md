# Assets Guide — Magic Cup Shell Game

All art in the MVP is **generated in code** (no external files required to build).
Replace these placeholders as the game matures.

## Placeholder → Production Map

| Placeholder | Location | Replace With |
|---|---|---|
| Red trapezoid cup | `GameScene.renderCupTexture()` | Artist PNG/SVG in `Assets.xcassets/Cups/` |
| Gold circle ball | `GameScene.setupBall()` | Animated sprite sheet |
| 🎩 emoji host | `GameView.hostSection` / `ContentView.hostIllustration` | Lottie/Rive animated host character |
| Twinkling circles | `ContentView.backgroundStars` | Particle `.sks` file or Metal shader |
| Stage felt + dots | `GameScene.setupBackground()` | Artist background illustration |

## Recommended Asset Sizes

| Asset | Size | Format |
|---|---|---|
| Cup sprite | 160×196 @2x | PNG with alpha |
| Ball sprite | 68×68 @2x | PNG with alpha |
| Host illustration | 320×400 @2x | Lottie JSON or APNG |
| Background stage | 390×310 @2x | PNG or SVG |
| Win confetti emitter | — | SpriteKit `.sks` particle file |

## Color Palette (Design Tokens)

| Token | Hex | Use |
|---|---|---|
| Stage Felt | `#122C1C` | Game background green |
| Gold Accent | `#E6BF2E` | Rims, HUD, CTAs |
| Cup Body | `#820D0D` → `#D11414` | Gradient, left to right |
| Ball Gold | `#F4D11F` | Ball fill |
| Deep Purple | `#0A0828` | App background |
| Host Purple | `#850D85` | Host avatar background |

## Sound Assets

| Sound | Trigger | File Name |
|---|---|---|
| Ball pop | Ball appears | `sfx_ball_appear.caf` |
| Cup whoosh | Each swap | `sfx_whoosh.caf` |
| Cup cover | Ball hidden | `sfx_cup_down.caf` |
| Win fanfare | Correct pick | `sfx_win.caf` |
| Lose sting | Wrong pick | `sfx_lose.caf` |

Hook into `SoundManager` — see `// TODO: SOUNDS` comments in `GameScene.swift`.

## Future Skin Packs (StoreKit)

- **Classic Vegas** (default / free)
- **Ancient Egypt** — stone cups, scarab ball
- **Ocean Magic** — sea-glass cups, pearl ball
- **Neon Cyber** — holographic cups, energy orb ball
