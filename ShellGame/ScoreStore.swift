// ScoreStore.swift
// Persists session scores locally. Top 20 entries kept, sorted by score descending.

import Foundation

struct ScoreEntry: Codable, Identifiable {
    let id: UUID
    let score: Int
    let level: Int
    let survivalCount: Int   // consecutive L7 wins in that session (0 if not at L7)
    let date: Date
}

final class ScoreStore {
    static let shared = ScoreStore()
    private let storageKey = "cq_score_history"
    private let maxEntries = 20
    private init() {}

    /// Saves a session result and returns the UUID of the new entry, or nil if score == 0.
    @discardableResult
    func save(score: Int, level: Int, survivalCount: Int) -> UUID? {
        guard score > 0 else { return nil }
        var entries = loadAll()
        let entry = ScoreEntry(
            id: UUID(),
            score: score,
            level: level,
            survivalCount: survivalCount,
            date: Date()
        )
        entries.append(entry)
        entries.sort { $0.score > $1.score }
        let trimmed = Array(entries.prefix(maxEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        return entry.id
    }

    func loadAll() -> [ScoreEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([ScoreEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.score > $1.score }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
