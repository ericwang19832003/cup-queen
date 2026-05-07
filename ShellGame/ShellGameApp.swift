// ShellGameApp.swift
// Magic Cup — Shell Game MVP
//
// Extension points (commented for future sprints):
//   ANALYTICS : Replace stub with Firebase/Amplitude — see AppDelegate hook below
//   STOREKIT  : Add StoreKit 2 for "No Ads" / premium skin packs
//   ADS       : AdMob / AppLovin — inject banner after round result overlay
//   SKINS     : SkinManager.shared.loadSavedSkin() on launch
//   SOUNDS    : SoundManager.shared.configure() on launch, AVAudioSession setup
//   GAMECENTER: GKLocalPlayer.local.authenticateHandler for leaderboards

import SwiftUI
import UserNotifications

@main
struct ShellGameApp: App {

    init() {
        // TODO: ANALYTICS — FirebaseApp.configure()
        // TODO: SOUNDS    — SoundManager.shared.configure()
        // TODO: SKINS     — SkinManager.shared.loadSavedSkin()
        // TODO: ADMOB     — AdManager.shared.configure()  ← uncomment after adding SDK
        Task { await PurchaseManager.shared.checkExistingEntitlements() }
        GameCenterManager.shared.authenticate()
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted && StreakManager.shared.streakCount > 0 {
                StreakManager.shared.scheduleReminder()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AdManager
// ATT consent + AdMob interstitial/rewarded lifecycle.
//
// ACTIVATION CHECKLIST (before shipping):
//   1. Add Google-Mobile-Ads-SDK via SPM:
//      https://github.com/googleads/swift-package-manager-google-mobile-ads
//   2. Uncomment all "TODO: ADMOB" lines and remove the stub print() calls
//   3. Replace test Ad Unit IDs below with real IDs from AdMob dashboard
//   4. In Xcode → target → Info tab → add key:
//      NSUserTrackingUsageDescription = "We use this to show you relevant ads."

import AppTrackingTransparency
import UIKit

private enum AdUnitID {
    static let interstitial = "ca-app-pub-3940256099942544/4411468910"  // Google test ID — replace before shipping
    static let rewarded     = "ca-app-pub-3940256099942544/1712485313"  // Google test ID — replace before shipping
}

final class AdManager {

    static let shared = AdManager()
    private init() {
        adsRemoved = UserDefaults.standard.bool(forKey: "cq_ads_removed")
    }

    private(set) var adsRemoved: Bool = false

    // TODO: ADMOB — private var interstitial: GADInterstitialAd?
    // TODO: ADMOB — private var rewardedAd: GADRewardedAd?

    // MARK: - Setup

    func configure() {
        // TODO: ADMOB — GADMobileAds.sharedInstance().start(completionHandler: nil)
        // TODO: ADMOB — GADMobileAds.sharedInstance().requestConfiguration.maxAdContentRating = .general
    }

    // MARK: - Interstitial (3rd cumulative loss)

    @MainActor
    func requestATTThenShowInterstitial() async {
        guard !adsRemoved else { return }

        if #available(iOS 14, *) {
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
        }

        await loadAndShowInterstitial()
    }

    private func loadAndShowInterstitial() async {
        guard !adsRemoved, let rootVC = rootViewController() else { return }

        // TODO: ADMOB — replace with:
        // do {
        //     interstitial = try await GADInterstitialAd.load(
        //         withAdUnitID: AdUnitID.interstitial, request: GADRequest()
        //     )
        //     interstitial?.present(fromRootViewController: rootVC)
        // } catch { print("Interstitial load failed: \(error)") }

        print("AdManager [STUB]: interstitial would show here — rootVC: \(rootVC)")
    }

    // MARK: - Rewarded (hint feature)

    /// Shows a rewarded ad; on completion, awards one streak shield.
    @MainActor
    func showShieldRewardedAd() {
        showRewardedAd {
            StreakManager.shared.addShield()
        }
    }

    func preloadRewardedAd() {
        guard !adsRemoved else { return }
        // TODO: ADMOB —
        // GADRewardedAd.load(withAdUnitID: AdUnitID.rewarded, request: GADRequest()) { [weak self] ad, error in
        //     if let error { print("Rewarded load failed: \(error)"); return }
        //     self?.rewardedAd = ad
        // }
    }

    @MainActor
    func showRewardedAd(onRewarded: @escaping () -> Void) {
        if adsRemoved { onRewarded(); return }   // IAP users get hint free
        guard let rootVC = rootViewController() else { return }

        // TODO: ADMOB — replace with:
        // guard let rewardedAd else { return }
        // rewardedAd.present(fromRootViewController: rootVC, userDidEarnRewardHandler: onRewarded)

        print("AdManager [STUB]: rewarded ad would show here — rootVC: \(rootVC)")
        onRewarded()   // grant hint immediately while SDK is not yet integrated
    }

    // MARK: - IAP

    func markAdsRemoved() {
        adsRemoved = true
        UserDefaults.standard.set(true, forKey: "cq_ads_removed")
    }

    // MARK: - Helpers

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController
    }
}

// MARK: - PurchaseManager
// StoreKit 2 non-consumable IAP: "Remove Ads" ($1.99).
// Requires product ID registered in App Store Connect before testing on device.

import StoreKit

final class PurchaseManager {

