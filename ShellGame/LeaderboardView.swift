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
                    Image(systemName: "chevron.left").opacity(0)   // balance
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
                                    Divider()
                                        .background(Color.white.opacity(0.08))
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
            Text(rankText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 32, alignment: .center)

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
