// MatchState.swift
// ShellGame — Competition / Duel domain types
// Swift 5.9+, iOS 16+, no external dependencies

import Foundation
import Combine

// MARK: - PlayerSide

enum PlayerSide {
    case local
    case remote
}

// MARK: - MatchPhase

enum MatchPhase {
    /// Not in a match.
    case idle
    /// Waiting in GKMatchmaker queue.
    case matchmaking
    /// Matched; 3-2-1 countdown before first round.
    case countdown
    /// Shuffle is running / player can tap.
    case roundActive
    /// Brief result display between rounds.
    case roundResult(winner: PlayerSide)
    /// Match over; show final result.
    case matchResult(winner: PlayerSide)
    /// Opponent disconnected; grace period ticking.
    case disconnected(forfeitAt: Date)
}

// MARK: - DuelMessage

/// Codable messages sent over the GKMatch data channel.
///
/// `PlayerSide` is encoded from the **sender's** perspective:
/// a `.roundWon(by: .local)` message means the *sender* won,
/// so the receiver should interpret it as `.roundWon(by: .remote)`.
enum DuelMessage: Codable {
    /// Host broadcasts a shared shuffle seed before each round.
    case shuffleSeed(UInt64)
    /// Winner broadcasts after tapping correctly.
    case roundWon(by: PlayerSide)
    /// Both sides signal ready; `Int` is the round number.
    case readyForRound(Int)
    /// Sent on disconnect or app backgrounding.
    case forfeit

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case kind, seed, side, round
    }

    private enum Kind: String {
        case shuffleSeed, roundWon, readyForRound, forfeit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shuffleSeed(let seed):
            try container.encode(Kind.shuffleSeed.rawValue, forKey: .kind)
            try container.encode(seed, forKey: .seed)
        case .roundWon(let side):
            try container.encode(Kind.roundWon.rawValue, forKey: .kind)
            try container.encode(side.rawValue, forKey: .side)
        case .readyForRound(let round):
            try container.encode(Kind.readyForRound.rawValue, forKey: .kind)
            try container.encode(round, forKey: .round)
        case .forfeit:
            try container.encode(Kind.forfeit.rawValue, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindString = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown DuelMessage kind: \(kindString)"
            )
        }
        switch kind {
        case .shuffleSeed:
            let seed = try container.decode(UInt64.self, forKey: .seed)
            self = .shuffleSeed(seed)
        case .roundWon:
            let sideRaw = try container.decode(String.self, forKey: .side)
            guard let side = PlayerSide(rawValue: sideRaw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .side,
                    in: container,
                    debugDescription: "Unknown PlayerSide: \(sideRaw)"
                )
            }
            self = .roundWon(by: side)
        case .readyForRound:
            let round = try container.decode(Int.self, forKey: .round)
            self = .readyForRound(round)
        case .forfeit:
            self = .forfeit
        }
    }
}

// MARK: - PlayerSide + RawRepresentable (for Codable)

extension PlayerSide: RawRepresentable {
    typealias RawValue = String

    init?(rawValue: String) {
        switch rawValue {
        case "local":  self = .local
        case "remote": self = .remote
        default:       return nil
        }
    }

    var rawValue: String {
        switch self {
        case .local:  return "local"
        case .remote: return "remote"
        }
    }
}

// MARK: - MatchState

final class MatchState: ObservableObject {

    // MARK: Published state

    @Published private(set) var phase: MatchPhase = .idle
    @Published private(set) var localRoundWins: Int = 0
    @Published private(set) var remoteRoundWins: Int = 0
    @Published private(set) var currentRound: Int = 0
    @Published private(set) var competitionWins: Int

    // MARK: Constants

    let winsNeeded: Int = 3

    // MARK: Private

    private static let competitionWinsKey = "cq_competition_wins"
    private var phaseBeforeDisconnect: MatchPhase?

    // MARK: Init

    init() {
        self.competitionWins = UserDefaults.standard.integer(forKey: Self.competitionWinsKey)
    }

    // MARK: Match lifecycle

    /// Begins searching for an opponent.
    func startMatchmaking() {
        phase = .matchmaking
    }

    /// Called when a GKMatch is found. Resets round counters and starts countdown.
    func matchFound() {
        localRoundWins = 0
        remoteRoundWins = 0
        currentRound = 0
        phase = .countdown
    }

    /// Transitions to .roundActive so DuelGameView mounts without incrementing currentRound.
    /// Called when the countdown finishes; the actual round number is assigned in startRound().
    func prepareRound() {
        phase = .roundActive
    }

    /// Advances to the next round.
    func startRound() {
        currentRound += 1
        phase = .roundActive
    }

    /// Records a round win for `side`, advancing to `roundResult` or `matchResult`.
    func recordRoundWin(for side: PlayerSide) {
        switch side {
        case .local:  localRoundWins  += 1
        case .remote: remoteRoundWins += 1
        }

        if localRoundWins >= winsNeeded || remoteRoundWins >= winsNeeded {
            if side == .local {
                competitionWins += 1
                UserDefaults.standard.set(competitionWins, forKey: Self.competitionWinsKey)
            }
            phase = .matchResult(winner: side)
        } else {
            phase = .roundResult(winner: side)
        }
    }

    // MARK: Disconnection handling

    /// Called when the opponent's connection is lost. Starts the 10-second grace period.
    func opponentDisconnected() {
        phaseBeforeDisconnect = phase
        phase = .disconnected(forfeitAt: Date().addingTimeInterval(10))
    }

    /// Called if the opponent reconnects before the grace period expires.
    func opponentReconnected() {
        guard case .disconnected = phase else { return }
        if let saved = phaseBeforeDisconnect {
            phase = saved
            phaseBeforeDisconnect = nil
        }
    }

    // MARK: Forfeit

    /// Ends the match immediately, awarding the win to `winner`.
    func forfeitMatch(winner: PlayerSide) {
        if winner == .local {
            competitionWins += 1
            UserDefaults.standard.set(competitionWins, forKey: Self.competitionWinsKey)
        }
        phase = .matchResult(winner: winner)
    }

    // MARK: Reset

    /// Resets all match state back to `.idle`.
    func reset() {
        localRoundWins = 0
        remoteRoundWins = 0
        currentRound = 0
        phaseBeforeDisconnect = nil
        phase = .idle
    }
}
