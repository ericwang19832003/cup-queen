# Home Screen Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Differentiate the home screen for new vs returning players — new players get a large animated cup demo, returning players get a progress card and compact idle cups, with cleaner hierarchy throughout.

**Architecture:** All changes are in `ShellGame/ContentView.swift`. Three new inline private structs are added: `HomeProgressCard`, `DemoShuffleView`, `IdleCupsView`. The existing `isReturningPlayer = savedHighScore > 0` gate drives which layout renders. No new files, no new dependencies.

**Tech Stack:** SwiftUI, UserDefaults (existing), existing `PreviewCupView` / `GoldenBallView` / `HostCharacterView` components. Pure SwiftUI animations — no SpriteKit on the home screen.

---

## Task 1: Add `HomeProgressCard` (returning player progress card)

**Files:**
- Modify: `ShellGame/ContentView.swift` — add inline private struct, wire into body

This replaces `bestStatsRow` and the greeting line in `titleSection` for returning players.

**Step 1: Add `HomeProgressCard` struct** at the bottom of `ContentView.swift`, before the closing of the file:

```swift
// MARK: - Home Progress Card

private struct HomeProgressCard: View {
    let level: Int
    let highScore: Int
    let wins: Int
    let prestigeCount: Int
    let playerName: String
    let bestSurvival: Int

    private var isMaxLevel: Bool { level >= 30 }
    private var progressFraction: CGFloat {
        // Each level = 1 win. Fraction is always the fractional part within current level.
        // wins = level - 1 at exact level boundary, so fraction resets per level.
        CGFloat(wins - (level - 1)) / 1.0  // always 0.0 or 1.0; expand when multi-win levels added
    }
    private var nextLevelLabel: String {
        if isMaxLevel {
            return bestSurvival > 0 ? "Survived \(bestSurvival) in a row" : "MAX LEVEL"
        }
        let winsNeeded = level - wins  // wins needed to reach next level
        let w = max(0, winsNeeded)
        return w == 1 ? "1 win to L\(level + 1)" : "\(w) wins to L\(level + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: level + score
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: isMaxLevel ? "crown.fill" : "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                    Text(isMaxLevel ? "MAX" : "Level \(level)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("\(highScore) pts")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                }
            }

            // Progress bar or survival count
            if isMaxLevel {
                Text(nextLevelLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 6)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1, green: 0.93, blue: 0.28),
                                                 Color(red: 1, green: 0.68, blue: 0.05)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * min(progressFraction, 1.0), height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text(nextLevelLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.50))
                }
            }

            // Greeting
            let trimmed = playerName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let crowns = prestigeCount > 0 ? " " + String(repeating: "👑", count: min(prestigeCount, 3)) : ""
                Text("Welcome back, \(trimmed)\(crowns)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.85))
                    .kerning(1.2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.55),
                                         Color.purple.opacity(0.30),
                                         Color.yellow.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }
}
```

**Step 2: Build to verify it compiles**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: add HomeProgressCard component for returning players"
```

---

## Task 2: Add `IdleCupsView` (returning player compact idle animation)

**Files:**
- Modify: `ShellGame/ContentView.swift` — add inline private struct

**Step 1: Add `IdleCupsView` struct** in `ContentView.swift` after `HomeProgressCard`:

```swift
// MARK: - Idle Cups View (returning player)

private struct IdleCupsView: View {
    @State private var leftY:   CGFloat = 0
    @State private var centreY: CGFloat = 0
    @State private var rightY:  CGFloat = 0
    @State private var glowPulse = false
    @State private var ballGlow  = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Spotlight
            Ellipse()
                .fill(Color.yellow.opacity(glowPulse ? 0.20 : 0.09))
                .frame(width: 96, height: 28)
                .blur(radius: 10)
                .offset(y: -12)

            // Felt strip
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.28, blue: 0.14),
                                 Color(red: 0.05, green: 0.18, blue: 0.09)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: 12)
                .padding(.horizontal, 8)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 4)

            // Cups + ball
            HStack(spacing: 20) {
                PreviewCupView(lit: false)
                    .offset(y: leftY)
                ZStack(alignment: .bottom) {
                    PreviewCupView(lit: true)
                        .offset(y: centreY)
                    GoldenBallView(diameter: 26, glowPulse: ballGlow)
                        .offset(y: centreY + 18)
                }
                PreviewCupView(lit: false)
                    .offset(y: rightY)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .onAppear {
            // Ball glow
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                ballGlow = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            // Staggered bob: left → centre → right, 3s total loop
            startBobLoop()
        }
    }

    private func bob(_ binding: Binding<CGFloat>, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.35)) { binding.wrappedValue = -8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.35) {
                withAnimation(.easeInOut(duration: 0.35)) { binding.wrappedValue = 0 }
            }
        }
    }

    private func startBobLoop() {
        bob($leftY,   delay: 0.0)
        bob($centreY, delay: 0.6)
        bob($rightY,  delay: 1.2)
        // Restart loop every 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { startBobLoop() }
    }
}
```

**Step 2: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: add IdleCupsView with staggered bob animation for returning players"
```

