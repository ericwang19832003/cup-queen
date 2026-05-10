// ContentView.swift
// CUP QUEEN — Las Vegas Arcade Shell Game
// Home screen: gameplay-first layout. Cups are the hero. App Store safe.
//
// Extension points:
//   GAMECENTER : Leaderboard button → GKGameCenterViewController
//   SKINS      : Skin picker sheet
//   ANALYTICS  : Track open → "Play Now" tap funnel

import SwiftUI
import StoreKit
import UserNotifications

// MARK: - ContentView

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var glowPulse      = false
    @State private var ctaPulse       = false
    @State private var ballGlow       = false
    @State private var showGameCenter = false
    @State private var showDuelLobby = false
    @State private var showSettings   = false
    @State private var showModes      = false
    @State private var showConflict  = false
    @State private var showNameEntry  = false
    @State private var navigateToGame = false
    @State private var showLeaderboard = false
    @State private var playWasTapped   = false
    @State private var startFreshSelected: Bool = false
    @State private var localSnap: [String: Any]  = [:]
    @State private var remoteSnap: [String: Any] = [:]
    @State private var playerName: String = ""
    @State private var topScore: (name: String, score: Int)? = nil
    @State private var rival: (name: String, score: Int)? = nil

    // Persisted best stats — read fresh each time view appears
    @State private var savedHighScore: Int = 0
    @State private var savedBestLevel: Int = 1
    @State private var savedBestSurvival: Int = 0
    @State private var savedPrestige: Int  = 0
    @State private var modesUnlocked: Bool = false
    @State private var savedCompetitionWins: Int = 0
    @State private var savedStreakCount: Int = 0
    @ObservedObject private var cosmeticState = CosmeticState.shared
    @State private var showCustomize: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                casinoBackground
                curtainBackdrop
                starField
                cupSpotlight
                marqueeLights
                blueAccentLights

                VStack(spacing: 0) {
                    Spacer().frame(height: 44)   // below Dynamic Island

                    // Jester mascot — top of screen like the real arcade machine
                    JesterMascotView(glowPulse: glowPulse, compact: true)
                        .frame(height: 58)
                    Spacer().frame(height: 2)

                    topBar
                    Spacer().frame(height: 8)

                    if isReturningPlayer {
                        // ── RETURNING PLAYER ────────────────────────────────
                        // 1. Cups — theatrical entrance, then idle bob
                        idleCupsSection
                        Spacer().frame(height: 14)

                        // 2. Named rival hook (most powerful retention lever)
                        rivalHook
                        Spacer().frame(height: 10)


                        // 4. Daily tension — streak or "play today" nudge
                        dailyTensionWidget
                        Spacer().frame(height: 16)

                        // 5. Primary CTA
                        continueButton
                        Spacer().frame(height: 8)
                    } else {
                        // ── NEW PLAYER ───────────────────────────────────────
                        titleSection
                        Spacer().frame(height: 8)

                        challengeBadge
                        Spacer().frame(height: 10)

                        demoShuffleSection
                        Spacer().frame(height: 14)

                        howToPlayRow
                        Spacer().frame(height: 18)

                        playNowButton
                        Spacer().frame(height: 8)
                    }

                    tabBar
                }
                .padding(.horizontal, 22)
            }
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: $showSettings) {
                SettingsSheet(onReset: {
                    resetProgress()
                    showSettings = false
                })
            }
            .sheet(isPresented: $showGameCenter) { GameCenterView() }
            .sheet(isPresented: $showNameEntry, onDismiss: {
                if playWasTapped {
                    navigateToGame = true
                    playWasTapped = false
                    // startFreshSelected intentionally kept — GameView reads it next
                } else {
                    startFreshSelected = false  // dismissed without playing; reset for next time
                }
            }) {
                PlayerNameEntryView(initialStartFresh: startFreshSelected) { startFresh in
                    startFreshSelected = startFresh
                    playWasTapped = true
                    showNameEntry = false
                }
            }
            .navigationDestination(isPresented: $navigateToGame) {
                GameView(startFresh: startFreshSelected)
            }
            .fullScreenCover(isPresented: $showDuelLobby) {
                CompetitionView()
            }
            .fullScreenCover(isPresented: $showModes) {
                ModesView()
            }
            .fullScreenCover(isPresented: $showLeaderboard) {
                LeaderboardView()
            }
            .onAppear {
                startAnimations()
                fetchTopScore()
                savedHighScore    = UserDefaults.standard.integer(forKey: "cq_highScore")
                savedBestLevel    = max(1, UserDefaults.standard.integer(forKey: "cq_bestLevel"))
                savedBestSurvival = UserDefaults.standard.integer(forKey: "cq_bestSurvival")
                savedPrestige     = UserDefaults.standard.integer(forKey: "cq_prestige")
                modesUnlocked     = savedBestLevel >= 7
                playerName        = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
                savedCompetitionWins = UserDefaults.standard.integer(forKey: "cq_competition_wins")
                savedStreakCount = StreakManager.shared.streakCount
                SoundManager.shared.startHomeAmbient()   // Feature 1: home screen jazz
                checkiCloudConflict()
                submitHighScoreCatchup()
                fetchRival()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    ScoreSubmissionService.shared.drainQueue()
                    checkiCloudConflict()
                    fetchTopScore()
                }
            }
            .sheet(isPresented: $showConflict) {
                iCloudConflictView(
                    localSnapshot: localSnap,
                    remoteSnapshot: remoteSnap,
                    onKeepLocal: {
                        iCloudSyncManager.shared.applyLocal()
                        showConflict = false
                        reloadStats()
                    },
                    onUseRemote: {
                        iCloudSyncManager.shared.applyiCloud()
                        showConflict = false
                        reloadStats()
                    }
                )
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showCustomize) { CustomizeView() }
            .onChange(of: showDuelLobby) { isShowing in
                // Restart home ambient when competition fullScreenCover is dismissed
                // (ContentView stays in hierarchy during fullScreenCover so onAppear won't re-fire)
                if !isShowing { SoundManager.shared.startHomeAmbient() }
            }
        }
    }

    private func reloadStats() {
        savedHighScore    = UserDefaults.standard.integer(forKey: "cq_highScore")
        savedBestLevel    = max(1, UserDefaults.standard.integer(forKey: "cq_bestLevel"))
        savedBestSurvival = UserDefaults.standard.integer(forKey: "cq_bestSurvival")
        savedPrestige     = UserDefaults.standard.integer(forKey: "cq_prestige")
        modesUnlocked     = savedBestLevel >= 7
        playerName        = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
        savedCompetitionWins = UserDefaults.standard.integer(forKey: "cq_competition_wins")
        savedStreakCount  = StreakManager.shared.streakCount
    }

    private func checkiCloudConflict() {
        guard !showConflict else { return }
        let mgr = iCloudSyncManager.shared
        if mgr.hasConflict() {
            localSnap  = mgr.localSnapshot()
            remoteSnap = mgr.remoteSnapshot()
            showConflict = true
        } else {
            mgr.silentlyApplyRemoteIfNewer()
            reloadStats()
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glowPulse = true }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { ctaPulse  = true }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { ballGlow  = true }
    }

    /// One-time retroactive submission: if the user has a saved high score that
    /// was never uploaded (e.g. force-quit before session end), submit it now.
    private func submitHighScoreCatchup() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: "cq_catchup_submitted") else { return }
        let high = ud.integer(forKey: "cq_highScore")
        let name = ud.string(forKey: "cq_player_name") ?? ""
        let level = max(1, ud.integer(forKey: "cq_bestLevel"))
        guard high > 0, !name.isEmpty else { return }
        ud.set(true, forKey: "cq_catchup_submitted")
        ScoreSubmissionService.shared.submit(
            playerName: name, score: high, mode: "solo", level: level
        )
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

    /// Fetch the player ranked just above the current user — creates a named rival.
    private func fetchRival() {
        guard savedHighScore > 0 else { return }
        guard var components = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/scores") else { return }
        components.queryItems = [
            URLQueryItem(name: "select", value: "player_name,score"),
            URLQueryItem(name: "score",  value: "gt.\(savedHighScore)"),
            URLQueryItem(name: "order",  value: "score.asc"),
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
                  let r = entries.first else { return }
            DispatchQueue.main.async { self.rival = (name: r.playerName, score: r.score) }
        }.resume()
    }

    // MARK: - Rival Hook

    /// Shows the player just above the user in the leaderboard — named, with score gap.
    private var rivalHook: some View {
        Group {
            if let r = rival {
                let gap = r.score - savedHighScore
                let fraction = savedHighScore > 0
                    ? min(CGFloat(savedHighScore) / CGFloat(r.score), 1.0)
                    : 0
                Button { showLeaderboard = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 1, green: 0.38, blue: 0.18))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(r.name)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.90))
                                    .lineLimit(1)
                                Text("is \(gap) pts ahead")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            // Thin bar: my score vs rival score
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 2)
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 1, green: 0.38, blue: 0.18),
                                                     Color(red: 1, green: 0.65, blue: 0.05)],
                                            startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * fraction, height: 2)
                                }
                            }
                            .frame(height: 2)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 1, green: 0.28, blue: 0.10).opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(red: 1, green: 0.38, blue: 0.18).opacity(0.30),
                                              lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Daily Tension Widget

    private var dailyTensionWidget: some View {
        let gold   = Color(red: 1, green: 0.83, blue: 0.22)
        let streak = savedStreakCount

        return Group {
            if streak >= 2 {
                // Active streak — show it with urgency
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.10))
                    Text("\(streak)-day streak")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(gold)
                    Text("· Keep it alive today")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color(red: 1, green: 0.45, blue: 0.10).opacity(0.10))
                        .overlay(Capsule().strokeBorder(
                            Color(red: 1, green: 0.55, blue: 0.10).opacity(0.28), lineWidth: 1))
                )
            }
        }
    }

    private var leaderboardTeaser: some View {
        Group {
            if let top = topScore {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                    Text("Top score:")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    Text(top.name)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                    Text("·")
                        .foregroundColor(.white.opacity(0.30))
                    Text("\(top.score) pts")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
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

    // MARK: - Background

    private var casinoBackground: some View {
        ZStack {
            // Deep carnival navy — darker than before so lights pop
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.02, blue: 0.14),
                    Color(red: 0.08, green: 0.03, blue: 0.20),
                    Color(red: 0.04, green: 0.02, blue: 0.14)
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Strong edge vignette — pushes focus to center stage
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.72)],
                center: .center,
                startRadius: 100,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }

    /// Red velvet curtain panel behind the cups — arcade machine theatrical stage feel.
    private var curtainBackdrop: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 78)   // pulled up so jester peeks from curtain top
            ZStack {
                // Curtain body — deep burgundy red
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.04, blue: 0.06),
                        Color(red: 0.28, green: 0.02, blue: 0.04),
                        Color(red: 0.45, green: 0.04, blue: 0.06)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                // Centre spotlight on curtain
                RadialGradient(
                    colors: [Color(red: 0.70, green: 0.10, blue: 0.08).opacity(0.55), Color.clear],
                    center: .center, startRadius: 0, endRadius: 200
                )
                // Top gold trim rail
                VStack {
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.90, blue: 0.30),
                                 Color(red: 0.85, green: 0.60, blue: 0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 4)
                    Spacer()
                    // Bottom gold trim rail
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.90, blue: 0.30),
                                 Color(red: 0.85, green: 0.60, blue: 0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 4)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            .shadow(color: Color.black.opacity(0.65), radius: 18, y: 10)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// Arcade-cabinet perimeter bulbs — warm white incandescent style like the real machine.
    private var marqueeLights: some View {
        GeometryReader { _ in
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                Canvas { ctx, size in
                    let t   = timeline.date.timeIntervalSinceReferenceDate
                    let r: CGFloat   = 9.0      // large round bulbs
                    let pad: CGFloat = r + 3    // tight inset
                    let gap: CGFloat = 30       // even spacing
                    let warm = Color(red: 1.00, green: 0.95, blue: 0.78)   // incandescent white

                    // Build perimeter positions (clockwise)
                    var pts: [(CGFloat, CGFloat)] = []
                    var x = pad; while x <= size.width - pad  { pts.append((x, pad)); x += gap }
                    var y = pad + gap; while y <= size.height - pad { pts.append((size.width - pad, y)); y += gap }
                    x = size.width - pad - gap; while x >= pad { pts.append((x, size.height - pad)); x -= gap }
                    y = size.height - pad - gap; while y > pad { pts.append((pad, y)); y -= gap }

                    guard !pts.isEmpty else { return }

                    for (i, p) in pts.enumerated() {
                        // Gentle independent twinkle — no chase, just subtle life
                        let phase    = t * 0.6 + Double(i) * 0.38
                        let twinkle  = 0.88 + 0.12 * sin(phase)

                        // Outer warm glow
                        let gr = r * 2.4
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.0 - gr, y: p.1 - gr,
                                                   width: gr * 2, height: gr * 2)),
                            with: .color(warm.opacity(0.22 * twinkle))
                        )
                        // Socket ring (dark, gives depth like a real bulb in a socket)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.0 - r, y: p.1 - r,
                                                   width: r * 2, height: r * 2)),
                            with: .color(Color(red: 0.12, green: 0.08, blue: 0.04))
                        )
                        // Lit glass interior
                        let ir = r * 0.70
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.0 - ir, y: p.1 - ir,
                                                   width: ir * 2, height: ir * 2)),
                            with: .color(warm.opacity(0.80 * twinkle))
                        )
                        // Specular highlight (top-left)
                        let sr = r * 0.30
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.0 - sr * 1.2, y: p.1 - sr * 1.4,
                                                   width: sr * 1.2, height: sr * 0.9)),
                            with: .color(Color.white.opacity(0.75 * twinkle))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Two blue disco-ball accent lights at the top corners — matches the real arcade machine.
    private var blueAccentLights: some View {
        VStack(spacing: 0) {
            HStack {
                blueDiscoLight(pulse: glowPulse, delay: 0)
                Spacer()
                blueDiscoLight(pulse: glowPulse, delay: 0.5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 52)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func blueDiscoLight(pulse: Bool, delay: Double) -> some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(Color(red: 0.20, green: 0.45, blue: 1.00)
                    .opacity(pulse ? 0.40 : 0.20))
                .frame(width: 48, height: 48)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                    .delay(delay), value: pulse)
            // Main disc body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.45, green: 0.70, blue: 1.00),
                            Color(red: 0.10, green: 0.30, blue: 0.90)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 16
                    )
                )
                .frame(width: 28, height: 28)
            // Specular
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 9, height: 9)
                .offset(x: -6, y: -6)
        }
    }

    private var starField: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<28 {
                    let x: CGFloat       = CGFloat(i) * 14.2 + 8
                    let rawY: CGFloat    = CGFloat((i * 41 + 17) % 860)
                    let y                = rawY * (size.height / 860)
                    let baseOpacity: Double = 0.12 + Double(i % 6) * 0.04
                    let duration: Double = 1.4  + Double(i % 7) * 0.18
                    let delay: Double    = Double(i % 9) * 0.22
                    let phase            = (t - delay).truncatingRemainder(dividingBy: duration * 2) / (duration * 2)
                    let pulse            = 0.5 - 0.5 * cos(phase * 2 * .pi)
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

    /// Soft yellow spotlight aimed at the cup preview (mid-screen).
    private var cupSpotlight: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 200)
            RadialGradient(
                colors: [
                    Color.yellow.opacity(glowPulse ? 0.14 : 0.07),
                    Color.clear
                ],
                center: .top, startRadius: 0, endRadius: 380
            )
            .frame(height: 380)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Title Section

    private var topBar: some View {
        ZStack {
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                }
                Spacer()
                if !isReturningPlayer && GameCenterManager.shared.isAuthenticated {
                    Button { showGameCenter = true } label: {
                        Image(systemName: "trophy.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                    }
                } else if isReturningPlayer {
                    // Score at trailing edge
                    HStack(spacing: 2) {
                        Text(savedHighScore.formatted())
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.92, blue: 0.55))
                        Text("pts")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22).opacity(0.80))
                    }
                }
            }
            // Illuminated arcade marquee sign — matches the "Find the ball" sign on the real machine
            if isReturningPlayer {
                arcadeSign(text: "CUP QUEEN", pulse: glowPulse)
            }
        }
    }

    // MARK: - Arcade Sign (matches "Find the ball" illuminated panel on real machine)

    /// Illuminated sign with small LED dots around the border — like the arcade machine's title panel.
    private func arcadeSign(text: String, pulse: Bool) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.95, blue: 0.50),
                        Color(red: 1.00, green: 0.75, blue: 0.10),
                        Color(red: 1.00, green: 0.95, blue: 0.50)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    // Sign body — dark maroon like the arcade
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.22, green: 0.03, blue: 0.04))
                    // LED dot border — drawn with Canvas to match arcade machine
                    Canvas { ctx, size in
                        let r: CGFloat   = 3.2
                        let gap: CGFloat = 12
                        let pad: CGFloat = r + 3
                        let dotColor     = Color(red: 1.00, green: 0.90, blue: 0.30)
                        var pts: [(CGFloat, CGFloat)] = []
                        var x = pad; while x <= size.width - pad  { pts.append((x, pad)); x += gap }
                        var y = pad + gap; while y <= size.height - pad { pts.append((size.width - pad, y)); y += gap }
                        x = size.width - pad - gap; while x >= pad { pts.append((x, size.height - pad)); x -= gap }
                        y = size.height - pad - gap; while y > pad { pts.append((pad, y)); y -= gap }
                        for p in pts {
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: p.0 - r, y: p.1 - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(dotColor.opacity(0.92))
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    // Outer border
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.88, blue: 0.28),
                                         Color(red: 0.85, green: 0.55, blue: 0.05),
                                         Color(red: 1, green: 0.88, blue: 0.28)],
                                startPoint: .leading, endPoint: .trailing
                            ), lineWidth: 1.5
                        )
                }
                .shadow(color: Color(red: 1, green: 0.70, blue: 0.05)
                    .opacity(pulse ? 0.75 : 0.30),
                        radius: pulse ? 12 : 6)
            )
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 4) {
            Text("CUP QUEEN")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.93, blue: 0.38),
                            Color(red: 1.00, green: 0.68, blue: 0.05),
                            Color(red: 1.00, green: 0.93, blue: 0.38)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 1, green: 0.7, blue: 0).opacity(0.9), radius: 20, y: 3)

            Text("PICK THE RIGHT CUP")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.75))
                .tracking(5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Challenge Badge

    private var challengeBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(Color(red: 1, green: 0.45, blue: 0.18))
            Text("Only 1% of players beat Level 7")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.62, blue: 0.22), Color(red: 1, green: 0.36, blue: 0.15)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(Color(red: 1, green: 0.45, blue: 0.18))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 1, green: 0.35, blue: 0.12).opacity(0.13))
                .overlay(Capsule().strokeBorder(
                    Color(red: 1, green: 0.45, blue: 0.12).opacity(0.40), lineWidth: 1
                ))
        )
    }

    // MARK: - How to Play (horizontal, compact)

    private var howToPlayRow: some View {
        HStack(spacing: 0) {
            howToStep(icon: "eye.fill",            label: "Watch the Ball")
            rowDivider
            howToStep(icon: "arrow.triangle.swap", label: "Follow Cups")
            rowDivider
            howToStep(icon: "hand.tap.fill",       label: "Tap to Win")
        }
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.30), Color.purple.opacity(0.20)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private func howToStep(icon: String, label: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.80))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.22))
            .frame(width: 1, height: 46)
    }

    // MARK: - Play Now Button (pulsing CTA)

    private var playNowButton: some View {
        Button {
            showNameEntry = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.body.weight(.bold))
                Text("Play Now")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
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
        .accessibilityLabel("Play Now")
        .accessibilityHint("Enter your name and start a new game")
    }

    // MARK: - Returning / New Player Computed Properties

    private var isReturningPlayer: Bool { savedHighScore > 0 }

    private var rankTier: Int {
        let wins = savedCompetitionWins
        let atMaxLevel = savedBestLevel >= 7
        if wins >= 300 && atMaxLevel { return 4 }
        if wins >= 150 { return 3 }
        if wins >= 50  { return 2 }
        if wins >= 10  { return 1 }
        return 0
    }

    private var rankBadge: String { ["🥉","🥈","🥇","💎","👑"][rankTier] }
    private var rankName:  String { ["Bronze","Silver","Gold","Diamond","Master"][rankTier] }

    private var idleCupsSection: some View {
        IdleCupsView()
            .frame(height: 240)
    }

    // MARK: - Single compact stat row for returning players

    private var playerStatsRow: some View {
        let gold      = Color(red: 1, green: 0.83, blue: 0.22)
        let goldLight = Color(red: 1, green: 0.92, blue: 0.55)
        let wins      = UserDefaults.standard.integer(forKey: "cq_wins")
        let level     = savedBestLevel
        let fraction  = level > 0 ? min(CGFloat(wins) / CGFloat(level), 1.0) : 0
        let winsNeeded = max(0, level - wins)
        let label     = winsNeeded == 1 ? "1 win to L\(level + 1)" : "\(winsNeeded) wins to L\(level + 1)"

        return HStack(spacing: 10) {
            // Level pill
            HStack(spacing: 3) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(gold)
                Text("L\(level)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(goldLight)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(gold.opacity(0.14))
                .overlay(Capsule().strokeBorder(gold.opacity(0.25), lineWidth: 1)))

            // Progress bar — fills remaining horizontal space
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09)).frame(height: 3)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.93, blue: 0.28),
                                     Color(red: 1, green: 0.65, blue: 0.05)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction, height: 3)
                }
            }
            .frame(height: 3)

            // Progress label — fixed width so bar doesn't jitter
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize()
        }
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

    private var continueButton: some View {
        Button {
            startFreshSelected = false
            navigateToGame = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.body.weight(.bold))
                Text("CONTINUE L\(savedBestLevel)")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .tracking(1)
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
                color: Color(red: 1, green: 0.75, blue: 0.10).opacity(ctaPulse ? 0.50 : 0.22),
                radius: ctaPulse ? 18 : 8, y: 3
            )
        }
        .accessibilityLabel("Continue at Level \(savedBestLevel)")
        .accessibilityHint("Resume your saved game")
    }

    private var freshStartLink: some View {
        Button {
            startFreshSelected = true
            navigateToGame = true
        } label: {
            Text("New Game")
                .font(.system(size: 15, design: .rounded).weight(.semibold))
                .foregroundColor(.white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .overlay(Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                )
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            // Rank
            tabBarItem(icon: "trophy.fill", label: "Rank",
                       activeColor: Color(red: 1.00, green: 0.83, blue: 0.22),
                       active: true) {
                showLeaderboard = true
            }

            // Battle
            tabBarItem(icon: "bolt.fill", label: "Battle",
                       activeColor: Color(red: 0.55, green: 0.82, blue: 1.00)) {
                if !GameCenterManager.shared.isAuthenticated { GameCenterManager.shared.authenticate() }
                showDuelLobby = true
            }

            // Skins
            Button { showCustomize = true } label: {
                tabBarLabel(icon: "paintbrush.pointed.fill", label: "Skins",
                            activeColor: Color(red: 1.00, green: 0.58, blue: 0.88),
                            active: false)
                    .overlay(alignment: .topTrailing) {
                        if cosmeticState.hasUnseenUnlock {
                            Circle().fill(Color(red: 1, green: 0.25, blue: 0.35))
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }
                    }
            }
            .frame(maxWidth: .infinity)

            // Arcade
            Button { if modesUnlocked { showModes = true } } label: {
                tabBarLabel(
                    icon: modesUnlocked ? "gamecontroller.fill" : "lock.fill",
                    label: "Arcade",
                    activeColor: modesUnlocked
                        ? Color(red: 0.78, green: 0.55, blue: 1.00)
                        : Color.white.opacity(0.22),
                    active: false
                )
            }
            .frame(maxWidth: .infinity)
            .disabled(!modesUnlocked)
        }
        .padding(.top, 12)
        .padding(.bottom, 28)   // home indicator clearance
        .background(
            ZStack {
                // Frosted glass effect
                Color(red: 0.06, green: 0.03, blue: 0.18).opacity(0.92)
                // Subtle top border
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 0.5)
                    Spacer()
                }
            }
        )
    }

    private func tabBarItem(icon: String, label: String, activeColor: Color, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tabBarLabel(icon: icon, label: label, activeColor: activeColor, active: active)
        }
        .frame(maxWidth: .infinity)
    }

    private func tabBarLabel(icon: String, label: String, activeColor: Color, active: Bool = false) -> some View {
        VStack(spacing: 5) {
            ZStack {
                // Active pill highlight
                if active {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(activeColor.opacity(0.18))
                        .frame(width: 44, height: 30)
                }
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(active ? activeColor : .white.opacity(0.38))
                    .shadow(color: active ? activeColor.opacity(0.60) : .clear, radius: 8)
            }
            .frame(height: 30)
            Text(label)
                .font(.system(size: 10, design: .rounded).weight(.semibold))
                .foregroundColor(active ? activeColor : .white.opacity(0.38))
        }
    }

    private func resetProgress() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: "cq_wins")
        ud.removeObject(forKey: "cq_highScore")
        ud.removeObject(forKey: "cq_bestLevel")
        ud.removeObject(forKey: "cq_ftue_done")
        ud.removeObject(forKey: "cq_bestSurvival")
        ud.removeObject(forKey: "cq_prestige")
        ud.removeObject(forKey: "cq_player_name")
        ScoreStore.shared.clear()
        savedHighScore = 0
        savedBestLevel = 1
        savedBestSurvival = 0
        savedPrestige = 0
        modesUnlocked = false
        playerName = ""
    }
}

