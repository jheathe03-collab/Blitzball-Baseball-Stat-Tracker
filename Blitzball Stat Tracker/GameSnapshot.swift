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
    /// The per-challenge log, so undoing a challenge drops its recap entry too.
    var challengeCalls: [ChallengeCall]
    /// Save/Blown-Save entry context per side, so undoing a rotation change or a lead-erasing run
    /// restores exactly who was protecting what.
    var homeSaveEntryLead: Int
    var awaySaveEntryLead: Int
    var homeSaveEntryOuts: Int
    var awaySaveEntryOuts: Int
    var homeBlownSaveCharged: Bool
    var awayBlownSaveCharged: Bool
    /// Fielding errors, so undoing a play that charged one takes it back off the board.
    var homeErrors: Int
    var awayErrors: Int
    var runnerFirst: Player?
    var runnerSecond: Player?
    var runnerThird: Player?
    var homePitcher: Player?
    var awayPitcher: Player?
    /// Who was on the hook for each runner on base (runner name → pitcher name).
    var runnerResponsibility: [String: String]
    /// The play log exactly as it stood. A value copy rather than a high-water mark, because Redo
    /// has to PUT BACK entries that Undo removed — restoring reconciles both directions.
    var playRecords: [PlayRecord]
    /// Each stat line's batting/pitching, keyed by its stable SwiftData id.
    var lines: [PersistentIdentifier: LineStats]

    struct LineStats {
        var batting: BattingStats
        var pitching: PitchingStats
    }

    /// A play-log entry captured as a value, so it can be recreated after being deleted.
    struct PlayRecord {
        var sequence: Int
        var kind: PlayEventKind
        var inning: Int
        var isTopInning: Bool
        var outsBefore: Int
        var outcome: PlateAppearanceOutcome?
        var battedBallType: BattedBallType?
        var fieldPosition: FieldPosition?
        var battedOutType: BattedOutType?
        var batter: Player?
        var pitcher: Player?
        var detail: String
        var runsScored: Int
        var unearnedRuns: Int
        var homeScore: Int
        var awayScore: Int
        var createdAt: Date

        init(_ play: PlayEvent) {
            sequence = play.sequence
            kind = play.kind
            inning = play.inning
            isTopInning = play.isTopInning
            outsBefore = play.outsBefore
            outcome = play.outcome
            battedBallType = play.battedBallType
            fieldPosition = play.fieldPosition
            battedOutType = play.battedOutType
            batter = play.batter
            pitcher = play.pitcher
            detail = play.detail
            runsScored = play.runsScored
            unearnedRuns = play.unearnedRuns
            homeScore = play.homeScore
            awayScore = play.awayScore
            createdAt = play.createdAt
        }

        func makeEvent(in game: Game) -> PlayEvent {
            let event = PlayEvent(game: game, sequence: sequence, kind: kind, inning: inning,
                                  isTopInning: isTopInning, outsBefore: outsBefore, outcome: outcome,
                                  battedBallType: battedBallType, fieldPosition: fieldPosition,
                                  battedOutType: battedOutType,
                                  batter: batter, pitcher: pitcher, detail: detail,
                                  runsScored: runsScored, homeScore: homeScore, awayScore: awayScore,
                                  createdAt: createdAt)
            event.unearnedRuns = unearnedRuns
            return event
        }
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
            challengeCalls: challengeCalls,
            homeSaveEntryLead: homeSaveEntryLead,
            awaySaveEntryLead: awaySaveEntryLead,
            homeSaveEntryOuts: homeSaveEntryOuts,
            awaySaveEntryOuts: awaySaveEntryOuts,
            homeBlownSaveCharged: homeBlownSaveCharged,
            awayBlownSaveCharged: awayBlownSaveCharged,
            homeErrors: homeErrors,
            awayErrors: awayErrors,
            runnerFirst: runnerFirst,
            runnerSecond: runnerSecond,
            runnerThird: runnerThird,
            homePitcher: homePitcher,
            awayPitcher: awayPitcher,
            runnerResponsibility: runnerResponsibility,
            playRecords: plays.map(GameSnapshot.PlayRecord.init),
            lines: lines
        )
    }

    /// Restore a previously captured state (Undo).
    ///
    /// Pass the `context` so play-log entries recorded by the undone action are deleted too —
    /// without it the log keeps describing a play the game has already taken back.
    func restore(from snapshot: GameSnapshot, context: ModelContext? = nil) {
        // Reconcile the log in both directions: drop entries this snapshot never had (Undo), and
        // recreate any it had that are missing now (Redo).
        let wanted = Set(snapshot.playRecords.map(\.sequence))
        for play in plays where !wanted.contains(play.sequence) {
            play.game = nil
            context?.delete(play)
        }
        plays.removeAll { !wanted.contains($0.sequence) }
        let present = Set(plays.map(\.sequence))
        for record in snapshot.playRecords where !present.contains(record.sequence) {
            let event = record.makeEvent(in: self)
            context?.insert(event)
            plays.append(event)
        }
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
        challengeCalls = snapshot.challengeCalls
        homeSaveEntryLead = snapshot.homeSaveEntryLead
        awaySaveEntryLead = snapshot.awaySaveEntryLead
        homeSaveEntryOuts = snapshot.homeSaveEntryOuts
        awaySaveEntryOuts = snapshot.awaySaveEntryOuts
        homeBlownSaveCharged = snapshot.homeBlownSaveCharged
        awayBlownSaveCharged = snapshot.awayBlownSaveCharged
        homeErrors = snapshot.homeErrors
        awayErrors = snapshot.awayErrors
        runnerFirst = snapshot.runnerFirst
        runnerSecond = snapshot.runnerSecond
        runnerThird = snapshot.runnerThird
        homePitcher = snapshot.homePitcher
        awayPitcher = snapshot.awayPitcher
        runnerResponsibility = snapshot.runnerResponsibility
        for line in statLines {
            if let saved = snapshot.lines[line.persistentModelID] {
                line.batting = saved.batting
                line.pitching = saved.pitching
            }
        }
    }
}
