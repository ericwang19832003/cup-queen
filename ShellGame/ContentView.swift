// ContentView.swift
// CUP QUEEN — Las Vegas Arcade Shell Game
// Home screen: gameplay-first layout. Cups are the hero. App Store safe.
//
// Extension points:
//   GAMECENTER : Leaderboard button → GKGameCenterViewController
//   SKINS      : Skin picker sheet
//   ANALYTICS  : Track open → "Play Now" tap funnel

import SwiftUI

// MARK: - Pre-computed star data (deterministic; avoids per-render random)

private func makeStars() -> [StarData] {
    var out: [StarData] = []
    for i in 0..<28 {
        let x: CGFloat       = CGFloat(i) * 14.2 + 8
        let y: CGFloat       = CGFloat((i * 41 + 17) % 860)
        let size: CGFloat    = CGFloat(1 + (i % 4))
        let opacity: Double  = 0.25 + Double(i % 6) * 0.09
        let duration: Double = 1.4  + Double(i % 7) * 0.18
        let delay: Double    = Double(i % 9) * 0.22
        out.append(StarData(id: i, x: x, y: y, size: size,
                            opacity: opacity, duration: duration, delay: delay))
    }
    return out
}

private let backgroundStars: [StarData] = makeStars()

private struct StarData: Identifiable {
    let id: Int
    let x, y, size: CGFloat
    let opacity, duration, delay: Double
}