// MARK: - Top Leaderboard Entry

private struct TopEntry: Decodable {
    let playerName: String
    let score: Int
    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case score
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cq_music_enabled")   private var musicEnabled   = true
    @AppStorage("cq_sfx_enabled")     private var sfxEnabled     = true
    @AppStorage("cq_haptics_enabled") private var hapticsEnabled = true

    @State private var notificationsOn     = false
    @State private var showResetConfirm    = false
    @State private var isRestoringPurchases = false
    @State private var restoreMessage: String? = nil

    private let privacyPolicyURL = URL(string: "https://minwang.github.io/cup-queen/privacy")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.10, green: 0.03, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(.title2))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    // AUDIO
                    SettingsSection(title: "AUDIO", icon: "music.note") {
                        SettingsToggleRow(
                            icon: "music.note",
                            iconColor: Color(red: 0.55, green: 0.30, blue: 1.0),
                            label: "Music",
                            isOn: $musicEnabled
                        )
                        .onChange(of: musicEnabled) { val in
                            if val { SoundManager.shared.startHomeAmbient() }
                            else   { SoundManager.shared.stopAmbient() }
                        }
                        SettingsDivider()
                        SettingsToggleRow(
                            icon: "speaker.wave.2.fill",
                            iconColor: Color(red: 0.30, green: 0.65, blue: 1.0),
                            label: "Sound Effects",
                            isOn: $sfxEnabled
                        )
                    }

                    // GAMEPLAY
                    SettingsSection(title: "GAMEPLAY", icon: "gamecontroller") {
                        SettingsToggleRow(
                            icon: "iphone.radiowaves.left.and.right",
                            iconColor: Color(red: 1.0, green: 0.55, blue: 0.15),
                            label: "Haptics",
                            isOn: $hapticsEnabled
                        )
                        SettingsDivider()
                        SettingsToggleRow(
                            icon: "bell.badge.fill",
                            iconColor: Color(red: 1.0, green: 0.22, blue: 0.36),
                            label: "Daily Reminder",
                            isOn: $notificationsOn
                        )
                        .onChange(of: notificationsOn) { val in
                            if val {
                                Task {
                                    let granted = (try? await UNUserNotificationCenter.current()
                                        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                                    if granted {
                                        StreakManager.shared.scheduleReminder()
                                    } else {
                                        await MainActor.run { notificationsOn = false }
                                    }
                                }
                            } else {
                                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                            }
                        }
                    }

                    // ACCOUNT
                    SettingsSection(title: "ACCOUNT", icon: "person.crop.circle") {
                        Button {
                            isRestoringPurchases = true
                            Task {
                                await PurchaseManager.shared.restorePurchases()
                                await MainActor.run {
                                    isRestoringPurchases = false
                                    restoreMessage = "Purchases restored!"
                                }
                            }
                        } label: {
                            SettingsActionRow(
                                icon: "arrow.clockwise.circle.fill",
                                iconColor: Color(red: 0.20, green: 0.78, blue: 0.55),
                                label: isRestoringPurchases ? "Restoring…" : "Restore Purchases"
                            )
                        }
                        .disabled(isRestoringPurchases)
                    }

                    // SUPPORT
                    SettingsSection(title: "SUPPORT", icon: "star") {
                        Button {
                            if let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene }).first {
                                SKStoreReviewController.requestReview(in: scene)
                            }
                        } label: {
                            SettingsActionRow(
                                icon: "star.fill",
                                iconColor: Color(red: 1.0, green: 0.80, blue: 0.10),
                                label: "Rate Cup Queen"
                            )
                        }
                        SettingsDivider()
                        Link(destination: privacyPolicyURL) {
                            SettingsActionRow(
                                icon: "hand.raised.fill",
                                iconColor: Color(red: 0.50, green: 0.70, blue: 1.0),
                                label: "Privacy Policy"
                            )
                        }
                        SettingsDivider()
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 17))
                                .foregroundColor(.white.opacity(0.35))
                                .frame(width: 30)
                            Text("Version")
                                .font(.system(.callout, design: .rounded))
                                .foregroundColor(.white.opacity(0.70))
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                .font(.system(.callout, design: .rounded))
                                .foregroundColor(.white.opacity(0.40))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    // DANGER ZONE
                    SettingsSection(title: "DANGER ZONE", icon: "exclamationmark.triangle", accentColor: Color.red.opacity(0.70)) {
                        Button { showResetConfirm = true } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(.red.opacity(0.80))
                                    .frame(width: 30)
                                Text("Start New Game")
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundColor(.red.opacity(0.85))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red.opacity(0.40))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { checkNotificationStatus() }
        .alert("Start New Game?", isPresented: $showResetConfirm) {
            Button("Start Over", role: .destructive) { onReset(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your level, score, and all wins. You'll start fresh from Level 1.")
        }
        .alert("Purchases Restored", isPresented: .init(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsOn = settings.authorizationStatus == .authorized
            }
        }
    }
}

