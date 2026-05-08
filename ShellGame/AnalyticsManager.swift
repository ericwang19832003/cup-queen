// AnalyticsManager.swift
// Structured analytics layer — currently logs to console.
// To activate Firebase Analytics:
//   1. Add Firebase iOS SDK via SPM: https://github.com/firebase/firebase-ios-sdk
//   2. Add GoogleService-Info.plist to the ShellGame target
//   3. Uncomment FirebaseApp.configure() in ShellGameApp.init()
//   4. Replace each print() call below with the corresponding
//      FirebaseAnalytics.logEvent(_:parameters:) call shown in comments

import Foundation

// MARK: - Event Definitions

enum AnalyticsEvent {
    /// A game session began (user entered a play mode).
    case sessionStart(mode: String)
    /// A round resolved — win or loss.
    case roundResult(mode: String, level: Int, correct: Bool)
    /// An ad was displayed to the user.
    case adShow(type: String)   // "interstitial" | "rewarded"
    /// User tapped a purchase button.
    case purchaseTapped(productID: String)
}

// MARK: - Manager

enum AnalyticsManager {

    // MARK: - Log

    static func log(_ event: AnalyticsEvent) {
        switch event {

        case .sessionStart(let mode):
            // TODO: ANALYTICS
            // FirebaseAnalytics.logEvent("session_start", parameters: ["mode": mode])
            print("[Analytics] session_start mode=\(mode)")

        case .roundResult(let mode, let level, let correct):
            // TODO: ANALYTICS
            // FirebaseAnalytics.logEvent("round_result", parameters: [
            //     "mode": mode, "level": level, "correct": correct ? 1 : 0
            // ])
            print("[Analytics] round_result mode=\(mode) level=\(level) correct=\(correct)")

        case .adShow(let type):
            // TODO: ANALYTICS
            // FirebaseAnalytics.logEvent("ad_show", parameters: ["type": type])
            print("[Analytics] ad_show type=\(type)")

        case .purchaseTapped(let productID):
            // TODO: ANALYTICS
            // FirebaseAnalytics.logEvent("purchase_tapped", parameters: ["product_id": productID])
            print("[Analytics] purchase_tapped productID=\(productID)")
        }
    }
}
