# Player Name & Global Leaderboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let players enter a name before each game session and compete on a global Supabase-backed leaderboard visible to all users worldwide.

**Architecture:** A `PlayerNameEntryView` sheet appears every time Play is tapped, saving the name to UserDefaults `cq_player_name`. A `ScoreSubmissionService` POSTs scores to a Supabase public `scores` table (plain URLSession, no SDK) alongside existing Game Center submission. A `LeaderboardView` GETs the top 50 scores and displays them with mode filter tabs.

**Tech Stack:** Swift / SwiftUI, URLSession, Supabase REST API (anon key), UserDefaults for name persistence and offline queue.

---

## Pre-requisites (manual — do before Task 1)

You need a Supabase project. Go to [supabase.com](https://supabase.com), create a free project, then run the following SQL in the **SQL Editor**:

```sql
CREATE TABLE scores (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  player_name text        NOT NULL CHECK (char_length(player_name) <= 20),
  score       int         NOT NULL,
  mode        text        NOT NULL CHECK (mode IN ('solo','gauntlet','daily')),
  level       int         NOT NULL,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public read"   ON scores FOR SELECT USING (true);
CREATE POLICY "public insert" ON scores FOR INSERT WITH CHECK (true);

CREATE INDEX idx_scores_mode_score ON scores (mode, score DESC);
```

Collect from the Supabase dashboard (**Settings → API**):
- **Project URL** e.g. `https://xyzcompany.supabase.co`
- **anon public key** (long JWT string)

Also create a second Supabase project for dev/testing and collect its URL + anon key.

---

## Task 1: SupabaseConfig.swift

**Files:**
- Create: `ShellGame/SupabaseConfig.swift`

### Step 1: Create the file with placeholder values

```swift
// SupabaseConfig.swift
// Replace the placeholder strings with your real Supabase credentials.
// The anon key is safe to embed — RLS restricts writes to INSERT only.

import Foundation

enum SupabaseConfig {
#if DEBUG
    static let url     = "https://YOUR_DEV_PROJECT.supabase.co"
    static let anonKey = "YOUR_DEV_ANON_KEY"
#else
    static let url     = "https://YOUR_PROD_PROJECT.supabase.co"
    static let anonKey = "YOUR_PROD_ANON_KEY"
#endif

    static var scoresURL: URL {
        URL(string: "\(url)/rest/v1/scores")!
    }
}
```

Fill in the four placeholder strings with your real values.

### Step 2: Build to verify it compiles

```bash
cd /Users/minwang/cup_game
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Register the new file in Xcode target

Edit `ShellGame.xcodeproj/project.pbxproj` to add `SupabaseConfig.swift` to the ShellGame target's `PBXBuildFile` and `PBXGroup` sections, following the exact same pattern used for other Swift files in that project (e.g. find `GameState.swift` and duplicate the two entry blocks with the new filename and a new UUID). Then rebuild to confirm.

### Step 4: Commit

```bash
git add ShellGame/SupabaseConfig.swift ShellGame.xcodeproj/project.pbxproj
git commit -m "feat: add SupabaseConfig with prod/dev URL and anon key slots"
```

---

## Task 2: ScoreSubmissionService — write tests first

**Files:**
- Create: `ShellGame/ScoreSubmissionService.swift`
- Modify: `ShellGameTests/GameStateTests.swift` (add `ScoreQueueTests` class at the bottom)

The service has two responsibilities:
1. POST a score dict to Supabase
2. Manage an offline retry queue in UserDefaults

### Step 1: Write the failing tests

Open `ShellGameTests/GameStateTests.swift`. At the very bottom (after `GauntletTests` closing brace), add:

```swift
// MARK: - ScoreQueueTests

final class ScoreQueueTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Start every test with an empty queue
        UserDefaults.standard.removeObject(forKey: "cq_pending_scores")
    }

    func test_enqueue_addsEntryToQueue() {
        let entry: [String: Any] = [
            "player_name": "Alice",
            "score": 500,
            "mode": "solo",
            "level": 3
        ]
        ScoreSubmissionService.shared.enqueue(entry)
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.count, 1)
        XCTAssertEqual(queue?.first?["player_name"] as? String, "Alice")
    }

    func test_enqueue_preservesOrder() {
        ScoreSubmissionService.shared.enqueue(["player_name": "A", "score": 100, "mode": "solo", "level": 1])
        ScoreSubmissionService.shared.enqueue(["player_name": "B", "score": 200, "mode": "solo", "level": 2])
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.first?["player_name"] as? String, "A")
        XCTAssertEqual(queue?.last?["player_name"]  as? String, "B")
    }

    func test_dequeue_removesFirstEntry() {
        ScoreSubmissionService.shared.enqueue(["player_name": "A", "score": 100, "mode": "solo", "level": 1])
        ScoreSubmissionService.shared.enqueue(["player_name": "B", "score": 200, "mode": "solo", "level": 2])
        let first = ScoreSubmissionService.shared.dequeue()
        XCTAssertEqual(first?["player_name"] as? String, "A")
        let queue = UserDefaults.standard.array(forKey: "cq_pending_scores") as? [[String: Any]]
        XCTAssertEqual(queue?.count, 1)
    }

    func test_dequeue_returnsNilWhenEmpty() {
        let result = ScoreSubmissionService.shared.dequeue()
        XCTAssertNil(result)
    }
}
```

### Step 2: Run to verify they fail

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ShellGameTests/ScoreQueueTests 2>&1 | tail -30
```