// MARK: - Settings Sub-Components

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var accentColor: Color = Color(red: 1, green: 0.80, blue: 0.22).opacity(0.75)
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .tracking(1.5)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(iconColor)
                    .frame(width: 30)
                Text(label)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
            }
        }
        .tint(Color(red: 0.55, green: 0.30, blue: 1.0))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let iconColor: Color
    let label: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(iconColor)
                .frame(width: 30)
            Text(label)
                .font(.system(.callout, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

// MARK: - Jester Mascot (emoji-based — Apple's renderer beats any SwiftUI shapes)

private struct JesterMascotView: View {
    let glowPulse: Bool
    let compact: Bool

    var body: some View {
        let size: CGFloat = compact ? 52 : 68

        ZStack {
            // Stage spotlight glow behind the character
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.85, blue: 0.20)
                        .opacity(glowPulse ? 0.32 : 0.16), Color.clear],
                    center: .center, startRadius: 4, endRadius: size * 0.9
                ))
                .frame(width: size * 2.0, height: size * 2.0)

            // Clown emoji — Apple's renderer, always looks polished
            Text("🤡")
                .font(.system(size: size))
                .shadow(color: Color.black.opacity(0.45), radius: 8, y: 4)
        }
    }
}

// MARK: - Preview Cup

struct PreviewCupView: View {
    let lit: Bool
    var theme: CupTheme = .classicRed
    var width: CGFloat = 74
    var height: CGFloat = 92

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                drawCup(ctx: ctx, size: size)
            }
            .frame(width: width, height: height)

            // Shine strip on lit cup
            if lit {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 10, height: 52)
                    .offset(x: -12, y: -4)
            }
        }
        .shadow(
            color: lit ? Color.yellow.opacity(0.60) : Color.black.opacity(0.55),
            radius: lit ? 18 : 6, y: 4
        )
    }

    private func drawCup(ctx: GraphicsContext, size: CGSize) {
        let w    = size.width
        let h    = size.height
        let topW = w * 0.55
        let topX = (w - topW) / 2
        let gold = Color(red: 0.95, green: 0.80, blue: 0.22)

        // Body (trapezoid)
        var body = Path()
        body.move(to:    CGPoint(x: topX + 2,        y: 10))
        body.addLine(to: CGPoint(x: topX + topW - 2, y: 10))
        body.addLine(to: CGPoint(x: w - 2,            y: h - 10))
        body.addLine(to: CGPoint(x: 2,                y: h - 10))
        body.closeSubpath()

        let topColor = lit ? theme.litTop : theme.unlitTop
        let botColor = lit ? theme.litBot : theme.unlitBot
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [topColor, botColor]),
            startPoint: CGPoint(x: w * 0.5, y: 0),
            endPoint:   CGPoint(x: w * 0.5, y: h)
        ))

        // Top rim
        var topRim = Path()
        topRim.addRoundedRect(
            in: CGRect(x: topX - 2, y: 2, width: topW + 4, height: 10),
            cornerSize: CGSize(width: 3, height: 3)
        )
        ctx.fill(topRim, with: .color(gold))

        // Bottom rim / base
        var botRim = Path()
        botRim.addRoundedRect(
            in: CGRect(x: 0, y: h - 12, width: w, height: 12),
            cornerSize: CGSize(width: 4, height: 4)
        )
        ctx.fill(botRim, with: .color(gold))
    }
}