// MARK: - ContentView

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var animateStars    = false
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

    // Persisted best stats — read fresh each time view appears
    @State private var savedHighScore: Int = 0
    @State private var savedBestLevel: Int = 1
    @State private var savedBestSurvival: Int = 0
    @State private var savedPrestige: Int  = 0
    @State private var modesUnlocked: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                casinoBackground
                starField
                cupSpotlight

                VStack(spacing: 0) {
                    Spacer().frame(height: 58)   // below status bar / Dynamic Island

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
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 22)
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.top, 62)
                        .padding(.leading, 22)
                }
            }
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
                PlayerNameEntryView { startFresh in
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
                SoundManager.shared.startHomeAmbient()   // Feature 1: home screen jazz
                checkiCloudConflict()
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
        animateStars = true
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glowPulse = true }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { ctaPulse  = true }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { ballGlow  = true }
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

    // MARK: - Background

    private var casinoBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.02, blue: 0.18),
                Color(red: 0.14, green: 0.04, blue: 0.28),
                Color(red: 0.06, green: 0.02, blue: 0.18)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var starField: some View {
        GeometryReader { geo in
            ForEach(backgroundStars) { star in
                Circle()
                    .fill(Color.yellow.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: star.x, y: star.y * (geo.size.height / 860))
                    .scaleEffect(animateStars ? 1.5 : 0.7)
                    .animation(
                        .easeInOut(duration: star.duration)
                            .repeatForever(autoreverses: true)
                            .delay(star.delay),
                        value: animateStars
                    )
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

    private var titleSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                Text("CUP QUEEN")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
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

                Text("FIND THE BALL")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.90))
                    .tracking(7)

                // Personalized welcome greeting with inline prestige crowns
                let trimmedName = playerName.trimmingCharacters(in: .whitespaces)
                if !trimmedName.isEmpty {
                    Text("Welcome back, \(trimmedName)\(savedPrestige > 0 ? " " + String(repeating: "👑", count: min(savedPrestige, 3)) : "")")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.85))
                        .kerning(1.5)
                }
            }
            .frame(maxWidth: .infinity)

            // Game Center leaderboard button
            if GameCenterManager.shared.isAuthenticated {
                Button {
                    showGameCenter = true
                } label: {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                        .shadow(color: Color.yellow.opacity(0.55), radius: 6)
                }
                .offset(x: 4, y: 2)
            }
        }
    }

    // MARK: - Challenge Badge

    private var challengeBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 1, green: 0.45, blue: 0.18))
            Text("Only 1% of players beat Level 7")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.62, blue: 0.22), Color(red: 1, green: 0.36, blue: 0.15)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
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

    // MARK: - Best Stats Row

    private var bestStatsRow: some View {
        let isMaxLevel = savedBestLevel >= 30
        return HStack(spacing: 12) {
            if isMaxLevel && savedBestSurvival > 0 {
                // L30 players: show survival streak instead of level
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                    Text("Survived \(savedBestSurvival)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                    Text("Level \(savedBestLevel)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
                }
            }
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 14)
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.80, blue: 0.22))
                Text("\(savedHighScore) pts")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1, green: 0.90, blue: 0.55))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(red: 1, green: 0.75, blue: 0.10).opacity(0.12))
                .overlay(Capsule().strokeBorder(
                    Color(red: 1, green: 0.80, blue: 0.22).opacity(0.35), lineWidth: 1
                ))
        )
    }

    // MARK: - Game Preview Section (HERO)

    private var gamePreviewSection: some View {
        VStack(spacing: 0) {
            // Magician host — upper body, tasteful, pointing toward cups
            HostCharacterView(glowPulse: glowPulse)
                .frame(height: 90)

            Spacer().frame(height: 6)

            // Cups + ball — the actual gameplay visual
            cupTableView
        }
        .padding(.top, 16)
        .padding(.bottom, 18)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.32),
                            Color(red: 0.10, green: 0.05, blue: 0.26).opacity(0.55)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.yellow.opacity(0.55),
                                    Color.purple.opacity(0.30),
                                    Color.yellow.opacity(0.55)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }

    /// Felt table with 3 cups and the golden ball visible under the centre cup.
    private var cupTableView: some View {
        ZStack(alignment: .bottom) {

            // Glow spotlight behind centre cup
            Ellipse()
                .fill(Color.yellow.opacity(glowPulse ? 0.24 : 0.11))
                .frame(width: 96, height: 32)
                .blur(radius: 12)
                .offset(y: -14)

            // Felt table strip
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.28, blue: 0.14),
                            Color(red: 0.05, green: 0.18, blue: 0.09)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .padding(.horizontal, 8)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 5)

            // Three cups
            HStack(spacing: 20) {
                PreviewCupView(lit: false)          // left
                centreWithBall                       // centre — ball visible
                PreviewCupView(lit: false)          // right
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)                   // sits on felt surface
        }
    }

    /// Centre cup with the golden ball sitting in front of it.
    private var centreWithBall: some View {
        ZStack(alignment: .bottom) {
            PreviewCupView(lit: true)

            GoldenBallView(diameter: 26, glowPulse: ballGlow)
                .offset(y: 18)   // rests on table surface, slightly below cup base
        }
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(colors: [.yellow, Color(red: 1, green: 0.72, blue: 0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
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

    // MARK: - Secondary Button Row

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
        .padding(.horizontal, 22)
    }

    private func resetProgress() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: "cq_wins")
        ud.removeObject(forKey: "cq_highScore")
        ud.removeObject(forKey: "cq_bestLevel")
        ud.removeObject(forKey: "cq_ftue_done")
        ud.removeObject(forKey: "cq_bestSurvival")
        ud.removeObject(forKey: "cq_prestige")
        ScoreStore.shared.clear()
        savedHighScore = 0
        savedBestLevel = 1
        savedBestSurvival = 0
        savedPrestige = 0
        modesUnlocked = false
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

// MARK: - Host Character (magic emblem)

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

            // Top hat emoji
            Text("🎩")
                .font(.system(size: 42))
                .offset(y: -2)
                .shadow(color: Color(red: 1, green: 0.80, blue: 0.10).opacity(0.70), radius: 12)

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
        }
        .compositingGroup()
    }
}

// MARK: - Preview Cup

private struct PreviewCupView: View {
    let lit: Bool

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                drawCup(ctx: ctx, size: size)
            }
            .frame(width: 74, height: 92)

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

        let topColor = lit ? Color(red: 0.82, green: 0.08, blue: 0.10) : Color(red: 0.48, green: 0.04, blue: 0.06)
        let botColor = lit ? Color(red: 1.00, green: 0.16, blue: 0.16) : Color(red: 0.72, green: 0.07, blue: 0.08)
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

private struct GoldenBallView: View {
    let diameter: CGFloat
    let glowPulse: Bool

    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(Color(red: 1, green: 0.80, blue: 0.10).opacity(glowPulse ? 0.60 : 0.28))
                .frame(width: diameter * 1.9, height: diameter * 1.9)
                .blur(radius: 7)

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
