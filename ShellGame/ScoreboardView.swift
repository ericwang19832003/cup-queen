// ScoreboardView.swift
// Full-screen session results + all-time leaderboard. Shown after each session.
// Casino visual theme matching ContentView / GameView.

import SwiftUI

struct ScoreboardView: View {
    let sessionScore: Int
    let sessionLevel: Int
    let sessionSurvival: Int
    let sessionEntryID: UUID?
    let onHome: () -> Void

    @State private var entries: [ScoreEntry] = []

    // 1-based rank of sessionScore in the saved list
    private var sessionRank: Int {
        entries.filter { $0.score > sessionScore }.count + 1
    }

    var body: some View {
        ZStack {
            casinoBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    headerSection
                    Spacer().frame(height: 22)
                    sessionCard
                    Spacer().frame(height: 18)
                    leaderboardCard
                    Spacer().frame(height: 28)
                    homeButton
                    Spacer().frame(height: 44)
                }
                .padding(.horizontal, 22)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { entries = ScoreStore.shared.loadAll() }
    }

    // MARK: - Background

    private var casinoBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.02, blue: 0.18),
                Color(red: 0.12, green: 0.04, blue: 0.26),
                Color(red: 0.05, green: 0.02, blue: 0.18)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.93, blue: 0.38),
                                 Color(red: 1, green: 0.68, blue: 0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color.yellow.opacity(0.85), radius: 14)
            Text("SESSION RESULTS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.80))
                .tracking(5)
        }
    }

    // MARK: - Session Card (score + rank)

    private var sessionCard: some View {
        VStack(spacing: 14) {
            // Big score
            Text("\(sessionScore)")
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.00, green: 0.93, blue: 0.38),
                                 Color(red: 1.00, green: 0.68, blue: 0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.yellow.opacity(0.50), radius: 10)

            Text("PTS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.35))
                .tracking(3)
                .offset(y: -10)

            // Rank badge
            rankBadge

            // Level + survival pills
            HStack(spacing: 8) {
                statPill(text: "Level \(sessionLevel)",
                         color: Color(red: 0.55, green: 0.20, blue: 0.85))
                if sessionSurvival > 0 {
                    statPill(text: "Survived \(sessionSurvival)",
                             color: Color(red: 0.20, green: 0.80, blue: 0.42))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.70),
                                         Color.purple.opacity(0.35)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }

    private var rankBadge: some View {
        let total = entries.count
        let rank  = sessionRank
        let (icon, label, badgeColor): (String, String, Color) = {
            switch rank {
            case 1: return ("🥇", "#1 All Time!", Color(red: 1.00, green: 0.80, blue: 0.10))
            case 2: return ("🥈", "#2 All Time",  Color(red: 0.78, green: 0.78, blue: 0.82))
            case 3: return ("🥉", "#3 All Time",  Color(red: 0.82, green: 0.52, blue: 0.25))
            default: return ("🎯", "#\(rank) of \(total)", Color.white.opacity(0.65))
            }
        }()
        return HStack(spacing: 6) {
            Text(icon).font(.system(size: 15))
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.13))
                .overlay(Capsule().strokeBorder(badgeColor.opacity(0.30), lineWidth: 1))
        )
    }

    private func statPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: - Leaderboard Card

    private var leaderboardCard: some View {
        let top = Array(entries.prefix(10))
        return VStack(spacing: 0) {
            // Section header
            HStack {
                Text("ALL-TIME TOP \(min(entries.count, 10))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
                    .tracking(3)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Rows
            VStack(spacing: 5) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, entry in
                    scoreRow(rank: index + 1, entry: entry)
                }
            }
        }
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func scoreRow(rank: Int, entry: ScoreEntry) -> some View {
        let isCurrent = entry.id == sessionEntryID
        return HStack(spacing: 10) {
            // Rank
            rankLabel(rank: rank)
                .frame(width: 30, alignment: .center)

            // Score
            Text("\(entry.score)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(isCurrent
                    ? Color(red: 1, green: 0.90, blue: 0.30)
                    : Color.white.opacity(0.88))
                .frame(minWidth: 52, alignment: .leading)

            // Level
            Text("L\(entry.level)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.78, green: 0.60, blue: 1.00))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(red: 0.45, green: 0.12, blue: 0.75).opacity(0.28)))

            // Survival (L7 only)
            if entry.survivalCount > 0 {
                Text("×\(entry.survivalCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.28, green: 0.88, blue: 0.48))
            }

            Spacer()

            // Date
            Text(relativeDate(entry.date))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.30))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.yellow.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isCurrent ? Color.yellow.opacity(0.38) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func rankLabel(rank: Int) -> some View {
        switch rank {
        case 1:  Text("🥇").font(.system(size: 17))
        case 2:  Text("🥈").font(.system(size: 17))
        case 3:  Text("🥉").font(.system(size: 17))
        default:
            Text("#\(rank)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.38))
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Home Button

    private var homeButton: some View {
        Button(action: onHome) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Home")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
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
            .shadow(color: Color(red: 1, green: 0.75, blue: 0.10).opacity(0.65), radius: 18, y: 4)
        }
    }
}