// MARK: - Golden Ball

struct GoldenBallView: View {
    let diameter: CGFloat
    let glowPulse: Bool

    var body: some View {
        ZStack {
            // Outer glow halo — focused, not overly blurry
            Circle()
                .fill(Color(red: 1, green: 0.80, blue: 0.10).opacity(glowPulse ? 0.65 : 0.30))
                .frame(width: diameter * 2.0, height: diameter * 2.0)
                .blur(radius: 6)

            // Ball body — radial gold gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.98, blue: 0.72),
                            Color(red: 1.00, green: 0.83, blue: 0.18),
                            Color(red: 0.88, green: 0.58, blue: 0.04)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.27),
                        startRadius: 0,
                        endRadius: diameter * 0.65
                    )
                )
                .frame(width: diameter, height: diameter)

            // Specular highlight
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: diameter * 0.28, height: diameter * 0.28)
                .offset(x: -diameter * 0.18, y: -diameter * 0.20)
        }
    }
}

// MARK: - Home Progress Card

private struct HomeProgressCard: View {
    let level: Int
    let highScore: Int
    let wins: Int
    let prestigeCount: Int
    let playerName: String
    let bestSurvival: Int
    let streakCount: Int
    let rankBadge: String

    private var isMaxLevel: Bool { level >= 30 }
    /// wins / level → fills toward 100% as player approaches the next level threshold
    private var progressFraction: CGFloat {
        guard level > 0 else { return 0 }
        return min(CGFloat(wins) / CGFloat(level), 1.0)
    }
    private var nextLevelLabel: String {
        if isMaxLevel {
            return bestSurvival > 0 ? "Survived \(bestSurvival) in a row" : "MAX LEVEL"
        }
        let winsNeeded = max(0, level - wins)
        return winsNeeded == 1 ? "1 win to L\(level + 1)" : "\(winsNeeded) wins to L\(level + 1)"
    }

