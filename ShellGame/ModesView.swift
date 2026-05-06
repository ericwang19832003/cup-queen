// ModesView.swift
// fullScreenCover shown from ContentView when player taps "Modes".
// Three cards: Gauntlet, Daily Challenge, Prestige.

import SwiftUI

struct ModesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showGauntlet = false
    @State private var showDaily    = false
    @State private var showPrestigeAlert = false

    // Stats read from UserDefaults
    @State private var bestGauntlet: Int  = 0
    @State private var prestigeCount: Int = 0
    @State private var dailyStreak: Int   = 0
    @State private var dailyAttempted: Bool = false
    @State private var currentLevel: Int  = 1

    var body: some View {
        ZStack {
            casinoBackground
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                header
                Spacer().frame(height: 24)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        gauntletCard
                        dailyCard
                        prestigeCard
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { loadStats() }
        .fullScreenCover(isPresented: $showGauntlet, onDismiss: loadStats) {
            GauntletView()
        }
        .fullScreenCover(isPresented: $showDaily, onDismiss: loadStats) {
            DailyChallengeView()
        }
    }

    private func loadStats() {
        bestGauntlet   = UserDefaults.standard.integer(forKey: "cq_best_gauntlet")
        prestigeCount  = UserDefaults.standard.integer(forKey: "cq_prestige")
        dailyStreak    = UserDefaults.standard.integer(forKey: "cq_daily_streak")
        dailyAttempted = GameState().isDailyAttempted
        currentLevel   = min(UserDefaults.standard.integer(forKey: "cq_wins") + 1, 30)
    }

    // MARK: - Background
    private var casinoBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                     Color(red: 0.12, green: 0.04, blue: 0.26),
                     Color(red: 0.05, green: 0.02, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text("MODES")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.80))
                .tracking(5)
            Spacer()
            Color.clear.frame(width: 24)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Gauntlet Card
    private var gauntletCard: some View {
        modeCard(
            icon: "flame.fill",
            iconColor: Color(red: 1, green: 0.45, blue: 0.15),
            title: "Gauntlet",
            subtitle: "One life. L1 → L7. No retries.",
            stat: bestGauntlet > 0 ? "Best: \(bestGauntlet) pts" : "Not attempted",
            ctaLabel: "Start Run",
            ctaAction: { showGauntlet = true },
            accentColor: Color(red: 1, green: 0.45, blue: 0.15)
        )
    }

    // MARK: - Daily Card
    private var dailyCard: some View {
        modeCard(
            icon: "calendar",
            iconColor: Color(red: 0.30, green: 0.75, blue: 1.00),
            title: "Daily Challenge",
            subtitle: dailyAttempted ? "Come back tomorrow!" : "Today's puzzle awaits.",
            stat: dailyStreak > 0 ? "🔥 \(dailyStreak)-day streak" : "No streak yet",
            ctaLabel: dailyAttempted ? "Attempted" : "Play Today",
            ctaAction: dailyAttempted ? nil : { showDaily = true },
            accentColor: Color(red: 0.30, green: 0.75, blue: 1.00)
        )
    }

    // MARK: - Prestige Card
    private var prestigeCard: some View {
        let canPrestige = currentLevel >= 30
        return modeCard(
            icon: "crown.fill",
            iconColor: Color(red: 1, green: 0.80, blue: 0.22),
            title: "Prestige",
            subtitle: canPrestige
                ? "Reset to L1. Keep your records. Earn a crown."
                : "Reach Level 30 to prestige.",
            stat: prestigeCount > 0 ? "👑 × \(prestigeCount)" : "Not yet prestiged",
            ctaLabel: canPrestige ? "Prestige Now" : "Not Available",
            ctaAction: canPrestige ? { showPrestigeAlert = true } : nil,
            accentColor: Color(red: 1, green: 0.80, blue: 0.22)
        )
        .alert("Prestige?", isPresented: $showPrestigeAlert) {
            Button("Prestige", role: .destructive) {
                let state = GameState()
                state.prestige()
                loadStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reset to Level 1 and earn 👑 Prestige \(prestigeCount + 1). Your high score, survival record, and gauntlet best are kept.")
        }
    }

    // MARK: - Reusable Card Builder
    private func modeCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        stat: String,
        ctaLabel: String,
        ctaAction: (() -> Void)?,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(iconColor)
                    .shadow(color: iconColor.opacity(0.60), radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Text(stat)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor.opacity(0.80))
            }
            if let action = ctaAction {
                Button(action: action) {
                    Text(ctaLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
            } else {
                Text(ctaLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
