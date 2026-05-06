// GameCenterMatchManager.swift
// ShellGame — Game Center real-time match coordination for Cup Queen duels
// Swift 5.9+, iOS 16+, no external dependencies

import GameKit
import Foundation

// MARK: - GameCenterMatchManager

final class GameCenterMatchManager: NSObject {

    // MARK: Shared instance

    static let shared = GameCenterMatchManager()
    private override init() { super.init() }

    // MARK: Dependencies

    /// Set by CompetitionView before starting matchmaking.
    weak var matchState: MatchState?

    // MARK: Private state

    private var match: GKMatch?
    private var forfeitTimer: Timer?

    // MARK: - Host determination

    /// The host is the player whose `gamePlayerID` is lexicographically smallest
    /// across all participants. Both devices compute this independently from the
    /// same match player list, so they always agree without a handshake.
    var isHost: Bool {
        guard let match else { return false }
        let localID = GKLocalPlayer.local.gamePlayerID
        let allIDs = ([localID] + match.players.map(\.gamePlayerID)).sorted()
        return allIDs.first == localID
    }

    // MARK: - Matchmaking

    /// Begins searching for a two-player match via GKMatchmaker.
    func startMatchmaking() {
        matchState?.startMatchmaking()

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.playerGroup = 0   // open pool; future: ranked groups

        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            DispatchQueue.main.async {
                if let error {
                    print("GCMatchManager: matchmaking error — \(error.localizedDescription)")
                    self?.matchState?.reset()
                    return
                }
                guard let match else { return }
                self?.match = match
                match.delegate = self
                self?.matchState?.matchFound()
            }
        }
    }

    /// Cancels an in-progress matchmaking search or drops the active match.
    func cancelMatchmaking() {
        GKMatchmaker.shared().cancel()
        match?.disconnect()
        match = nil
        matchState?.reset()
    }

    // MARK: - Messaging

    /// Encodes and sends a `DuelMessage` reliably to all remote players.
    func sendMessage(_ message: DuelMessage) {
        guard let match else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            print("GCMatchManager: send failed — \(error)")
        }
    }

    // MARK: - Disconnect

    /// Tears down the active match and cancels any pending forfeit timer.
    func disconnect() {
        forfeitTimer?.invalidate()
        forfeitTimer = nil
        match?.disconnect()
        match = nil
    }
}

// MARK: - GKMatchDelegate

extension GameCenterMatchManager: GKMatchDelegate {

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let message = try? JSONDecoder().decode(DuelMessage.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleMessage(message)
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .disconnected:
                self?.matchState?.opponentDisconnected()
                // Start forfeit timer — if opponent doesn't reconnect within 10 s, they forfeit.
                self?.forfeitTimer?.invalidate()
                self?.forfeitTimer = Timer.scheduledTimer(
                    withTimeInterval: 10,
                    repeats: false
                ) { [weak self] _ in
                    self?.matchState?.forfeitMatch(winner: .local)
                }
            case .connected:
                self?.forfeitTimer?.invalidate()
                self?.forfeitTimer = nil
                self?.matchState?.opponentReconnected()
            default:
                break
            }
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            print("GCMatchManager: match failed — \(error?.localizedDescription ?? "unknown")")
            self?.matchState?.reset()
        }
    }
}

// MARK: - Message handling

private extension GameCenterMatchManager {

    func handleMessage(_ message: DuelMessage) {
        guard let state = matchState else { return }
        switch message {

        case .shuffleSeed(let seed):
            // CompetitionView observes matchState.phase to trigger round start.
            // The seed is surfaced via a notification so CompetitionView (or the
            // SpriteKit scene) can set up the identical shuffle without coupling
            // directly to this manager.
            NotificationCenter.default.post(
                name: .duelShuffleSeedReceived,
                object: nil,
                userInfo: ["seed": seed]
            )

        case .roundWon:
            // Sender won — from the receiver's perspective, the remote player won.
            state.recordRoundWin(for: .remote)

        case .readyForRound(let round):
            NotificationCenter.default.post(
                name: .duelOpponentReadyForRound,
                object: nil,
                userInfo: ["round": round]
            )

        case .forfeit:
            state.forfeitMatch(winner: .local)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the host broadcasts a shuffle seed for the upcoming round.
    /// `userInfo["seed"]` is a `UInt64`.
    static let duelShuffleSeedReceived   = Notification.Name("cq.duel.shuffleSeedReceived")

    /// Posted when the remote player signals readiness for a round.
    /// `userInfo["round"]` is an `Int`.
    static let duelOpponentReadyForRound = Notification.Name("cq.duel.opponentReadyForRound")
}
