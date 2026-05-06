# Home Screen Polish — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Cup Queen home screen feel professional, personal, and visually striking through 6 focused improvements.

**Architecture:** All changes are confined to `ContentView.swift`. Task 4 adds a `LeaderboardTeaser` sub-view inside the same file that makes a single lightweight network fetch. No new files unless a sub-view grows beyond ~60 lines.

**Tech Stack:** SwiftUI, existing `SupabaseConfig`, existing `UserDefaults` keys (`cq_player_name`, `cq_wins`, `cq_prestige`)

---

### Task 1: Personalized Greeting

**Files:**
- Modify: `ShellGame/ContentView.swift` — `titleSection` computed var

**Spec:**
- Read `UserDefaults.standard.string(forKey: "cq_player_name")` and trim whitespace.
- If non-empty: show `"Welcome back, [name]"` in small caps below "CUP QUEEN".
- If empty: show nothing (new player, no greeting yet).
- Style: `.system(size: 13, weight: .semibold, design: .rounded)`, foreground `Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.85)`, letter-spacing 1.5.
- Prestige crowns (👑 ×N) move to be inline after the name (e.g. `"Welcome back, Alex 👑👑"`) instead of a separate HStack.
- Placement: between the "FIND THE BALL" subtitle and the `challengeBadge`.
- Use `@State private var playerName: String = ""` loaded in `.onAppear` alongside the other stat reloads (and in `reloadStats()`).

**Step 1:** Make the change to `titleSection` and `startAnimations` / `reloadStats` / `onAppear`.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: personalized welcome greeting with prestige crowns inline"
```

---

### Task 2: Compact 3-Column Secondary Button Row

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Spec:**
Replace the three separate `leaderboardButton`, `duelButton`, `modesButton` computed vars (and their spacers) in the `body` VStack with a single `secondaryButtonRow` computed var.

Remove from body:
```swift
leaderboardButton
Spacer().frame(height: 10)
duelButton
Spacer().frame(height: 8)
modesButton
```

Add in their place (after `Spacer().frame(height: 8)` below playNowButton):
```swift
secondaryButtonRow
```

The `secondaryButtonRow`:
```swift
private var secondaryButtonRow: some View {
    HStack(spacing: 10) {
        // Leaderboard
        Button { showLeaderboard = true } label: {
            VStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Leaderboard")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.40), lineWidth: 1.5))
            )
        }

        // Duel
        Button {
            if !GameCenterManager.shared.isAuthenticated { GameCenterManager.shared.authenticate() }
            showDuelLobby = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "swords")
                    .font(.system(size: 16, weight: .semibold))
                Text("Duel")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(red: 1, green: 0.88, blue: 0.30))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.yellow.opacity(0.45), lineWidth: 1.5))
            )
        }

        // Modes
        Button { if modesUnlocked { showModes = true } } label: {
            VStack(spacing: 5) {
                Image(systemName: modesUnlocked ? "star.circle.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Modes")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(modesUnlocked
                ? Color(red: 0.78, green: 0.58, blue: 1.00)
                : .white.opacity(0.28))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(modesUnlocked ? Color(red: 0.35, green: 0.10, blue: 0.60).opacity(0.22) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            modesUnlocked ? Color(red: 0.65, green: 0.40, blue: 1.00).opacity(0.45) : Color.white.opacity(0.10),
                            lineWidth: 1.2))
            )
        }
        .disabled(!modesUnlocked)
    }
}
```

Also delete the old `leaderboardButton`, `duelButton`, `modesButton` computed vars (they are now inlined into `secondaryButtonRow`).

**Step 1:** Apply the change.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: condense secondary buttons into compact 3-column row"
```

---

### Task 3: Move Reset Progress to Settings Sheet

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Spec:**

1. Add `@State private var showSettings = false`.

2. Replace the gear-free title area: in `titleSection`, the Game Center trophy button is in the `.topTrailing` corner. Add a **gear button in the `.topLeading` corner**:
```swift
// Settings gear — top-left
Button { showSettings = true } label: {
    Image(systemName: "gearshape.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white.opacity(0.40))
}
.offset(x: -4, y: 2)
```
The `titleSection` ZStack currently has alignment `.topTrailing`. Change to just a ZStack with two overlay buttons positioned manually, or keep `.topTrailing` for the GC button and use a separate `.overlay(alignment: .topLeading)` on the VStack.

Simplest approach — keep the existing ZStack structure, add the gear as a separate overlay on the outer VStack in `body`:
```swift
// In body, after .padding(.horizontal, 22):
.overlay(alignment: .topLeading) {
    Button { showSettings = true } label: {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 16))
            .foregroundColor(.white.opacity(0.35))
            .padding(.top, 62)
            .padding(.leading, 22)
    }
}
```

3. Add a `.sheet(isPresented: $showSettings)` modifier alongside the other sheets:
```swift
.sheet(isPresented: $showSettings) {
    SettingsSheet(onReset: {
        resetProgress()
        showSettings = false
    })
}
```