---

## Task 3: Add `DemoShuffleView` (new player animated demo)

**Files:**
- Modify: `ShellGame/ContentView.swift` — add inline private struct

This is the centrepiece: a full shuffle demo loop that teaches the game without words.

**Step 1: Add `DemoShuffleView` struct** in `ContentView.swift`:

```swift
// MARK: - Demo Shuffle View (new player)

private struct DemoShuffleView: View {
    // Cup X positions (slot-based): left=-108, centre=0, right=108, spacing accounts for cup width 88
    @State private var positions: [CGFloat] = [-108, 0, 108]   // index = cup identity
    @State private var ballOwner: Int = 1                        // cup index that holds ball
    @State private var ballVisible: Bool = true                  // false when hidden under cup
    @State private var revealCup: Int? = nil                     // cup index to lift for reveal
    @State private var cupLifted: [Bool] = [false, false, false]
    @State private var glowBurst: Bool = false
    @State private var ballGlow:  Bool = false

    // Fixed shuffle pairs (slot indices in positions array — not cup identity)
    // Centre↔Right, Left↔Centre, Centre↔Right, Left↔Centre
    private let shufflePairs: [(Int, Int)] = [(1,2),(0,1),(1,2),(0,1)]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Spotlight
            Ellipse()
                .fill(Color.yellow.opacity(glowBurst ? 0.35 : 0.14))
                .frame(width: 130, height: 40)
                .blur(radius: 14)
                .offset(y: -18)
                .animation(.easeInOut(duration: 0.4), value: glowBurst)

            // Felt strip
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.28, blue: 0.14),
                                 Color(red: 0.05, green: 0.18, blue: 0.09)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: 14)
                .padding(.horizontal, 8)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 5)

            // Cups + ball
            ZStack(alignment: .bottom) {
                ForEach(0..<3, id: \.self) { cup in
                    ZStack(alignment: .bottom) {
                        PreviewCupView(lit: cup == ballOwner && ballVisible)
                            .frame(width: 88, height: 108)
                            .offset(y: cupLifted[cup] ? -34 : 0)

                        // Ball — only visible when ballVisible and this cup owns it
                        if cup == ballOwner {
                            GoldenBallView(diameter: 30, glowPulse: ballGlow)
                                .opacity(ballVisible ? 0 : 1)  // hidden when cup is down (covered)
                                .offset(y: cupLifted[cup] ? 14 : 22)
                        }
                    }
                    .position(x: positions[cup] + 195, y: 60)  // 195 = half of ~390 width
                }

                // Ball visible on table BEFORE cup covers it (step 1) and at reveal (step 8)
                GoldenBallView(diameter: 30, glowPulse: ballGlow)
                    .opacity(ballVisible ? 1 : 0)
                    .position(x: positions[ballOwner] + 195, y: 95)
            }
            .frame(height: 120)
            .padding(.bottom, 14)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                ballGlow = true
            }
            runDemoLoop()
        }
    }

    private func runDemoLoop() {
        // Reset
        positions  = [-108, 0, 108]
        cupLifted  = [false, false, false]
        ballOwner  = 1
        ballVisible = true
        glowBurst   = false

        var t = 0.0

        // Step 1: Ball visible (0.8s hold) — already set above
        t += 0.8

        // Step 2: Cover ball (centre cup lifts then drops — hides ball)
        after(t) {
            ballVisible = false
        }
        t += 0.4

        // Step 3: Pause
        t += 0.5

        // Step 4: Shuffle (4 pairs × 0.55s each)
        for pair in shufflePairs {
            let (a, b) = pair
            after(t) { swapCups(a, b) }
            t += 0.55
        }
        t += 0.3  // settle

        // Step 5: All cups bob upward (inviting tap)
        after(t) {
            withAnimation(.easeInOut(duration: 0.30)) {
                cupLifted = [true, true, true]
            }
        }
        t += 0.30
        after(t) {
            withAnimation(.easeInOut(duration: 0.30)) {
                cupLifted = [false, false, false]
            }
        }
        t += 0.60

        // Step 6: Misdirection — lift a wrong cup (left cup = index 0)
        after(t) {
            withAnimation(.easeInOut(duration: 0.25)) { cupLifted[0] = true }
        }
        t += 0.35
        after(t) {
            withAnimation(.easeInOut(duration: 0.25)) { cupLifted[0] = false }
        }
        t += 0.50

        // Step 7: Beat pause (tension)
        t += 0.70

        // Step 8: Reveal correct cup
        after(t) {
            withAnimation(.easeInOut(duration: 0.35)) { cupLifted[ballOwner] = true }
            ballVisible = true
            withAnimation(.easeInOut(duration: 0.20)) { glowBurst = true }
        }
        t += 0.35

        // Step 9: Hold on reveal (1.5s)
        t += 1.5

        // Step 10: Cover again, restart
        after(t) {
            withAnimation(.easeInOut(duration: 0.25)) { cupLifted[ballOwner] = false }
            glowBurst = false
        }
        t += 0.5
        after(t) { runDemoLoop() }
    }

    private func after(_ delay: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    private func swapCups(_ a: Int, _ b: Int) {
        // Swap the x-positions of cups at indices a and b
        withAnimation(.easeInOut(duration: 0.50)) {
            let tmp = positions[a]
            positions[a] = positions[b]
            positions[b] = tmp
        }
        // Track ball owner
        if ballOwner == a { ballOwner = b }
        else if ballOwner == b { ballOwner = a }
    }
}
```

