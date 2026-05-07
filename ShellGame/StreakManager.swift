// StreakManager.swift
// Tracks the player's daily play streak, shields, and milestone rewards.
// Call recordRound() after any round completion (any mode).

import Foundation
import UserNotifications

final class StreakManager {
    static let shared = StreakManager()

    // MARK: - UserDefaults Keys (all prefixed cq_ps_ for "play streak")

    private enum K {
        static let count      = "cq_ps_count"
        static let lastDay    = "cq_ps_last_day"
        static let shields    = "cq_ps_shields"
        static let milestones = "cq_ps_milestones"  // [Int] array of claimed day values
    }

    // MARK: - State (read-only from outside)

    private(set) var streakCount: Int = 0
    private(set) var shields: Int = 0
    private(set) var claimedMilestones: Set<Int> = []

    // MARK: - Constants

    /// Milestone day → human-readable reward label (for UI display).
    static let milestoneRewards: [Int: String] = [
        3:   "3 hints",
        7:   "Streak Shield + Gold Felt table",
        14:  "5 hints",
        30:  "Crimson Cup skin",
        60:  "Streak Shield + 10 hints",
        100: "Diamond Animated cup",
        365: "Crown Queen ball + prestige badge"
    ]

    static let maxShields = 3

    // MARK: - Init

    private init() { load() }

    // MARK: - Internal Testing API

    /// Reloads all state from UserDefaults. Call in test setUp() after wiping keys.
    func reloadFromDefaults() { load() }

    // MARK: - Public API

    /// Call after any round completes (any mode).
    /// Returns the set of milestone day numbers newly crossed (empty if none).
    @discardableResult
    func recordRound() -> Set<Int> {
        let today = dayString(for: Date())
        let ud = UserDefaults.standard
        let lastDay = ud.string(forKey: K.lastDay) ?? ""

        // Already recorded today — idempotent.
        if lastDay == today { return [] }

        // Compute gap: 1 = consecutive, 2 = one day missed, 3+ = multiple missed.
        let gap = lastDay.isEmpty ? 0 : daysBetween(from: lastDay, to: today)

        switch gap {
        case 0:
            // First ever play.
            streakCount = 1
        case 1:
            // Consecutive day.
            streakCount += 1
        case 2:
            // Exactly one day missed. Shield saves it.
            if shields > 0 {
                shields -= 1
                ud.set(shields, forKey: K.shields)
                streakCount += 1
            } else {
                streakCount = 1
            }
        default:
            // Two or more days missed. Shields cannot help.
            streakCount = 1
        }

        ud.set(streakCount, forKey: K.count)
        ud.set(today, forKey: K.lastDay)

        // Schedule / update the 8 PM reminder.
        scheduleReminder()

        return checkMilestones()
    }

    /// Awards one shield (from a rewarded ad). Capped at maxShields.
    func addShield() {
        shields = min(shields + 1, Self.maxShields)
        UserDefaults.standard.set(shields, forKey: K.shields)
    }

    /// Awards multiple shields (e.g., 3-pack IAP).
    func addShields(_ count: Int) {
        shields = min(shields + count, Self.maxShields)
        UserDefaults.standard.set(shields, forKey: K.shields)
    }

    // MARK: - Notification

    /// Schedules a repeating 8 PM local reminder. Call after recordRound().
    func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["cq.streak.reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Cup Queen"
        content.body = streakCount > 1
            ? "🔥 Don't lose your \(streakCount)-day streak!"
            : "👑 Your daily challenge is waiting!"
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 20; dc.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(
            identifier: "cq.streak.reminder", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Private helpers

    private func checkMilestones() -> Set<Int> {
        var newOnes = Set<Int>()
        for day in Self.milestoneRewards.keys {
            if streakCount >= day && !claimedMilestones.contains(day) {
                claimedMilestones.insert(day)
                newOnes.insert(day)
            }
        }
        if !newOnes.isEmpty {
            UserDefaults.standard.set(Array(claimedMilestones), forKey: K.milestones)
        }
        return newOnes
    }

    private func load() {
        let ud = UserDefaults.standard
        streakCount = ud.integer(forKey: K.count)
        shields     = ud.integer(forKey: K.shields)
        if let arr = ud.array(forKey: K.milestones) as? [Int] {
            claimedMilestones = Set(arr)
        }
    }

    private func dayString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Number of calendar days from `from` to `to` (always positive going forward).
    private func daysBetween(from: String, to: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d1 = f.date(from: from), let d2 = f.date(from: to) else { return 99 }
        return Calendar.current.dateComponents([.day], from: d1, to: d2).day ?? 99
    }
}
