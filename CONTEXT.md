# Cup Queen — Domain Context

## Glossary

### Session
One unbroken run from the home screen into the game, ending when the player taps **Main Menu** or the app is killed/backgrounded. Within a session, `score` and `streak` accumulate. A **loss** resets only the streak; the session score keeps accumulating. The session's peak score is what gets compared against `highScore` and submitted to Game Center.

### Round
A single placing → shuffling → choosing → revealing → result cycle. Many rounds make up one session.

### Lifetime wins (`wins`)
Cumulative count of correct picks across all sessions, persisted in UserDefaults. Drives `level` on next launch.

### Level
Derived from lifetime wins: `min(wins + 1, 7)`. Players always open the app at their earned level. Level drives `LevelConfig` (cup count, swap count, duration, arc, pauses). **Levels never decrease** — a loss only breaks the streak. At L7 the meaningful metric shifts to streak length ("Survived X rounds").

### Sound & Haptics
Six events get both sound (via `AVAudioEngine` synthesis) and haptics (via `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`):

| Event | Sound | Haptic |
|-------|-------|--------|
| Ball placed under cup | Soft thud | `.light` impact |
| Each cup swap | Whoosh | None |
| Correct pick | Ascending chime + cheer | `.medium` success |
| Wrong pick | Low buzz | `.rigid` error |
| Level up | Fanfare | `.heavy` impact |
| Hint reveal | Magical shimmer | `.light` impact |

### Privacy Policy
**Hard blocker for App Store submission and AdMob production mode.** Must be generated at `app-privacy-policy-generator.firebaseapp.com` and pasted into: (1) App Store Connect → App Information → Privacy Policy URL, (2) Google AdMob → App settings → Privacy policy URL. Status: **pending — user action required**.

### Background / Foreground Handling
`GameView` listens to `UIApplication.willResignActiveNotification` — on background, the SpriteKit scene pauses and the current round is flagged dirty. On `didBecomeActiveNotification`, if mid-round (phase is `.placing`, `.shuffling`, or `.choosing`), the round resets via `resetForNewRound()` and replays from placing. Avoids players returning to a blind choosing phase they didn't watch.

### First-Time User Experience (FTUE)
First ever round runs at `swapDuration * 1.43` (≈0.60s at L1 instead of 0.42s). Controlled by `cq_ftue_done` UserDefaults bool — set to `true` after round 1 completes, never applied again. No UI, no tutorial overlay. Silent and invisible to returning players.

### App Store Metadata
- **Name:** Cup Queen
- **Subtitle:** "Shell Game — Find the Ball" (28 chars)
- **Primary category:** Games → Puzzle
- **Secondary category:** Games → Family
- **Age rating:** 12+ (no casino language; AdMob G-rated ads)

### AdMob Content Rating
`maxAdContentRating = .general` (G-rated) set unconditionally at app init. Required for App Store 12+ compliance. ~10–15% CPM reduction accepted as compliance cost.

### Session Boundary
Tapping **Main Menu** explicitly ends the session. `score` and `streak` reset on the next game entry (new `@StateObject`). `lossCount` also resets. `wins`, `highScore`, and `bestLevel` are persisted to UserDefaults before the session ends. "Main Menu = session end" is the canonical contract.

### ATT Prompt
`ATTrackingManager.requestTrackingAuthorization` is called immediately before the first interstitial ad fires (on the 3rd cumulative loss of a session). Never shown on cold launch. Denial falls back to AdMob non-personalised ads — monetisation continues at lower CPM.

### Hint (Rewarded Video)
Appears during `.choosing` phase only, after a 2-second hesitation delay. Fades in as a "💡 Hint" button; disappears on cup tap. Watching the ad triggers a partial reveal: the correct cup lifts briefly (0.6s) then drops back — player must still tap it. Remove Ads IAP does **not** unlock free hints; hints remain rewarded-video-gated for all users.

### Remove Ads IAP
Single non-consumable StoreKit 2 purchase at **$1.99** (`com.shellgame.magiccup.removeads`). Removes interstitial ads only. Cosmetics and hints remain separate future revenue levers. Persisted via StoreKit 2 transaction verification (no server needed).

### Game Center Leaderboards
Two leaderboards:
1. **Score** (`cq.leaderboard.score`) — all players; submits session `highScore` on session end
2. **Survival** (`cq.leaderboard.survival`) — L7 players only; submits `survivalCount` (consecutive L7 wins in a session)

### Loss Count
Session-only counter (`lossCount: Int` in `GameState`). Increments on every loss regardless of wins between them. After 3 cumulative losses in a session, an interstitial ad fires and `lossCount` resets to 0. Not persisted across sessions.

### Endless Mode
Activated once a player reaches L7. L7 base config is already at minimum viable speed (0.10s), so escalation uses **swap count** instead: each win at L7 adds 1 extra swap (23 → 24 → … → 35 max). A session-only `survivalCount` tracks consecutive L7 wins — resets on any loss, displayed in the result overlay, and submitted to Game Center as the Survival leaderboard metric.

### Streak
Correct picks in a row within the current session. Resets to 0 on any loss. Drives score multiplier (max 4×).

---

## Competition Mode

### Match
A real-time synchronized duel between two players over Game Center. Distinct from a **Session** — a Match has a defined winner and loser. A Match consists of a series of **Duel Rounds** until one player reaches 3 wins (first-to-3 format). Match results are fully isolated from solo progression (`wins`, `level`, `highScore` are unaffected).
_Avoid_: Game, battle, race

### Duel Round
One complete placing → shuffling → choosing cycle played synchronously by both players on the same shuffle sequence (shared seed). The first player to tap the correct cup wins the Duel Round. If the first tapper is wrong, the other player may still win by tapping correctly. A Duel Round ends the moment a correct tap is registered — the round closes for both players simultaneously.
_Avoid_: Turn, game, stage

### Round Winner
The player who taps the correct cup first in a Duel Round. Determined by the tapping player's device and broadcast to the opponent via the GKMatch data channel.

### Match Winner
The first player to win 3 Duel Rounds. The Match ends immediately when this threshold is reached.

### Competition Config
A fixed `LevelConfig` used for all Duel Rounds regardless of either player's solo `level`. Decouples competition difficulty from solo progression and prevents level-based sandbagging.
_Avoid_: Duel level, competition level

### Forfeit
A Match outcome triggered when a player disconnects and fails to reconnect within the 10-second grace period. The disconnected player loses the Match; the opponent is awarded the win.

### Competition Wins
A persistent, isolated counter of Match wins. Tracked in UserDefaults (`cq_competition_wins`). Never affects solo `wins` or `level`. Submitted to the `cq.leaderboard.duels` Game Center leaderboard.
_Avoid_: Duel wins, match score

---

## Relationships (Competition)

- A **Match** consists of multiple **Duel Rounds**
- A **Duel Round** produces exactly one **Round Winner** (or ends via **Forfeit**)
- A **Match** produces exactly one **Match Winner**
- A **Match Win** increments **Competition Wins** only — never solo `wins`

## Example dialogue

> **Dev:** "If both players tap wrong, who wins the Duel Round?"
> **Domain expert:** "Nobody — both tapped wrong cups, so neither gets the Round Winner. Wait, that's not possible: only one cup has the ball, and the round ends on the first *correct* tap. A wrong tap doesn't end the round."

> **Dev:** "Does winning a Match level me up?"
> **Domain expert:** "No — **Competition Wins** and solo **wins** are completely separate. Matches don't touch your level."