Expected: FAIL with "type 'ScoreSubmissionService' has no member…" or similar.

### Step 3: Implement ScoreSubmissionService.swift

```swift
// ScoreSubmissionService.swift
// Posts scores to the Supabase scores table.
// On network failure, enqueues the entry in UserDefaults for later retry.

import Foundation

final class ScoreSubmissionService {

    static let shared = ScoreSubmissionService()
    private init() {}

    private let queueKey = "cq_pending_scores"

    // MARK: - Public API

    /// Submit a score. On failure, the entry is queued for retry.
    func submit(playerName: String, score: Int, mode: String, level: Int) {
        let entry: [String: Any] = [
            "player_name": playerName,
            "score": score,
            "mode": mode,
            "level": level
        ]
        post(entry) { [weak self] success in
            if !success { self?.enqueue(entry) }
        }
    }

    /// Drain the offline queue — call on app foreground.
    func drainQueue() {
        guard dequeue() != nil else { return }
        // Peek, don't remove yet — remove only on success
        guard let entry = peekQueue() else { return }
        post(entry) { [weak self] success in
            if success {
                _ = self?.dequeue()
                self?.drainQueue()   // recurse until empty
            }
        }
    }

    // MARK: - Queue (internal for tests)

    func enqueue(_ entry: [String: Any]) {
        var queue = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        queue.append(entry)
        UserDefaults.standard.set(queue, forKey: queueKey)
    }

    @discardableResult
    func dequeue() -> [String: Any]? {
        var queue = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        guard !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        UserDefaults.standard.set(queue, forKey: queueKey)
        return first
    }

    // MARK: - Private

    private func peekQueue() -> [String: Any]? {
        (UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]])?.first
    }

    private func post(_ entry: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: entry) else {
            completion(false); return
        }
        var request = URLRequest(url: SupabaseConfig.scoresURL)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal",   forHTTPHeaderField: "Prefer")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            completion(ok)
        }.resume()
    }
}
```

### Step 4: Register the new file in Xcode target

Edit `project.pbxproj` to add `ScoreSubmissionService.swift` to the ShellGame target (same pattern as Task 1 Step 3). Build to confirm.

### Step 5: Run tests to verify they pass

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ShellGameTests/ScoreQueueTests 2>&1 | tail -30
```

Expected: 4 tests PASS.

### Step 6: Commit

```bash
git add ShellGame/ScoreSubmissionService.swift \
        ShellGame.xcodeproj/project.pbxproj \
        ShellGameTests/GameStateTests.swift
git commit -m "feat: add ScoreSubmissionService with offline queue"
```

---

## Task 3: PlayerNameEntryView — write tests first

**Files:**
- Create: `ShellGame/PlayerNameEntryView.swift`
- Modify: `ShellGameTests/GameStateTests.swift` (add `PlayerNameTests` class)

### Step 1: Write the failing tests

Append to `GameStateTests.swift`:

```swift
// MARK: - PlayerNameTests

final class PlayerNameTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "cq_player_name")
    }

    func test_savedName_defaultsToEmptyString() {
        let name = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
        XCTAssertEqual(name, "")
    }

    func test_saveName_persistsToUserDefaults() {
        UserDefaults.standard.set("Zara", forKey: "cq_player_name")
        let loaded = UserDefaults.standard.string(forKey: "cq_player_name")
        XCTAssertEqual(loaded, "Zara")
    }

    func test_nameCappedAt20Characters() {
        let longName = String(repeating: "X", count: 25)
        let capped = String(longName.prefix(20))
        XCTAssertEqual(capped.count, 20)
    }
}
```

### Step 2: Run to verify they pass (these are pure logic tests, no UI)

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ShellGameTests/PlayerNameTests 2>&1 | tail -20
```

