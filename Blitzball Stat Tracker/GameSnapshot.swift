//
//  GameSnapshot.swift
//  Blitzball Stat Tracker
//
//  A value snapshot of everything a single play can change. The live screen pushes one of these
//  before each action, so Undo can restore the game exactly. Stats are value-type structs, so a
//  snapshot is just a copy.
//

import Foundation
import SwiftData

struct GameSnapshot {
    var currentInning: Int
    var isTopInning: Bool
    var outs: Int
    var awayInningRuns: [Int]
    var homeInningRuns: [Int]
    var homeBatterIndex: Int
    var awayBatterIndex: Int
    var homePitchingSwaps: Int
    var awayPitchingSwaps: Int
    var homePitcherOuts: Int
    var awayPitcherOuts: Int
    var homeChallengesUsed: Int
    var awayChallengesUsed: Int
    var homeChallengesWon: Int
    var awayChallengesWon: Int
    var runnerFirst: Player?
    var runnerSecond: Player?
    var runnerThird: Player?
    var homePitcher: Player?
    var awayPitcher: Player?
    /// Each stat line's batting/pitching, keyed by its stable SwiftData id.
    var lines: [PersistentIdentifier: LineStats]

    struct LineStats {
        var batting: BattingStats
        var pitching: PitchingStats
    }
}

extension Game {
    /// Capture the current state.
    func snapshot() -> GameSnapshot {
        var lines: [PersistentIdentifier: GameSnapshot.LineStats] = [:]
        for line in statLines {
            lines[line.persistentModelID] = .init(batting: line.batting, pitching: line.pitching)
        }
        return GameSnapshot(
            currentInning: currentInning,
            isTopInning: isTopInning,
            outs: outs,
            awayInningRuns: awayInningRuns,
            homeInningRuns: homeInningRuns,
            homeBatterIndex: homeBatterIndex,
            awayBatterIndex: awayBatterIndex,
            homePitchingSwaps: homePitchingSwaps,
            awayPitchingSwaps: awayPitchingSwaps,
            homePitcherOuts: homePitcherOuts,
            awayPitcherOuts: awayPitcherOuts,
            homeChallengesUsed: homeChallengesUsed,
            awayChallengesUsed: awayChallengesUsed,
            homeChallengesWon: homeChallengesWon,
            awayChallengesWon: awayChallengesWon,
            runnerFirst: runnerFirst,
            runnerSecond: runnerSecond,
            runnerThird: runnerThird,
            homePitcher: homePitcher,
            awayPitcher: awayPitcher,
            lines: lines
        )
    }

    /// Restore a previously captured state (Undo).
    func restore(from snapshot: GameSnapshot) {
        currentInning = snapshot.currentInning
        isTopInning = snapshot.isTopInning
        outs = snapshot.outs
        awayInningRuns = snapshot.awayInningRuns
        homeInningRuns = snapshot.homeInningRuns
        homeBatterIndex = snapshot.homeBatterIndex
        awayBatterIndex = snapshot.awayBatterIndex
        homePitchingSwaps = snapshot.homePitchingSwaps
        awayPitchingSwaps = snapshot.awayPitchingSwaps
        homePitcherOuts = snapshot.homePitcherOuts
        awayPitcherOuts = snapshot.awayPitcherOuts
        homeChallengesUsed = snapshot.homeChallengesUsed
        awayChallengesUsed = snapshot.awayChallengesUsed
        homeChallengesWon = snapshot.homeChallengesWon
        awayChallengesWon = snapshot.awayChallengesWon
        runnerFirst = snapshot.runnerFirst
        runnerSecond = snapshot.runnerSecond
        runnerThird = snapshot.runnerThird
        homePitcher = snapshot.homePitcher
        awayPitcher = snapshot.awayPitcher
        for line in statLines {
            if let saved = snapshot.lines[line.persistentModelID] {
                line.batting = saved.batting
                line.pitching = saved.pitching
            }
        }
    }
}