**Step 2: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: add DemoShuffleView with full demo loop for new players"
```

---

## Task 4: Wire up new player layout in `ContentView.body`

**Files:**
- Modify: `ShellGame/ContentView.swift` — replace `gamePreviewSection` with conditional, add `challengeBadge` gate

**Step 1: Replace the hero section and conditional badge** in the `body` VStack.

Find this block in `body`:
```swift
titleSection
Spacer().frame(height: 8)

challengeBadge
Spacer().frame(height: 10)

if savedHighScore > 0 {
    bestStatsRow
}
Spacer().frame(height: 14)

gamePreviewSection           // ← HERO: host + cups + ball
Spacer().frame(height: 6)
leaderboardTeaser
Spacer().frame(height: 12)

howToPlayRow
Spacer().frame(height: 18)

playNowButton
Spacer().frame(height: 8)

secondaryButtonRow
```

Replace with:
```swift
titleSection
Spacer().frame(height: 8)

if isReturningPlayer {
    // Returning player: progress card, compact cups, teaser, contextual CTA
    HomeProgressCard(
        level: savedBestLevel,
        highScore: savedHighScore,
        wins: UserDefaults.standard.integer(forKey: "cq_wins"),
        prestigeCount: savedPrestige,
        playerName: playerName,
        bestSurvival: savedBestSurvival
    )
    Spacer().frame(height: 12)

    HostCharacterView(glowPulse: glowPulse)
        .frame(height: 72)
    Spacer().frame(height: 6)

    idleCupsSection
    Spacer().frame(height: 8)

    leaderboardTeaser
    Spacer().frame(height: 14)

    continueButton
    Spacer().frame(height: 6)
    freshStartLink
    Spacer().frame(height: 8)
} else {
    // New player: challenge badge, large demo, how-to, play now
    challengeBadge
    Spacer().frame(height: 10)

    HostCharacterView(glowPulse: glowPulse)
        .frame(height: 80)
    Spacer().frame(height: 6)

    demoShuffleSection
    Spacer().frame(height: 14)

    howToPlayRow
    Spacer().frame(height: 18)

    playNowButton
    Spacer().frame(height: 8)
}

Divider()
    .background(Color.white.opacity(0.15))
    .padding(.horizontal, 8)
Spacer().frame(height: 10)

secondaryButtonRow
Spacer().frame(height: 24)
```

**Step 2: Add the `isReturningPlayer` computed property** and new section wrappers. Add these to `ContentView` alongside the other computed vars:

```swift
private var isReturningPlayer: Bool { savedHighScore > 0 }

private var idleCupsSection: some View {
    IdleCupsView()
        .frame(height: 130)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.32),
                             Color(red: 0.10, green: 0.05, blue: 0.26).opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(LinearGradient(
                        colors: [Color.yellow.opacity(0.55),
                                 Color.purple.opacity(0.30),
                                 Color.yellow.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5))
        )
}

private var demoShuffleSection: some View {
    DemoShuffleView()
        .frame(height: 170)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.32),
                             Color(red: 0.10, green: 0.05, blue: 0.26).opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(LinearGradient(
                        colors: [Color.yellow.opacity(0.55),
                                 Color.purple.opacity(0.30),
                                 Color.yellow.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5))
        )
}
```

**Step 3: Remove the greeting from `titleSection`** — it's moved into `HomeProgressCard`. Find in `titleSection`:
```swift
// Personalized welcome greeting with inline prestige crowns
let trimmedName = playerName.trimmingCharacters(in: .whitespaces)
if !trimmedName.isEmpty {
    Text("Welcome back, \(trimmedName)\(savedPrestige > 0 ? " " + String(repeating: "👑", count: min(savedPrestige, 3)) : "")")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.85))
        .kerning(1.5)
}
```
Delete that block entirely.

**Step 4: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: wire new vs returning player layout branches in ContentView"
```