Expected: 3 tests PASS (all UserDefaults/string logic, no missing type yet).

### Step 3: Implement PlayerNameEntryView.swift

```swift
// PlayerNameEntryView.swift
// Bottom sheet that appears before each game session.
// Saves the entered name to UserDefaults "cq_player_name".

import SwiftUI

struct PlayerNameEntryView: View {
    /// Called when the player taps Play — name already saved when this fires.
    let onPlay: () -> Void

    @State private var name: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.12, green: 0.04, blue: 0.26)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 12)

                Image(systemName: "person.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))

                Text("What's your name?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                TextField("Enter your name", text: $name)
                    .font(.system(size: 18, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.40), lineWidth: 1))
                    .onChange(of: name) { newValue in
                        if newValue.count > 20 {
                            name = String(newValue.prefix(20))
                        }
                    }
                    .padding(.horizontal, 32)

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    UserDefaults.standard.set(trimmed, forKey: "cq_player_name")
                    onPlay()
                } label: {
                    Text("Play")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                                ? LinearGradient(colors: [.gray, .gray],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(
                                    colors: [Color(red: 1, green: 0.93, blue: 0.28),
                                             Color(red: 1, green: 0.68, blue: 0.05)],
                                    startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            name = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}
```

### Step 4: Register the new file in Xcode target

Edit `project.pbxproj` to add `PlayerNameEntryView.swift`. Build to confirm.

### Step 5: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 6: Commit

```bash
git add ShellGame/PlayerNameEntryView.swift \
        ShellGame.xcodeproj/project.pbxproj \
        ShellGameTests/GameStateTests.swift
git commit -m "feat: add PlayerNameEntryView bottom sheet"
```

---

## Task 4: Wire name prompt into ContentView

**Files:**
- Modify: `ShellGame/ContentView.swift`

The current `playNowButton` is a `NavigationLink(destination: GameView())` at line 511. We need to:
1. Convert it to a `Button` that shows the name sheet
2. Add a `navigationDestination` so we can navigate programmatically after the sheet confirms

### Step 1: Add two new `@State` properties to ContentView

Find the existing `@State` block (around lines 43–61). After `@State private var showConflict  = false`, add:

```swift
@State private var showNameEntry  = false
@State private var navigateToGame = false
```

### Step 2: Replace the `playNowButton` computed property

Find `private var playNowButton: some View` (around line 510). Replace the entire property — from `private var playNowButton` through its closing brace — with:

```swift
private var playNowButton: some View {
    Button {
        showNameEntry = true
    } label: {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 17, weight: .bold))
            Text("Play Now")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.93, blue: 0.28),
                    Color(red: 1.00, green: 0.68, blue: 0.05),
                    Color(red: 1.00, green: 0.93, blue: 0.28)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .shadow(
            color: Color(red: 1, green: 0.75, blue: 0.10).opacity(ctaPulse ? 0.80 : 0.38),
            radius: ctaPulse ? 28 : 14, y: 5
        )
    }
}
```

### Step 3: Add sheet and navigationDestination modifiers

Find the existing `.sheet(isPresented: $showGameCenter)` modifier (around line 107). **After** it (before `.fullScreenCover` lines), add:

```swift
.sheet(isPresented: $showNameEntry) {
    PlayerNameEntryView {
        showNameEntry  = false
        navigateToGame = true
    }
}
.navigationDestination(isPresented: $navigateToGame) {
    GameView()
}
```

### Step 4: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 5: Commit

```bash
git add ShellGame/ContentView.swift
git commit -m "feat: show player name sheet before navigating to game"
```

---

## Task 5: Expose game mode + wire Supabase score submission

**Files:**
- Modify: `ShellGame/GameState.swift` (add computed property)
- Modify: `ShellGame/GameView.swift` (extend `submitSessionScores`)

We need GameView to know the mode string for submission, and to call `ScoreSubmissionService`.

### Step 1: Expose mode from GameState

In `GameState.swift`, find `private let mode: GameMode` (around line 81). Change it to:

```swift
private(set) var mode: GameMode
```

