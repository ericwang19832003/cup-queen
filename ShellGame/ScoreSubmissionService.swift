// ScoreSubmissionService.swift
// Posts scores to the Supabase scores table.
// On network failure, enqueues the entry in UserDefaults for later retry.

import Foundation

final class ScoreSubmissionService {

    static let shared = ScoreSubmissionService()
    private init() {}

    private let queueKey = "cq_pending_scores"

    // MARK: - Public API

    /// Submit a score. On failure, the entry is queued for retry.
    func submit(playerName: String, score: Int, mode: String, level: Int) {
        let entry: [String: Any] = [
            "player_name": playerName,
            "score": score,
            "mode": mode,
            "level": level
        ]
        post(entry) { [weak self] success in
            if !success { self?.enqueue(entry) }
        }
    }

    /// Drain the offline queue — call on app foreground.
    func drainQueue() {
        guard let entry = peekQueue() else { return }
        post(entry) { [weak self] success in
            if success {
                _ = self?.dequeue()
                self?.drainQueue()   // recurse until empty
            }
        }
    }

    // MARK: - Queue (internal for tests)

    func enqueue(_ entry: [String: Any]) {
        var queue = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        queue.append(entry)
        UserDefaults.standard.set(queue, forKey: queueKey)
    }

    @discardableResult
    func dequeue() -> [String: Any]? {
        var queue = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        guard !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        UserDefaults.standard.set(queue, forKey: queueKey)
        return first
    }

    // MARK: - Private

    private func peekQueue() -> [String: Any]? {
        (UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]])?.first
    }

    private func post(_ entry: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: entry) else {
            completion(false); return
        }
        var request = URLRequest(url: SupabaseConfig.scoresURL)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal",   forHTTPHeaderField: "Prefer")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            completion(ok)
        }.resume()
    }
}
