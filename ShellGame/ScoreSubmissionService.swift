// ScoreSubmissionService.swift
// Posts scores to the Supabase scores table.
// On transient failure (5xx / network error), enqueues for retry.
// On permanent failure (4xx), the entry is silently discarded.

import Foundation

final class ScoreSubmissionService {

    static let shared = ScoreSubmissionService()
    private init() {}

    private let queueKey   = "cq_pending_scores"
    private let queue      = DispatchQueue(label: "com.cupqueen.scorequeue")
    private var isDraining = false

    // MARK: - Public API

    /// Submit a score. On transient failure (network/5xx), the entry is queued for retry.
    func submit(playerName: String, score: Int, mode: String, level: Int) {
        let entry: [String: Any] = [
            "player_name": playerName,
            "score": score,
            "mode": mode,
            "level": level
        ]
        post(entry) { [weak self] result in
            if case .transientFailure = result {
                self?.queue.async { self?.enqueueUnsafe(entry) }
            }
            // .permanentFailure → discard silently
            // .success → nothing to do
        }
    }

    /// Drain the offline queue — call on app foreground.
    func drainQueue() {
        queue.async { [weak self] in
            guard let self, !self.isDraining else { return }
            self.isDraining = true
            self.drainNext()
        }
    }

    // MARK: - Queue (internal access for tests)

    func enqueue(_ entry: [String: Any]) {
        queue.async { [weak self] in self?.enqueueUnsafe(entry) }
    }

    @discardableResult
    func dequeue() -> [String: Any]? {
        queue.sync { dequeueUnsafe() }
    }

    // MARK: - Private queue helpers (must be called on self.queue)

    private func enqueueUnsafe(_ entry: [String: Any]) {
        var q = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        q.append(entry)
        UserDefaults.standard.set(q, forKey: queueKey)
    }

    @discardableResult
    private func dequeueUnsafe() -> [String: Any]? {
        var q = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
        guard !q.isEmpty else { return nil }
        let first = q.removeFirst()
        UserDefaults.standard.set(q, forKey: queueKey)
        return first
    }

    private func peekQueueUnsafe() -> [String: Any]? {
        (UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]])?.first
    }

    private func drainNext() {
        // Must be called on self.queue
        guard let entry = peekQueueUnsafe() else {
            isDraining = false
            return
        }
        post(entry) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success:
                    _ = self.dequeueUnsafe()
                    self.drainNext()
                case .permanentFailure:
                    _ = self.dequeueUnsafe()   // discard bad entry, try next
                    self.drainNext()
                case .transientFailure:
                    self.isDraining = false    // stop; try again next foreground
                }
            }
        }
    }

    // MARK: - Network

    private enum PostResult { case success, transientFailure, permanentFailure }

    private func post(_ entry: [String: Any], completion: @escaping (PostResult) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: entry) else {
            completion(.permanentFailure); return
        }
        var request = URLRequest(url: SupabaseConfig.scoresURL)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal",   forHTTPHeaderField: "Prefer")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    completion(.success)
                } else if (400...499).contains(http.statusCode) {
                    completion(.permanentFailure)   // bad request — don't retry
                } else {
                    completion(.transientFailure)   // 5xx / unexpected
                }
            } else {
                // network error (no response)
                completion(.transientFailure)
            }
        }.resume()
    }
}