---

## Task 5: Add `continueButton` and `freshStartLink` (returning player CTA)

**Files:**
- Modify: `ShellGame/ContentView.swift` — add two new computed properties

**Step 1: Add `continueButton`** alongside other button computed vars in `ContentView`:

```swift
private var continueButton: some View {
    Button {
        showNameEntry = true
        startFreshSelected = false
    } label: {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 17, weight: .bold))
            Text("Continue — Level \(savedBestLevel)")
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

**Step 2: Add `freshStartLink`** alongside `continueButton`:

```swift
private var freshStartLink: some View {
    Button {
        startFreshSelected = true
        showNameEntry = true
    } label: {
        Text("Fresh Start")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.40))
    }
    .buttonStyle(.plain)
}
```

**Step 3: Build to verify**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: add Continue and Fresh Start CTA for returning players"
```

---

## Task 6: Clean up old components no longer used

**Files:**
- Modify: `ShellGame/ContentView.swift` — remove unused computed properties

**Step 1: Delete `bestStatsRow`** computed property entirely. Search for:
```swift
// MARK: - Best Stats Row
private var bestStatsRow: some View {
```
Delete from that line through the closing `}` of the property (the one ending with `.padding(.vertical, 7)` and capsule background). It is fully replaced by `HomeProgressCard`.

**Step 2: Delete `gamePreviewSection`** and `cupTableView` and `centreWithBall`. These three computed properties are replaced by `demoShuffleSection` and `idleCupsSection`. Search for and delete:
```swift
// MARK: - Game Preview Section (HERO)
private var gamePreviewSection: some View {
```
...through and including `cupTableView` and `centreWithBall` (all three contiguous properties).

**Step 3: Build to verify nothing is broken by the removals**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**
```bash
git add ShellGame/ContentView.swift
git commit -m "chore: remove bestStatsRow and gamePreviewSection (replaced by new components)"
```

---

## Task 7: Final verification pass

**Step 1: Full build**
```bash
xcodebuild -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

**Step 2: Run existing test suite**
```bash
xcodebuild test -project ShellGame.xcodeproj -scheme ShellGame \
  -destination 'id=50282512-942F-4991-B223-C71DC01F715D' 2>&1 | grep "Executed"
```
Expected: all tests pass (no regressions — these changes are UI-only).

**Step 3: Manual checklist — simulate new player**
In `ContentView.onAppear`, temporarily set `savedHighScore = 0` to test new player path:
- [ ] Challenge badge visible
- [ ] Large demo cups visible (~170pt height)
- [ ] Demo loop runs: ball shows → cup covers → shuffle → misdirection → reveal → repeat
- [ ] How-to row visible
- [ ] "Play Now" button visible
- [ ] No progress card
- Revert the temp change after confirming.

**Step 4: Manual checklist — simulate returning player**
Set a nonzero highScore in UserDefaults or run through a game to earn one:
- [ ] Progress card visible with level, score, progress bar, greeting
- [ ] Compact idle cups visible (~130pt height), bob animation running
- [ ] Leaderboard teaser visible above CTA
- [ ] "Continue — Level X" button shows correct level
- [ ] "Fresh Start" ghost link visible below button
- [ ] No challenge badge
- [ ] No how-to row
- [ ] Divider visible between CTA and secondary row
- [ ] Secondary row (Leaderboard / Duel / Modes) unchanged

**Step 5: Final commit and push**
```bash
git add ShellGame/ContentView.swift
git commit -m "feat: home screen redesign — contextual new vs returning player layout"
git push origin main
```

---

## Success Criteria

- [ ] New player: title → badge → large animated demo → how-to → Play Now → (divider) → secondary row
- [ ] Returning player: title → progress card → compact idle cups → leaderboard teaser → Continue CTA → Fresh Start link → (divider) → secondary row
- [ ] Demo loop completes full sequence on repeat without drift or stutter
- [ ] Idle bob runs smoothly, no jank
- [ ] `freshStartLink` correctly routes through `startFresh: true` via existing `PlayerNameEntryView` flow
- [ ] Progress bar fills correctly for current level
- [ ] L30 players see survival count instead of progress bar
- [ ] All existing tests pass
- [ ] BUILD SUCCEEDED, 0 errors