(Remove the `let`/`private let`, make it `private(set) var` so it's readable from outside but not writable.)

### Step 2: Extend `submitSessionScores` in GameView

Find `private func submitSessionScores()` (around line 602). Replace it with:

```swift
private func submitSessionScores() {
    GameCenterManager.shared.submitHighScore(gameState.highScore)
    GameCenterManager.shared.submitSurvivalCount(gameState.survivalCount)

    let playerName = UserDefaults.standard.string(forKey: "cq_player_name") ?? "Anonymous"
    let modeString: String = {
        switch gameState.mode {
        case .solo:    return "solo"
        case .gauntlet: return "gauntlet"
        case .daily:   return "daily"
        }
    }()
    ScoreSubmissionService.shared.submit(
        playerName: playerName,
        score: gameState.score,
        mode: modeString,
        level: gameState.level
    )
}
```

### Step 3: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add ShellGame/GameState.swift ShellGame/GameView.swift
git commit -m "feat: submit scores to Supabase on session end"
```

---

## Task 6: LeaderboardView

**Files:**
- Create: `ShellGame/LeaderboardView.swift`

### Step 1: Implement LeaderboardView.swift

```swift
// LeaderboardView.swift
// Fetches and displays the top 50 global scores from Supabase.
// Filterable by mode (All / Solo / Gauntlet / Daily).

import SwiftUI

// MARK: - Model

struct LeaderboardEntry: Identifiable, Decodable {
    let id: UUID
    let playerName: String
    let score: Int
    let mode: String
    let level: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case playerName = "player_name"
        case score, mode, level
        case createdAt  = "created_at"
    }
}

// MARK: - View

struct LeaderboardView: View {

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var selectedMode = "all"
    @Environment(\.dismiss) private var dismiss

    private let modes = [("all", "All"), ("solo", "Solo"), ("gauntlet", "Gauntlet"), ("daily", "Daily")]
    private let myName = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.01, blue: 0.16),
                         Color(red: 0.10, green: 0.03, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.yellow.opacity(0.9))
                    }
                    Spacer()
                    Text("Global Leaderboard")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    // Balance the back button
                    Image(systemName: "chevron.left").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Mode filter
                HStack(spacing: 8) {
                    ForEach(modes, id: \.0) { (key, label) in
                        Button {
                            selectedMode = key
                            Task { await loadEntries() }
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(selectedMode == key ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    selectedMode == key
                                        ? Color(red: 1, green: 0.85, blue: 0.28)
                                        : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if isLoading {
                    Spacer()
                    ProgressView().tint(.yellow)
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    Text("No scores yet. Be the first!")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                                LeaderboardRow(rank: idx + 1, entry: entry,
                                               isMe: !myName.isEmpty && entry.playerName == myName)
                                if idx < entries.count - 1 {
                                    Divider().background(Color.white.opacity(0.08))
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .refreshable { await loadEntries() }
                }
            }
        }
        .task { await loadEntries() }
    }

    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }
        entries = (try? await fetchEntries(mode: selectedMode)) ?? []
    }

    private func fetchEntries(mode: String) async throws -> [LeaderboardEntry] {
        var components = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/scores")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,player_name,score,mode,level,created_at"),
            URLQueryItem(name: "order",  value: "score.desc"),
            URLQueryItem(name: "limit",  value: "50")
        ]
        if mode != "all" {
            queryItems.append(URLQueryItem(name: "mode", value: "eq.\(mode)"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LeaderboardEntry].self, from: data)
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text(rankText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 32, alignment: .center)

            // Name + mode badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.playerName)
                        .font(.system(size: 15, weight: isMe ? .bold : .medium, design: .rounded))
                        .foregroundColor(isMe ? Color(red: 1, green: 0.85, blue: 0.28) : .white)
                    if isMe {
                        Text("YOU")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(red: 1, green: 0.85, blue: 0.28))
                            .clipShape(Capsule())
                    }
                }
                Text("Lvl \(entry.level) · \(entry.mode.capitalized)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer()

            // Score
            Text("\(entry.score)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isMe ? Color.yellow.opacity(0.06) : Color.clear)
    }

    private var rankText: String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1, green: 0.85, blue: 0.28)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.80)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .white.opacity(0.45)
        }
    }
}
```

### Step 2: Register the new file in Xcode target

Edit `project.pbxproj` to add `LeaderboardView.swift`. Build to confirm.

### Step 3: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add ShellGame/LeaderboardView.swift ShellGame.xcodeproj/project.pbxproj
git commit -m "feat: add LeaderboardView with mode filter and YOU highlight"
```

---

## Task 7: Add leaderboard button to ContentView

**Files:**
- Modify: `ShellGame/ContentView.swift`

### Step 1: Add `showLeaderboard` state property

In the `@State` block (after `showNameEntry`), add:

```swift
@State private var showLeaderboard = false
```