4. Add `SettingsSheet` as a private struct at the bottom of `ContentView.swift` (before the `// MARK: - Host Character` section):
```swift
// MARK: - Settings Sheet

private struct SettingsSheet: View {
    let onReset: () -> Void
    @State private var showResetConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.12, green: 0.04, blue: 0.26)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Text("Settings")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                VStack(spacing: 0) {
                    Button {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red.opacity(0.80))
                            Text("Reset Progress")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.red.opacity(0.80))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .presentationDetents([.height(280)])
        .alert("Reset Progress?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { onReset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear your level, score, and all wins. You'll restart from Level 1.")
        }
    }
}
```

5. Remove `resetProgressButton` and `footerText` from the body VStack, and remove the `resetProgressButton` and `footerText` computed var definitions.

6. Remove `@State private var showResetAlert` (now handled inside SettingsSheet).

**Step 1:** Apply all changes.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: move Reset Progress to gear settings sheet, remove footer clutter"
```

---

### Task 4: Live #1 Leaderboard Teaser

**Files:**
- Modify: `ShellGame/ContentView.swift`

**Spec:**
Add a small "live teaser" strip below the `gamePreviewSection` showing the current #1 global score.

1. Add state to ContentView:
```swift
@State private var topScore: (name: String, score: Int)? = nil
```

2. Add a `leaderboardTeaser` computed var:
```swift
private var leaderboardTeaser: some View {
    Group {
        if let top = topScore {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                Text("Top score:")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                Text(top.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                Text("·")
                    .foregroundColor(.white.opacity(0.30))
                Text("\(top.score) pts")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(red: 1, green: 0.75, blue: 0.10).opacity(0.09))
                    .overlay(Capsule().strokeBorder(
                        Color(red: 1, green: 0.80, blue: 0.22).opacity(0.28), lineWidth: 1))
            )
        }
    }
}
```

3. In the body VStack, add `leaderboardTeaser` and a `Spacer().frame(height: 6)` immediately after `gamePreviewSection` and its spacer:
```swift
gamePreviewSection
Spacer().frame(height: 6)
leaderboardTeaser
Spacer().frame(height: 12)
```
(Remove the existing `Spacer().frame(height: 18)` that was after `gamePreviewSection`.)

4. Add a `fetchTopScore()` function:
```swift
private func fetchTopScore() {
    guard var components = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/scores") else { return }
    components.queryItems = [
        URLQueryItem(name: "select", value: "player_name,score"),
        URLQueryItem(name: "order",  value: "score.desc"),
        URLQueryItem(name: "limit",  value: "1")
    ]
    guard let url = components.url else { return }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data,
              let arr = try? JSONDecoder().decode([[String: AnyCodable]].self, from: data),
              let first = arr.first,
              let name = first["player_name"]?.value as? String,
              let score = first["score"]?.value as? Int else { return }
        DispatchQueue.main.async { topScore = (name: name, score: score) }
    }.resume()
}
```

Note: `AnyCodable` is not available without a library. Use a simple struct instead:

```swift
private struct TopEntry: Decodable {
    let playerName: String
    let score: Int
    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case score
    }
}

private func fetchTopScore() {
    guard var components = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/scores") else { return }
    components.queryItems = [
        URLQueryItem(name: "select", value: "player_name,score"),
        URLQueryItem(name: "order",  value: "score.desc"),
        URLQueryItem(name: "limit",  value: "1")
    ]
    guard let url = components.url else { return }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data,
              let entries = try? JSONDecoder().decode([TopEntry].self, from: data),
              let top = entries.first else { return }
        DispatchQueue.main.async { self.topScore = (name: top.playerName, score: top.score) }
    }.resume()
}
```

5. Call `fetchTopScore()` in `.onAppear` alongside `startAnimations()`.

6. Also call it in `.onChange(of: scenePhase) { if newPhase == .active { fetchTopScore(); ... } }`.

`TopEntry` struct can be a private struct defined just before ContentView or at the top of the MARK: - ContentView section.

**Step 1:** Apply the change.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: live #1 leaderboard teaser strip on home screen"
```

---

### Task 5: Replace Code-Drawn Magician with Polished Hero Emblem

**Files:**
- Modify: `ShellGame/ContentView.swift` — `HostCharacterView` struct

**Spec:**
Replace the `HostCharacterView` code-drawn character (~100 lines of Capsule/Circle shapes) with a polished **magic emblem** that looks intentional and premium. The frame stays `height: 90`.

The new `HostCharacterView` is a layered composition:

