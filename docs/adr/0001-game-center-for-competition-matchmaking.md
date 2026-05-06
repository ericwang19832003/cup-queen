# Use Game Center for competition matchmaking and real-time data channel

Competition mode requires real-time synchronization between two devices. We chose `GKMatch` (Game Center) over a custom WebSocket server because the app already authenticates `GKLocalPlayer` on launch, Apple handles NAT traversal and friend invites at no ongoing cost, and `GKMatch` provides a sufficient data channel (~87KB/s) for the small event payloads a shell game duel requires. A custom backend would add infrastructure cost and maintenance burden that isn't justified for a casual mobile game.

## Considered Options

- **Custom WebSocket server** — full control, but requires hosting, auth, and scaling infrastructure indefinitely.
- **Game Center GKMatch** — chosen. Zero infrastructure cost, built-in friend invites and random matchmaking, real-time data channel, already partially integrated.
