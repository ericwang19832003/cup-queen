// iCloudConflictView.swift
// Sheet shown when iCloud and local game progress diverge.
// Player picks one source; all 9 keys are applied from that source atomically.

import SwiftUI

struct iCloudConflictView: View {
    let localSnapshot:  [String: Any]
    let remoteSnapshot: [String: Any]
    let onKeepLocal:  () -> Void
    let onUseRemote:  () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.12, green: 0.04, blue: 0.26)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(Color(red: 0.30, green: 0.75, blue: 1.00))
                    .shadow(color: Color(red: 0.30, green: 0.75, blue: 1.00).opacity(0.65), radius: 12)

                Text("Progress Conflict")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Your progress differs between this device and iCloud.\nChoose which to keep.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    snapshotColumn(title: "THIS DEVICE",
                                   snapshot: localSnapshot,
                                   accentColor: Color(red: 1, green: 0.72, blue: 0.20))
                    snapshotColumn(title: "ICLOUD",
                                   snapshot: remoteSnapshot,
                                   accentColor: Color(red: 0.30, green: 0.75, blue: 1.00))
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button(action: onKeepLocal) {
                        Text("Keep This Device")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color(red: 1, green: 0.85, blue: 0.20),
                                         Color(red: 1, green: 0.65, blue: 0.05)],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    Button(action: onUseRemote) {
                        Text("Use iCloud")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color(red: 0.30, green: 0.75, blue: 1.00),
                                         Color(red: 0.15, green: 0.55, blue: 0.90)],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func snapshotColumn(title: String,
                                 snapshot: [String: Any],
                                 accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .tracking(2)

            ForEach(displayRows(from: snapshot), id: \.label) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    Text(row.value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(accentColor.opacity(0.30), lineWidth: 1))
        )
    }

    private struct DisplayRow {
        let label: String
        let value: String
    }

    private func displayRows(from snapshot: [String: Any]) -> [DisplayRow] {
        let wins    = snapshot["cq_wins"]          as? Int ?? 0
        let high    = snapshot["cq_highScore"]     as? Int ?? 0
        let surv    = snapshot["cq_bestSurvival"]  as? Int ?? 0
        let gaunt   = snapshot["cq_best_gauntlet"] as? Int ?? 0
        let prest   = snapshot["cq_prestige"]      as? Int ?? 0
        let streak  = snapshot["cq_daily_streak"]  as? Int ?? 0
        return [
            DisplayRow(label: "Level",         value: "Level \(min(wins + 1, 7))"),
            DisplayRow(label: "High Score",    value: "\(high) pts"),
            DisplayRow(label: "Best Survival", value: surv  > 0 ? "×\(surv)"       : "—"),
            DisplayRow(label: "Best Gauntlet", value: gaunt > 0 ? "\(gaunt) pts"   : "—"),
            DisplayRow(label: "Prestige",      value: prest > 0 ? "👑 ×\(prest)"   : "—"),
            DisplayRow(label: "Daily Streak",  value: streak > 0 ? "🔥 \(streak)d" : "—"),
        ]
    }
}
