//
//  Game+Challenges.swift
//  Blitzball Stat Tracker
//
//  Manager challenges (opt-in via the `challenges` setting). Each team gets `settings.challenges`
//  challenges. A FAILED challenge (call stood) uses one up; a SUCCESSFUL one (call overturned) is
//  retained, matching how MLB replay works. The raw counters live on Game; these are the derived
//  reads + the single mutation the live screen calls.
//

import Foundation

/// One logged challenge — who called it, when (which half-inning), and how it turned out. Kept as a
/// value type in a JSON blob on the Game (see `Game.challengeCalls`), so it rides snapshots/Undo and
/// the archives with no schema change.
struct ChallengeCall: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The team that challenged (true = home).
    var isHome: Bool
    var inning: Int
    var isTopInning: Bool
    /// true = successful (call overturned, retained); false = failed (call stood, spent one).
    var upheld: Bool
    var at: Date = .now
}

extension Game {
    /// The per-challenge log, decoded from its blob (newest last). Setting re-encodes it.
    var challengeCalls: [ChallengeCall] {
        get { BlobCoder.decode(challengeCallsData) ?? [] }
        set { challengeCallsData = BlobCoder.encode(newValue) }
    }

    /// Failed challenges so far for a side (these count against the cap).
    func challengesUsed(isHome: Bool) -> Int {
        isHome ? homeChallengesUsed : awayChallengesUsed
    }

    /// Successful (retained) challenges so far for a side — display only.
    func challengesWon(isHome: Bool) -> Int {
        isHome ? homeChallengesWon : awayChallengesWon
    }

    /// How many challenges a side has left = cap minus the ones they've lost.
    func challengesRemaining(isHome: Bool) -> Int {
        max(0, settings.challenges - challengesUsed(isHome: isHome))
    }

    /// True while at least one side can still challenge (drives the button's enabled state).
    var anyChallengesRemaining: Bool {
        challengesRemaining(isHome: true) > 0 || challengesRemaining(isHome: false) > 0
    }

    /// Record a challenge for a side. Success is retained (won++); failure spends one (used++). Also
    /// appends to the per-challenge log with the current half-inning for the "View Challenges" recap.
    func recordChallenge(isHome: Bool, success: Bool) {
        switch (isHome, success) {
        case (true, true):   homeChallengesWon += 1
        case (true, false):  homeChallengesUsed += 1
        case (false, true):  awayChallengesWon += 1
        case (false, false): awayChallengesUsed += 1
        }
        var log = challengeCalls
        log.append(ChallengeCall(isHome: isHome, inning: currentInning,
                                 isTopInning: isTopInning, upheld: success))
        challengeCalls = log
    }
}