```swift
private struct HostCharacterView: View {
    let glowPulse: Bool

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.55, green: 0.02, blue: 0.75).opacity(glowPulse ? 0.45 : 0.22),
                            Color.clear
                        ],
                        center: .center, startRadius: 20, endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // Inner ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 1, green: 0.85, blue: 0.22).opacity(0.85),
                            Color(red: 0.75, green: 0.25, blue: 1.00).opacity(0.60),
                            Color(red: 1, green: 0.85, blue: 0.22).opacity(0.85)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 82, height: 82)

            // Top hat emoji — large, crisp
            Text("🎩")
                .font(.system(size: 42))
                .offset(y: -2)
                .shadow(color: Color(red: 1, green: 0.80, blue: 0.10).opacity(0.70), radius: 12)

            // Sparkle accents at cardinal positions
            ForEach([(CGFloat(-46), CGFloat(-8)), (46, -8), (0, -52), (-28, 38), (28, 38)], id: \.0) { (x, y) in
                Image(systemName: "sparkle")
                    .font(.system(size: x == 0 ? 10 : 7, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.22).opacity(glowPulse ? 0.90 : 0.45))
                    .offset(x: x, y: y)
            }
        }
        .compositingGroup()
    }
}
```

Note: The `ForEach` on a tuple array needs a proper approach. Use an array of named structs or just 5 explicit `Image` modifiers:

```swift
// Sparkle — top
Image(systemName: "sparkle")
    .font(.system(size: 10, weight: .bold))
    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.22).opacity(glowPulse ? 0.90 : 0.45))
    .offset(x: 0, y: -52)

// Sparkle — left
Image(systemName: "sparkle")
    .font(.system(size: 7, weight: .bold))
    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.22).opacity(glowPulse ? 0.80 : 0.38))
    .offset(x: -46, y: -8)

// Sparkle — right
Image(systemName: "sparkle")
    .font(.system(size: 7, weight: .bold))
    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.22).opacity(glowPulse ? 0.80 : 0.38))
    .offset(x: 46, y: -8)

// Sparkle — bottom-left
Image(systemName: "sparkle")
    .font(.system(size: 8, weight: .bold))
    .foregroundColor(Color(red: 0.78, green: 0.50, blue: 1.00).opacity(glowPulse ? 0.70 : 0.30))
    .offset(x: -28, y: 36)

// Sparkle — bottom-right
Image(systemName: "sparkle")
    .font(.system(size: 8, weight: .bold))
    .foregroundColor(Color(red: 0.78, green: 0.50, blue: 1.00).opacity(glowPulse ? 0.70 : 0.30))
    .offset(x: 28, y: 36)
```

Delete the old `PreviewCupView.drawCup` private method body — keep `PreviewCupView` intact. Only replace `HostCharacterView`.

**Step 1:** Replace `HostCharacterView` with the new implementation.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: replace code-drawn magician with polished magic emblem"
```

---

### Task 6: Optimize Star Field with Canvas

**Files:**
- Modify: `ShellGame/ContentView.swift` — `starField` computed var and `backgroundStars` / `makeStars()` / `StarData`

**Spec:**
Replace the 28 individually-animated `Circle()` views in `starField` with a single `TimelineView` + `Canvas` that draws all stars in one GPU call.

Remove:
- `makeStars()` function
- `backgroundStars` constant
- `StarData` struct
- `@State private var animateStars`
- `startAnimations()` call to `animateStars = true`

Replace `starField` with:

```swift
private var starField: some View {
    TimelineView(.animation) { timeline in
        Canvas { ctx, size in
            let t = timeline.date.timeIntervalSinceReferenceDate
            for i in 0..<28 {
                let x: CGFloat       = CGFloat(i) * 14.2 + 8
                let rawY: CGFloat    = CGFloat((i * 41 + 17) % 860)
                let y                = rawY * (size.height / 860)
                let baseOpacity: Double = 0.25 + Double(i % 6) * 0.09
                let duration: Double = 1.4  + Double(i % 7) * 0.18
                let delay: Double    = Double(i % 9) * 0.22
                let phase            = (t - delay).truncatingRemainder(dividingBy: duration * 2) / (duration * 2)
                let pulse            = 0.5 - 0.5 * cos(phase * 2 * .pi)   // 0→1→0
                let opacity          = baseOpacity * (0.46 + 0.54 * pulse)
                let radius: CGFloat  = CGFloat(1 + (i % 4)) * (0.7 + 0.8 * pulse)
                let rect = CGRect(x: x - radius, y: y - radius,
                                  width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color(.yellow.opacity(opacity)))
            }
        }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
}
```

IMPORTANT: `animateStars` is only used to trigger the star animation. After removing it, check if it's referenced anywhere else (it should only be in `startAnimations()` and `starField`). Remove both references.

Also remove `@State private var animateStars = false` from the state declarations.

**Step 1:** Apply the change.

**Step 2:** Build:
```bash
cd /Users/minwang/cup_game && xcodebuild build -project ShellGame.xcodeproj \
  -scheme ShellGame -destination 'generic/platform=iOS Simulator' 2>&1 | tail -3
```

**Step 3:** Commit:
```bash
git add ShellGame/ContentView.swift
git commit -m "perf: replace 28 animated Circle views with single Canvas star field"
```