    var body: some View {
        let gold = Color(red: 1, green: 0.83, blue: 0.22)
        let goldLight = Color(red: 1, green: 0.92, blue: 0.55)
        let trimmed = playerName.trimmingCharacters(in: .whitespaces)

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Level pill (left) · pts (right)
            HStack(alignment: .center) {
                // Compact level pill — avoids "Level 11" word redundancy
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(gold)
                    Text(isMaxLevel ? "MAX" : "L\(level)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(goldLight)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(gold.opacity(0.12))
                    .overlay(Capsule().strokeBorder(gold.opacity(0.28), lineWidth: 1)))
                Spacer()
                HStack(spacing: 3) {
                    Text(highScore.formatted())
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(goldLight)
                    Text("pts")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(gold.opacity(0.75))
                }
            }

            // Row 2: Name · streak · rank
            HStack(spacing: 5) {
                if !trimmed.isEmpty {
                    Text(trimmed)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(goldLight.opacity(0.75))
                }
                if !trimmed.isEmpty && streakCount > 0 {
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 1, green: 0.55, blue: 0.10))
                        Text("\(streakCount)-day streak")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.72, blue: 0.10))
                    }
                }
                Spacer()
                // Rank as text pill (avoids emoji rendering bugs)
                Text(rankBadge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(goldLight)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(gold.opacity(0.16))
                        .overlay(Capsule().strokeBorder(gold.opacity(0.30), lineWidth: 1)))
            }

            // Row 3: Progress bar + label
            if !isMaxLevel {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10)).frame(height: 4)
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color(red: 1, green: 0.93, blue: 0.28),
                                             Color(red: 1, green: 0.65, blue: 0.05)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * max(0, min(progressFraction, 1.0)), height: 4)
                        }
                    }
                    .frame(height: 4)
                    Text(nextLevelLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [gold.opacity(0.50),
                                         Color.purple.opacity(0.20),
                                         gold.opacity(0.50)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Idle Cups View (returning player)

private struct IdleCupsView: View {
    @State private var leftY:   CGFloat = 0
    @State private var centreY: CGFloat = 0
    @State private var rightY:  CGFloat = 0
    // Entrance: cups start above screen, slam down on appear
    @State private var leftEntrance:   CGFloat = -320
    @State private var centreEntrance: CGFloat = -320
    @State private var rightEntrance:  CGFloat = -320
    @State private var glowPulse = false
    @State private var ballGlow  = false
    @State private var isActive  = false
    @State private var cupTheme: CupTheme = CosmeticState.shared.activeCup

    var body: some View {
        ZStack(alignment: .bottom) {
            // Focused warm spotlight under the table
            Ellipse()
                .fill(Color(red: 1, green: 0.78, blue: 0.12).opacity(glowPulse ? 0.28 : 0.12))
                .frame(width: 220, height: 32)
                .blur(radius: 10)
                .offset(y: 2)

            // Casino table platform
            ZStack {
                // Felt body — deep burgundy purple
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.30, green: 0.08, blue: 0.48),
                                 Color(red: 0.16, green: 0.04, blue: 0.26)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(maxWidth: .infinity, maxHeight: 18)
                // Gold top rail overlay
                VStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.90, blue: 0.35),
                                     Color(red: 0.85, green: 0.60, blue: 0.08)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(maxWidth: .infinity, maxHeight: 3)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 18)
            .shadow(color: Color(red: 1, green: 0.78, blue: 0.10).opacity(0.18), radius: 6, y: -2)
            .shadow(color: .black.opacity(0.80), radius: 12, y: 8)

            // Cups + ball — entrance offset combined with idle bob offset
            HStack(spacing: 22) {
                PreviewCupView(lit: false, theme: cupTheme, width: 88, height: 110)
                    .offset(y: leftY + leftEntrance)
                ZStack(alignment: .bottom) {
                    PreviewCupView(lit: true, theme: cupTheme, width: 88, height: 110)
                        .offset(y: centreY + centreEntrance)
                    GoldenBallView(diameter: 32, glowPulse: ballGlow)
                        .offset(y: centreY + centreEntrance + 22)
                }
                PreviewCupView(lit: false, theme: cupTheme, width: 88, height: 110)
                    .offset(y: rightY + rightEntrance)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .onAppear {
            cupTheme = CosmeticState.shared.activeCup

            // ── Entrance: cups slam down from above, staggered ──
            let slamSpring = Animation.interpolatingSpring(stiffness: 260, damping: 22)
            withAnimation(slamSpring.delay(0.05)) { leftEntrance   = 0 }
            withAnimation(slamSpring.delay(0.18)) { centreEntrance = 0 }
            withAnimation(slamSpring.delay(0.31)) { rightEntrance  = 0 }

            // ── Idle animations start after slam lands ──
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    ballGlow = true
                }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
                isActive = true
                startBobLoop()
            }
        }
        .onDisappear { isActive = false }
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
        guard isActive else { return }
        bob($leftY,   delay: 0.0)
        bob($centreY, delay: 0.6)
        bob($rightY,  delay: 1.2)
        // Restart loop every 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { startBobLoop() }
    }
}

