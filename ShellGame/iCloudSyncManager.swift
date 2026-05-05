// iCloudSyncManager.swift
// Mirrors all game-progress UserDefaults keys to NSUbiquitousKeyValueStore.
// No backend, no registration — uses the player's Apple ID automatically.

import Foundation

final class iCloudSyncManager {

    static let shared = iCloudSyncManager()
    private let store = NSUbiquitousKeyValueStore.default

    /// All keys synced between UserDefaults and iCloud KV Store.
    static let syncKeys: [String] = [
        "cq_wins", "cq_highScore", "cq_bestLevel", "cq_ftue_done",
        "cq_bestSurvival", "cq_best_gauntlet", "cq_prestige",
        "cq_daily_streak", "cq_daily_last_date"
    ]

    private init() {}

    // MARK: - Push (local → iCloud)

    /// Copies all local UserDefaults values to iCloud KV Store.
    func push() {
        for key in Self.syncKeys {
            if let val = UserDefaults.standard.object(forKey: key) {
                store.set(val, forKey: key)
            } else {
                store.removeObject(forKey: key)
            }
        }
        store.synchronize()
    }

    // MARK: - Conflict Detection

    /// True if both local and iCloud have a value for any key AND they differ.
    func hasConflict() -> Bool {
        for key in Self.syncKeys {
            guard let remote = store.object(forKey: key),
                  let local  = UserDefaults.standard.object(forKey: key) else { continue }
            if (remote as? NSObject)?.isEqual(local) != true { return true }
        }
        return false
    }

    // MARK: - Resolution

    /// Overwrites local UserDefaults with all iCloud values.
    func applyiCloud() {
        for key in Self.syncKeys {
            if let val = store.object(forKey: key) {
                UserDefaults.standard.set(val, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Overwrites iCloud with all local UserDefaults values.
    func applyLocal() {
        push()
    }

    // MARK: - Snapshots (for conflict UI)

    func remoteSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Self.syncKeys {
            if let val = store.object(forKey: key) { out[key] = val }
        }
        return out
    }

    func localSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Self.syncKeys {
            if let val = UserDefaults.standard.object(forKey: key) { out[key] = val }
        }
        return out
    }

    // MARK: - Silent New-Device Apply

    /// On a fresh device: silently apply any iCloud keys that local is missing.
    func silentlyApplyRemoteIfNewer() {
        guard !hasConflict() else { return }
        for key in Self.syncKeys {
            if UserDefaults.standard.object(forKey: key) == nil,
               let remote = store.object(forKey: key) {
                UserDefaults.standard.set(remote, forKey: key)
            }
        }
    }
}
