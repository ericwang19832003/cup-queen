// ContentView.swift
// CUP QUEEN — Las Vegas Arcade Shell Game
// Home screen: gameplay-first layout. Cups are the hero. App Store safe.
//
// Extension points:
//   GAMECENTER : Leaderboard button → GKGameCenterViewController
//   SKINS      : Skin picker sheet
//   ANALYTICS  : Track open → "Play Now" tap funnel

import SwiftUI

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
                starField
                cupSpotlight

                VStack(spacing: 0) {
                    Spacer().frame(height: 58)   // below status bar / Dynamic Island

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
                            bestSurvival: savedBestSurvival,
                            streakCount: savedStreakCount,
                            rankBadge: rankBadge
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

    private var continueButton: some View {
        Button {
            startFreshSelected = false
            showNameEntry = true
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

    private var freshStartLink: some View {
        Button {
            startFreshSelected = true
            showNameEntry = true
        } label: {
            Text("Fresh Start")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.40))
                .underline()
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

            // Style
            Button { showCustomize = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Style")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(red: 1, green: 0.60, blue: 0.80))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.35, green: 0.05, blue: 0.20).opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(red: 1, green: 0.60, blue: 0.80).opacity(0.40), lineWidth: 1.5))
                )
                .overlay(alignment: .topTrailing) {
                    if cosmeticState.hasUnseenUnlock {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: -6, y: 6)
                    }
                }
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

struct PreviewCupView: View {
    let lit: Bool
    var theme: CupTheme = .classicRed

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
    private var progressFraction: CGFloat {
        CGFloat(wins - (level - 1)) / 1.0
    }
    private var nextLevelLabel: String {
        if isMaxLevel {
            return bestSurvival > 0 ? "Survived \(bestSurvival) in a row" : "MAX LEVEL"
        }
        let winsNeeded = level - wins
        let w = max(0, winsNeeded)
        return w == 1 ? "1 win to L\(level + 1)" : "\(w) wins to L\(level + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: level + score
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
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
                                .frame(width: geo.size.width * max(0, min(progressFraction, 1.0)), height: 6)
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

            // Streak + rank row
            HStack(spacing: 8) {
                if streakCount > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text("\(streakCount) day streak")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 1, green: 0.68, blue: 0.05))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(red: 1, green: 0.68, blue: 0.05).opacity(0.12))
                    .clipShape(Capsule())
                }
                Text(rankBadge)
                    .font(.system(size: 14))
                Spacer()
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

// MARK: - Idle Cups View (returning player)

private struct IdleCupsView: View {
    @State private var leftY:   CGFloat = 0
    @State private var centreY: CGFloat = 0
    @State private var rightY:  CGFloat = 0
    @State private var glowPulse = false
    @State private var ballGlow  = false
    @State private var isActive  = false
    @State private var cupTheme: CupTheme = CosmeticState.shared.activeCup

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
                PreviewCupView(lit: false, theme: cupTheme)
                    .offset(y: leftY)
                ZStack(alignment: .bottom) {
                    PreviewCupView(lit: true, theme: cupTheme)
                        .offset(y: centreY)
                    GoldenBallView(diameter: 26, glowPulse: ballGlow)
                        .offset(y: centreY + 18)
                }
                PreviewCupView(lit: false, theme: cupTheme)
                    .offset(y: rightY)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .onAppear {
            cupTheme = CosmeticState.shared.activeCup
            // Ball glow
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                ballGlow = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            // Staggered bob: left → centre → right, 3s total loop
            isActive = true
            startBobLoop()
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