// MARK: - Demo Shuffle View (new player)

private struct DemoShuffleView: View {
    // Cup X positions (slot-based): left=-108, centre=0, right=108, spacing accounts for cup width 88
    @State private var positions: [CGFloat] = [-108, 0, 108]   // index = cup identity
    @State private var ballOwner: Int = 1                        // cup index that holds ball
    @State private var ballVisible: Bool = true                  // false when hidden under cup
    @State private var cupLifted: [Bool] = [false, false, false]
    @State private var glowBurst: Bool = false
    @State private var ballGlow:  Bool = false
    @State private var isActive:  Bool = false
    @State private var cupTheme: CupTheme = CosmeticState.shared.activeCup

    // Fixed shuffle pairs (slot indices in positions array — not cup identity)
    // Centre↔Right, Left↔Centre, Centre↔Right, Left↔Centre
    private let shufflePairs: [(Int, Int)] = [(1,2),(0,1),(1,2),(0,1)]

    var body: some View {
        GeometryReader { geo in
        let halfWidth = geo.size.width / 2
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
                        PreviewCupView(lit: cup == ballOwner && ballVisible, theme: cupTheme)
                            .frame(width: 88, height: 108)
                            .offset(y: cupLifted[cup] ? -34 : 0)

                        // Ball under lifted cup — only during reveal (cup lifted + ballVisible)
                        if cup == ballOwner {
                            GoldenBallView(diameter: 30, glowPulse: ballGlow)
                                .opacity(ballVisible && cupLifted[cup] ? 1 : 0)
                                .offset(y: 22)
                        }
                    }
                    .position(x: positions[cup] + halfWidth, y: 60)
                }

                // Ball on table — before cup covers it (step 1); hidden during shuffle/reveal
                GoldenBallView(diameter: 30, glowPulse: ballGlow)
                    .opacity(ballVisible && !cupLifted[ballOwner] ? 1 : 0)
                    .position(x: positions[ballOwner] + halfWidth, y: 95)
            }
            .frame(height: 120)
            .padding(.bottom, 14)
        }
        .onAppear {
            isActive = true
            cupTheme = CosmeticState.shared.activeCup
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                ballGlow = true
            }
            runDemoLoop()
        }
        .onDisappear { isActive = false }
        } // GeometryReader
    }

    private func runDemoLoop() {
        guard isActive else { return }
        // Reset
        positions  = [-108, 0, 108]
        cupLifted  = [false, false, false]
        ballOwner  = 1
        ballVisible = true
        glowBurst   = false

        var t = 0.0

        // Step 1: Ball visible (0.8s hold) — already set above
        t += 0.8

        // Step 2: Cover ball (centre cup lowers — hides ball)
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
