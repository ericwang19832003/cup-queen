// ShareCardView.swift
// Renders a shareable stat card via ImageRenderer.
// Usage: let image = ShareCardView.render(stats: ...)

import SwiftUI

struct ShareStats {
    let level: Int
    let score: Int
    let survival: Int          // 0 if not a survival session
    let streakCount: Int
    let playerName: String
    let cupTheme: CupTheme
}

struct ShareCardView: View {
    let stats: ShareStats

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))
                Text("CUP QUEEN")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .kerning(3)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.15))

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                if stats.survival > 0 {
                    statRow(icon: "flame.fill",
                            label: "Survived \(stats.survival) rounds",
                            color: Color(red: 1, green: 0.50, blue: 0.10))
                }
                statRow(icon: "star.fill",
                        label: "Score: \(stats.score.formatted())",
                        color: Color(red: 1, green: 0.85, blue: 0.28))
                statRow(icon: "crown.fill",
                        label: "Level \(stats.level)",
                        color: Color(red: 0.78, green: 0.50, blue: 1.00))
                if stats.streakCount > 1 {
                    statRow(icon: "flame",
                            label: "\(stats.streakCount)-day streak 🔥",
                            color: Color(red: 1, green: 0.68, blue: 0.05))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.15))

            // CTA
            VStack(spacing: 2) {
                Text("Can you beat me?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.60))
                Text("apps.apple.com/app/id6615093313")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28).opacity(0.80))
            }
            .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.06, green: 0.02, blue: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [stats.cupTheme.litTop.opacity(0.70),
                                         Color.purple.opacity(0.40),
                                         stats.cupTheme.litTop.opacity(0.70)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 2
                        )
                )
        )
    }

    private func statRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    /// Renders this view to a UIImage for sharing via UIActivityViewController.
    @MainActor
    static func render(stats: ShareStats) -> UIImage? {
        let view = ShareCardView(stats: stats)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