### Step 2: Add a leaderboard button after the Play Now button

In the `body` VStack (around line 89 where `playNowButton` is referenced), add after `playNowButton`:

```swift
Spacer().frame(height: 10)

playNowButton
Spacer().frame(height: 8)

leaderboardButton     // ← add this line
Spacer().frame(height: 10)
```

Replace the existing:
```swift
playNowButton
Spacer().frame(height: 10)
```
With:
```swift
playNowButton
Spacer().frame(height: 8)

leaderboardButton
Spacer().frame(height: 10)
```

### Step 3: Add the `leaderboardButton` computed property

Add this new computed property below `playNowButton` (around line 537, before `duelButton`):

```swift
// MARK: - Leaderboard Button

private var leaderboardButton: some View {
    Button {
        showLeaderboard = true
    } label: {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Leaderboard")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule().strokeBorder(
                        Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.40),
                        lineWidth: 1.5
                    )
                )
        )
    }
}
```

### Step 4: Add the fullScreenCover for LeaderboardView

Find the existing `.fullScreenCover(isPresented: $showModes)` line. After it, add:

```swift
.fullScreenCover(isPresented: $showLeaderboard) {
    LeaderboardView()
}
```

### Step 5: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 6: Commit

```bash
git add ShellGame/ContentView.swift
git commit -m "feat: add leaderboard button to home screen"
```

---

## Task 8: Drain offline queue on app foreground

**Files:**
- Modify: `ShellGame/ContentView.swift`

ContentView already observes `@Environment(\.scenePhase)`. We just need to call `drainQueue()` when the app becomes active.

### Step 1: Find the `onChange(of: scenePhase)` handler in ContentView

Search ContentView for `scenePhase`. It's in the `.onChange` or `onAppear` block (around lines 114–150). Find the existing `onChange(of: scenePhase)` handler. If it doesn't exist yet, add one. If it does exist, add the drain call inside the `.active` case.

Add or extend the handler:

```swift
.onChange(of: scenePhase) { phase in
    if phase == .active {
        ScoreSubmissionService.shared.drainQueue()
    }
    // ... any existing scenePhase handling stays here
}
```

**Note:** If there is already an `.onChange(of: scenePhase)` block, add the `drainQueue()` call inside it when `phase == .active`. Do NOT create a second `.onChange(of: scenePhase)` block — that would cause only one to fire.

### Step 2: Build

```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Run the full test suite

```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -40
```

Expected: All tests PASS (44 existing + 7 new = 51 total).

### Step 4: Commit

```bash
git add ShellGame/ContentView.swift
git commit -m "feat: drain Supabase offline score queue on app foreground"
```

---

## Manual Verification Checklist

After all tasks complete, verify in Simulator:

- [ ] Name prompt sheet appears every time Play Now is tapped
- [ ] TextField pre-fills with the last-used name on re-launch
- [ ] Entering 21+ characters: input stops at 20
- [ ] Play button is disabled (greyed) when TextField is empty or whitespace-only
- [ ] After tapping Play: name saved, game starts normally
- [ ] After completing a round: score appears in Supabase dashboard within ~2 seconds
- [ ] Leaderboard button is visible on home screen
- [ ] Leaderboard shows the submitted score with correct player name
- [ ] Mode filter tabs (Solo / Gauntlet / Daily) correctly filter results
- [ ] Your own entry highlighted in yellow with "YOU" badge
- [ ] Existing Game Center leaderboard still submits (no regression)
- [ ] Airplane mode: play a round → score queued → reconnect → app foreground → score appears in Supabase

---

## Notes for the Implementer

- **`SupabaseConfig.swift` placeholder strings** — you must fill in the four `YOUR_*` values before Task 2 tests can pass against a real DB. For unit tests of the queue (Task 2), a real Supabase connection is not needed — those tests only touch UserDefaults.
- **Xcode target registration** — every new `.swift` file must be added to `project.pbxproj`. The pattern is: find an existing file (e.g. `GameState.swift`) in the PBXBuildFile and PBXGroup sections, duplicate those two blocks with a new UUID and the new filename. Generate UUIDs with `uuidgen | tr -d '-' | head -c 24`.
- **`drainQueue` recursion** — the recursive call in `ScoreSubmissionService.drainQueue()` is safe because it's callback-based (not stack-based); each call only proceeds if there's an item and the previous POST succeeded.
- **ISO8601 date decoding** — Supabase returns timestamps like `2026-05-05T12:34:56+00:00`. The `JSONDecoder.dateDecodingStrategy = .iso8601` handles this correctly.
