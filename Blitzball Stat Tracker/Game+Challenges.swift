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

extension Game {
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

    /// Record a challenge for a side. Success is retained (won++); failure spends one (used++).
    func recordChallenge(isHome: Bool, success: Bool) {
        switch (isHome, success) {
        case (true, true):   homeChallengesWon += 1
        case (true, false):  homeChallengesUsed += 1
        case (false, true):  awayChallengesWon += 1
        case (false, false): awayChallengesUsed += 1
        }
    }
}
