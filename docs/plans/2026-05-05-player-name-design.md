# Player Name & Global Leaderboard — Design Document

**Date:** 2026-05-05  
**Status:** Approved

---

## Goal

Allow players to enter a name before each game session and compete on a global leaderboard visible to all users worldwide, while preserving the existing Game Center leaderboard integration.

---

## Architecture

### Data Flow

```
[Tap Play] → PlayerNameEntryView (sheet)
                 ↓ name saved to UserDefaults "cq_player_name"
             [Game runs normally]
                 ↓ round ends, session score finalized
             ScoreSubmissionService
                 ├── POST to Supabase scores table (global leaderboard)
                 └── Submit to Game Center (existing, unchanged)

[Leaderboard button on home] → LeaderboardView
                                   └── GET top 50 scores from Supabase
```

### New Components

| Component | Type | Purpose |
|---|---|---|
| `PlayerNameEntryView` | SwiftUI View | Bottom sheet — name TextField + Play button |
| `ScoreSubmissionService` | Swift class | Posts score to Supabase; manages offline retry queue |
| `LeaderboardView` | SwiftUI View | Global top-50 list, filterable by mode |

### Modified Files

| File | Change |
|---|---|
| `GameView.swift` | Show `PlayerNameEntryView` sheet when Play tapped |
| `ContentView.swift` | Add Leaderboard button to home screen |
| `GameState.swift` | Call `ScoreSubmissionService` after result phase |

### No New SDK

Plain `URLSession` POST/GET to Supabase REST API with anon key in headers. Zero new Swift Package dependencies.

---

## Supabase Schema

```sql
CREATE TABLE scores (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  player_name text        NOT NULL CHECK (char_length(player_name) <= 20),
  score       int         NOT NULL,
  mode        text        NOT NULL,  -- 'solo' | 'gauntlet' | 'daily'
  level       int         NOT NULL,
  created_at  timestamptz DEFAULT now()
);

-- Row-Level Security
ALTER TABLE scores ENABLE ROW LEVEL SECURITY;

-- Anyone can read
CREATE POLICY "public read"   ON scores FOR SELECT USING (true);
-- Anyone can insert; no client-side update or delete
CREATE POLICY "public insert" ON scores FOR INSERT WITH CHECK (true);
```

---

## User Experience

### Pre-Session Name Prompt

Appears as a bottom sheet every time the player taps Play.

```
┌─────────────────────────────┐
│  What's your name?          │
│                             │
│  ┌─────────────────────┐    │
│  │  Alex               │    │
│  └─────────────────────┘    │
│                             │
│  [        Play        ]     │
└─────────────────────────────┘
```

- Pre-fills with last-used name from UserDefaults key `cq_player_name`
- Play button disabled when TextField is empty
- Name capped at 20 characters (enforced in UI + DB)
- No skip/cancel — name is required for leaderboard integrity
- Tapping Play saves name to UserDefaults and starts the game immediately

### Leaderboard Screen

Accessible via a trophy button on the home screen.

- Top 50 scores globally, sorted by score descending
- Mode filter tabs: **All / Solo / Gauntlet / Daily**
- Each row: rank · player name · score · level reached · time ago
- Player's own best score highlighted (matched by stored `cq_player_name`)
- Pull-to-refresh

### Score Submission

- Fires silently after the result overlay appears (non-blocking)
- Only the final session score is submitted, not per-round intermediate scores
- Submitted fields: `player_name`, `score`, `mode`, `level`

---

## Offline Handling

Failed submissions stored as JSON in UserDefaults key `cq_pending_scores` (array of score dicts). Queue drained one-by-one on next app foreground. Silent — no user-facing error unless queue exceeds 10 items (edge case, not expected).

---

## Security & Privacy

- **Anon key embedded in app bundle** — safe; RLS prevents writes beyond INSERT
- **No PII stored**: no device ID, no IP, no Game Center ID — only name + score + mode + level + timestamp
- **Abuse protection**: 20-char name limit at DB level; Supabase built-in rate limiting; admin can delete offensive entries from dashboard
- **No UPDATE/DELETE** from client — scores are immutable once submitted
- **Debug/prod separation**: `#if DEBUG` compile flag swaps Supabase URL + anon key to a separate dev project

---

## Testing Plan

### Unit Tests (added to `GameStateTests.swift`)

- Empty name disables Play button
- Name truncated at 20 chars in UI
- Last name pre-filled from UserDefaults on sheet open
- `ScoreSubmissionService` builds correct JSON payload
- Offline queue enqueues on network failure
- Queue drains in FIFO order on retry

### Manual Verification Checklist

- [ ] Name prompt appears every time Play is tapped
- [ ] Pre-fill works after first name entry
- [ ] 21-char name rejected (Play button stays disabled)
- [ ] Leaderboard shows scores from multiple entries
- [ ] Score appears on leaderboard within ~2 seconds of submission
- [ ] Offline: airplane mode → play round → score queued → reconnect → score appears
- [ ] Mode filter tabs correctly filter Solo / Gauntlet / Daily
- [ ] Existing Game Center leaderboard still works

---

## Out of Scope (this version)

- Name moderation / profanity filter
- Edit or delete your own scores
- Per-week / per-month leaderboard periods
- Friend-only leaderboard views
- Profile avatars