    static let shared = PurchaseManager()
    private init() {
        transactionListener = listenForTransactions()
    }

    private enum ProductID {
        static let removeAds    = "com.shellgame.magiccup.removeads"
        static let cupGold      = "com.shellgame.magiccup.cosmetic.goldcup"
        static let cupMidnight  = "com.shellgame.magiccup.cosmetic.midnight"
        static let cupDiamond   = "com.shellgame.magiccup.cosmetic.diamond"
        static let ballCrystal  = "com.shellgame.magiccup.cosmetic.crystal"
        static let tableNeon    = "com.shellgame.magiccup.cosmetic.neonpurple"
        static let tableMidBlue = "com.shellgame.magiccup.cosmetic.midnightblue"
        static let starterPack  = "com.shellgame.magiccup.cosmetic.starterpack"
        static let shieldThree  = "com.shellgame.magiccup.streakshield3"

        static let all: [String] = [
            removeAds, cupGold, cupMidnight, cupDiamond,
            ballCrystal, tableNeon, tableMidBlue, starterPack, shieldThree
        ]
    }

    private var transactionListener: Task<Void, Never>?

    // MARK: - Products

    /// Fetches the Remove Ads product. Returns nil if not yet configured in ASC.
    func fetchProduct() async -> Product? {
        try? await Product.products(for: [ProductID.removeAds]).first
    }

    // MARK: - Purchase

    @MainActor
    func purchaseRemoveAds() async {
        guard let product = await fetchProduct() else {
            print("PurchaseManager: product not found — configure in App Store Connect")
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                AdManager.shared.markAdsRemoved()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("PurchaseManager: purchase error — \(error)")
        }
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("PurchaseManager: restore sync error — \(error)")
        }
        // currentEntitlements catches restored transactions automatically via listener
    }

    // MARK: - Entitlement check on launch

    func checkExistingEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            await transaction.finish()
            if transaction.productID == ProductID.removeAds {
                AdManager.shared.markAdsRemoved()
            }
            await MainActor.run { applyCosmetic(productID: transaction.productID) }
        }
    }

    // MARK: - Transaction listener (handles renewals, family sharing, refunds)

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await transaction.finish()
                if transaction.productID == ProductID.removeAds {
                    AdManager.shared.markAdsRemoved()
                }
                await MainActor.run { self.applyCosmetic(productID: transaction.productID) }
            }
        }
    }

    // MARK: - Cosmetic purchases

    enum PurchaseError: Error {
        case productNotFound
    }

    /// Purchase a cosmetic item or the streak shield 3-pack.
    /// On success, unlocks the appropriate CosmeticState items.
    @MainActor
    func purchaseCosmetic(productID: String) async throws {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PurchaseError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await MainActor.run { applyCosmetic(productID: transaction.productID) }
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    private func applyCosmetic(productID: String) {
        let c = CosmeticState.shared
        switch productID {
        case ProductID.cupGold:      c.unlockCup(id: "goldCup")
        case ProductID.cupMidnight:  c.unlockCup(id: "midnight")
        case ProductID.cupDiamond:   c.unlockCup(id: "diamond")
        case ProductID.ballCrystal:  c.unlockBall(id: "crystal")
        case ProductID.tableNeon:    c.unlockTable(id: "neonPurple")
        case ProductID.tableMidBlue: c.unlockTable(id: "midnightBlue")
        case ProductID.starterPack:  c.unlockStarterPack()
        case ProductID.shieldThree:  StreakManager.shared.addShields(3)
        default: break
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }
}

// MARK: - GameCenterManager
// Leaderboard IDs must be registered in App Store Connect before scores can be submitted.
//   cq.leaderboard.score    — all players; ranks by session high score
//   cq.leaderboard.survival — L7 players; ranks by consecutive L7 wins in a session

import GameKit

final class GameCenterManager {

    static let shared = GameCenterManager()
    private init() {}

    var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }

    // MARK: - Authentication

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let error {
                print("GameCenter: auth error — \(error.localizedDescription)")
            }
            // iOS 18 handles presentation automatically; viewController is nil on success
        }
    }

    // MARK: - Score Submission

    func submitHighScore(_ score: Int) {
        guard isAuthenticated, score > 0 else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: ["cq.leaderboard.score"]
                )
            } catch {
                print("GameCenter: score submit failed — \(error.localizedDescription)")
            }
        }
    }

    func submitSurvivalCount(_ count: Int) {
        guard isAuthenticated, count > 0 else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    count, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: ["cq.leaderboard.survival"]
                )
            } catch {
                print("GameCenter: survival submit failed — \(error.localizedDescription)")
            }
        }
    }

    func submitGauntletScore(_ score: Int) {
        guard isAuthenticated, score > 0 else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: ["cq.leaderboard.gauntlet"]
                )
            } catch {
                print("GameCenter: gauntlet submit failed — \(error.localizedDescription)")
            }
        }
    }

    func submitDailyScore(_ score: Int) {
        guard isAuthenticated else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: ["cq.leaderboard.daily"]
                )
            } catch {
                print("GameCenter: daily submit failed — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - GameCenterView (SwiftUI sheet wrapper)

import SwiftUI

struct GameCenterView: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
            dismiss()
        }
    }
}
