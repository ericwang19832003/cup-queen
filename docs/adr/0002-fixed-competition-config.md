# Competition mode uses a fixed difficulty config independent of player level

In solo play, difficulty is derived from lifetime `wins` (L1–L7). In a duel, two players at different levels would face asymmetric shuffles if each played their own level — a L7 player has a dramatically smaller correct-tap window than a L1 player, making the match unfair. We introduced a dedicated `Competition Config` (a static `LevelConfig` entry) that all Duel Rounds use regardless of either player's solo level. This also prevents sandbagging (players deliberately staying at low levels to beat newcomers in ranked duels).

## Consequences

- Solo `level` and competition difficulty are fully decoupled — a player's duel experience never changes as they progress in solo mode.
- The `Competition Config` values (cup count, swap count, speed) are a tuning decision that can be adjusted independently of the solo level curve.
