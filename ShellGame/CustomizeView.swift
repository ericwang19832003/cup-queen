// CustomizeView.swift
// 3-tab cosmetics picker sheet. Shown from ContentView secondary row.

import SwiftUI
import StoreKit

struct CustomizeView: View {
    @StateObject private var cosmetics = CosmeticState.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var isPurchasing = false
    @State private var purchaseError: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $selectedTab) {
                    Text("Cups").tag(0)
                    Text("Ball").tag(1)
                    Text("Table").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        switch selectedTab {
                        case 0:
                            ForEach(CupTheme.all, id: \.id) { theme in
                                CupSkinCell(
                                    theme: theme,
                                    isActive: cosmetics.activeCup.id == theme.id,
                                    isUnlocked: cosmetics.unlockedCups.contains(theme.id),
                                    isPurchasing: isPurchasing,
                                    progress: cosmetics.progress(for: theme.id),
                                    onSelect: { cosmetics.selectCup(theme) },
                                    onPurchase: { purchase(productID: CosmeticState.purchasableCups[theme.id]) }
                                )
                            }
                        case 1:
                            ForEach(BallTheme.all, id: \.id) { theme in
                                BallSkinCell(
                                    theme: theme,
                                    isActive: cosmetics.activeBall.id == theme.id,
                                    isUnlocked: cosmetics.unlockedBalls.contains(theme.id),
                                    isPurchasing: isPurchasing,
                                    onSelect: { cosmetics.selectBall(theme) },
                                    onPurchase: { purchase(productID: CosmeticState.purchasableBalls[theme.id]) }
                                )
                            }
                        default:
                            ForEach(TableTheme.all, id: \.id) { theme in
                                TableSkinCell(
                                    theme: theme,
                                    isActive: cosmetics.activeTable.id == theme.id,
                                    isUnlocked: cosmetics.unlockedTables.contains(theme.id),
                                    isPurchasing: isPurchasing,
                                    onSelect: { cosmetics.selectTable(theme) },
                                    onPurchase: { purchase(productID: CosmeticState.purchasableTables[theme.id]) }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(red: 0.06, green: 0.02, blue: 0.18).ignoresSafeArea())
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))
                }
            }
            .alert("Purchase failed", isPresented: Binding(
                get: { purchaseError != nil },
                set: { if !$0 { purchaseError = nil } }
            )) {
                Button("OK") { purchaseError = nil }
            } message: {
                Text(purchaseError ?? "")
            }
            .onAppear {
                cosmetics.clearUnseenUnlock()
            }
        }
    }

    @MainActor
    private func purchase(productID: String?) {
        guard let pid = productID else { return }
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await PurchaseManager.shared.purchaseCosmetic(productID: pid)
            } catch {
                purchaseError = error.localizedDescription
            }
        }
    }
}

// MARK: - Cup Skin Cell

private struct CupSkinCell: View {
    let theme: CupTheme
    let isActive: Bool
    let isUnlocked: Bool
    let isPurchasing: Bool
    let progress: (current: Int, required: Int, label: String)?
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            PreviewCupView(lit: false, theme: theme)
                .frame(width: 60, height: 74)

            Text(theme.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            if isActive {
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))
            } else if isUnlocked {
                Button("Use", action: onSelect)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
            } else if CosmeticState.purchasableCups[theme.id] != nil {
                Button(isPurchasing ? "..." : "Buy", action: onPurchase)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.85, blue: 0.28))
                    .clipShape(Capsule())
                    .disabled(isPurchasing)
            } else if let prog = progress {
                VStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                    Text("\(prog.current) / \(prog.required)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                    Text(prog.label)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
            } else {
                // Milestone-only (no progress path)
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive
                      ? Color(red: 0.30, green: 0.15, blue: 0.60).opacity(0.40)
                      : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isActive
                                  ? Color.yellow.opacity(0.60)
                                  : Color.white.opacity(0.10), lineWidth: 1.5))
        )
    }
}

// MARK: - Ball Skin Cell

private struct BallSkinCell: View {
    let theme: BallTheme
    let isActive: Bool
    let isUnlocked: Bool
    let isPurchasing: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            GoldenBallView(diameter: 44, glowPulse: isActive)
                .padding(.top, 8)

            Text(theme.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            if isActive {
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))
            } else if isUnlocked {
                Button("Use", action: onSelect)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
            } else if CosmeticState.purchasableBalls[theme.id] != nil {
                Button(isPurchasing ? "..." : "Buy", action: onPurchase)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.85, blue: 0.28))
                    .clipShape(Capsule())
                    .disabled(isPurchasing)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? Color(red: 0.30, green: 0.15, blue: 0.60).opacity(0.40) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isActive ? Color.yellow.opacity(0.60) : Color.white.opacity(0.10), lineWidth: 1.5))
        )
    }
}

// MARK: - Table Skin Cell

private struct TableSkinCell: View {
    let theme: TableTheme
    let isActive: Bool
    let isUnlocked: Bool
    let isPurchasing: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Preview: felt strip sample
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [theme.topColor, theme.botColor],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 80, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.top, 8)

            Text(theme.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            if isActive {
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))
            } else if isUnlocked {
                Button("Use", action: onSelect)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
            } else if CosmeticState.purchasableTables[theme.id] != nil {
                Button(isPurchasing ? "..." : "Buy", action: onPurchase)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.85, blue: 0.28))
                    .clipShape(Capsule())
                    .disabled(isPurchasing)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? Color(red: 0.30, green: 0.15, blue: 0.60).opacity(0.40) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isActive ? Color.yellow.opacity(0.60) : Color.white.opacity(0.10), lineWidth: 1.5))
        )
    }
}
