# Competition rounds are synchronized: same shuffle, first correct tap wins

Both players watch the same shuffle sequence (derived from a shared seed) simultaneously. The first player to tap the correct cup wins the Duel Round, and the round closes for both players immediately. We chose this over a parallel model (independent shuffles, score compared at end) because it creates direct head-to-head tension and maps cleanly to the real-time data channel: the tapping player broadcasts a single `roundWon` event and the opponent's UI closes the round on receipt. A wrong tap does not end the round — the opponent still has a window to tap correctly.

## Consequences

- Round length is bounded by player reaction time, not a timeout — matches are fast.
- A shared shuffle seed must be agreed upon at round start (one player generates it and broadcasts it via GKMatch before the placing phase begins).
