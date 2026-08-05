//
//  PlayEditingTests.swift
//  Blitzball Stat TrackerTests
//
//  Correcting a recorded play. A bug here would silently corrupt stats rather than crash, so these
//  lean on round-trip and conservation properties: re-scoring back to the original must restore the
//  line exactly, and moving a play between players must preserve the totals.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct PlayEditingTests {

    private struct Fixture {
        let game: Game
        let batter: Player, otherBatter: Player
        let pitcher: Player, reliever: Player
        let batterLine: GameStatLine, otherBatterLine: GameStatLine
        let pitcherLine: GameStatLine, relieverLine: GameStatLine
    }

    /// Top of the 1st: away bats, home pitches.
    private func makeFixture() -> Fixture {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true
        game.homeInningRuns = [0]; game.awayInningRuns = [0]

        let batter = Player(name: "Sam"), otherBatter = Player(name: "Ian")
        let pitcher = Player(name: "Darrin"), reliever = Player(name: "Kelsie")

        let bl = GameStatLine(player: batter, isHome: false, battingOrder: 0)
        let obl = GameStatLine(player: otherBatter, isHome: false, battingOrder: 1)
        let pl = GameStatLine(player: pitcher, isHome: true, battingOrder: 0)
        let rl = GameStatLine(player: reliever, isHome: true, battingOrder: 1)
        for l in [bl, obl, pl, rl] { l.game = game }
        game.statLines = [bl, obl, pl, rl]
        game.awayPitcher = nil; game.homePitcher = pitcher

        return Fixture(game: game, batter: batter, otherBatter: otherBatter,
                       pitcher: pitcher, reliever: reliever,
                       batterLine: bl, otherBatterLine: obl, pitcherLine: pl, relieverLine: rl)
    }

    /// Record a play the way the live screen does: apply the stats, then log it.
    private func record(_ f: Fixture, _ outcome: PlateAppearanceOutcome, runs: Int = 0) -> PlayEvent {
        f.batterLine.batting.record(outcome)
        f.pitcherLine.pitching.recordAllowed(outcome)
        if outcome.chargesError { f.game.homeErrors += 1 }
        return f.game.logPlay(.plateAppearance, outcome: outcome,
                              batter: f.batter, pitcher: f.pitcher, runsScored: runs)
    }

    // MARK: - Re-scoring

    /// The whole point of the feature: a double that was really a single plus a misplay.
    @Test func doubleBecomesSinglePlusError() throws {
        let f = makeFixture()
        let play = record(f, .double)
        #expect(f.batterLine.batting.doubles == 1)

        f.game.reclassify(play, to: .singleAdvancedOnError)

        #expect(f.batterLine.batting.hits == 1)
        #expect(f.batterLine.batting.doubles == 0)          // the inflation, removed
        #expect(f.batterLine.batting.totalBases == 1)
        #expect(f.batterLine.batting.atBats == 1)           // still exactly one plate appearance
        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.pitcherLine.pitching.hitsAllowed == 1)
        #expect(f.game.homeErrors == 1)                     // charged to the fielding side
        #expect(play.outcome == .singleAdvancedOnError)
    }

    /// Re-scoring back to the original must land on exactly the starting numbers — no drift.
    @Test func reclassifyingBackRestoresTheOriginalLine() throws {
        let f = makeFixture()
        let play = record(f, .double)
        let batting = f.batterLine.batting
        let pitching = f.pitcherLine.pitching

        f.game.reclassify(play, to: .reachedOnTwoBaseError)
        f.game.reclassify(play, to: .double)

        #expect(f.batterLine.batting == batting)
        #expect(f.pitcherLine.pitching == pitching)
        #expect(f.game.homeErrors == 0)                     // the error was refunded too
    }

    /// Editing the same play repeatedly must compound correctly rather than accumulate.
    @Test func repeatedEditsDoNotAccumulate() throws {
        let f = makeFixture()
        let play = record(f, .single)

        f.game.reclassify(play, to: .reachedOnError)
        f.game.reclassify(play, to: .fieldersChoice)
        f.game.reclassify(play, to: .reachedOnError)

        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.batterLine.batting.reachedOnError == 1)
        #expect(f.game.homeErrors == 1)                     // exactly one, not three
    }

    /// A hit that becomes an error must stop counting against the pitcher.
    @Test func singleBecomingAnErrorRemovesTheHitAllowed() throws {
        let f = makeFixture()
        let play = record(f, .single)
        f.game.reclassify(play, to: .reachedOnError)

        #expect(f.pitcherLine.pitching.hitsAllowed == 0)
        #expect(f.pitcherLine.pitching.atBatsAgainst == 1)
        #expect(f.batterLine.batting.battingAverage == 0)
    }

    /// An out that was really a baserunner gives the inning its out back — but only when the play
    /// is in the half-inning currently being played.
    @Test func outBecomingAnErrorReturnsTheOutToTheCurrentInning() throws {
        let f = makeFixture()
        f.game.outs = 1
        let play = record(f, .out)

        f.game.reclassify(play, to: .reachedOnError)

        #expect(f.game.outs == 0)
        #expect(f.pitcherLine.pitching.outsRecorded == 0)
    }

    @Test func editingAnOlderInningLeavesLiveOutsAlone() throws {
        let f = makeFixture()
        let play = record(f, .out)
        f.game.currentInning = 4          // the game has moved on
        f.game.outs = 2

        f.game.reclassify(play, to: .reachedOnError)

        #expect(f.game.outs == 2)                            // untouched
        #expect(f.pitcherLine.pitching.outsRecorded == 0)    // the pitcher's tally still corrects
    }

    // MARK: - Reassigning

    /// Moving a play to another batter must conserve the totals — nothing invented or lost.
    @Test func reassigningBatterMovesTheCreditIntact() throws {
        let f = makeFixture()
        let play = record(f, .double)

        f.game.reassignBatter(play, to: f.otherBatter)

        #expect(f.batterLine.batting == BattingStats())      // original line emptied
        #expect(f.otherBatterLine.batting.hits == 1)
        #expect(f.otherBatterLine.batting.doubles == 1)
        #expect(f.otherBatterLine.batting.plateAppearances == 1)
        #expect(play.batter === f.otherBatter)
    }

    @Test func reassigningPitcherMovesTheCreditIntact() throws {
        let f = makeFixture()
        let play = record(f, .strikeout)

        f.game.reassignPitcher(play, to: f.reliever)

        #expect(f.pitcherLine.pitching == PitchingStats())
        #expect(f.relieverLine.pitching.strikeouts == 1)
        #expect(f.relieverLine.pitching.outsRecorded == 1)
        #expect(play.pitcher === f.reliever)
    }

    /// Re-scoring after a reassignment must hit the NEW player's line, not the old one.
    @Test func reclassifyingAfterReassignmentFollowsTheNewBatter() throws {
        let f = makeFixture()
        let play = record(f, .double)
        f.game.reassignBatter(play, to: f.otherBatter)

        f.game.reclassify(play, to: .singleAdvancedOnError)

        #expect(f.otherBatterLine.batting.doubles == 0)
        #expect(f.otherBatterLine.batting.hits == 1)
        #expect(f.batterLine.batting == BattingStats())      // never touched again
    }

    // MARK: - Earned / unearned

    @Test func markingRunsUnearnedLowersERAOnly() throws {
        let f = makeFixture()
        let play = record(f, .single, runs: 2)
        f.pitcherLine.pitching.runsAllowed = 2
        f.pitcherLine.pitching.earnedRuns = 2
        f.pitcherLine.pitching.outsRecorded = 3

        f.game.setRunsUnearned(play, unearned: true)

        #expect(f.pitcherLine.pitching.runsAllowed == 2)     // still charged the runs
        #expect(f.pitcherLine.pitching.earnedRuns == 0)      // but not against ERA
        #expect(f.pitcherLine.pitching.earnedRunAverage == 0)
        #expect(play.unearnedRuns == 2)
    }

    /// Toggling back restores the earned runs, and toggling twice doesn't double-count.
    @Test func unearnedTogglesBothWaysWithoutDrift() throws {
        let f = makeFixture()
        let play = record(f, .single, runs: 1)
        f.pitcherLine.pitching.runsAllowed = 1
        f.pitcherLine.pitching.earnedRuns = 1

        f.game.setRunsUnearned(play, unearned: true)
        f.game.setRunsUnearned(play, unearned: true)         // no-op
        #expect(f.pitcherLine.pitching.earnedRuns == 0)

        f.game.setRunsUnearned(play, unearned: false)
        #expect(f.pitcherLine.pitching.earnedRuns == 1)
        #expect(play.unearnedRuns == 0)
    }

    // MARK: - Options offered

    @Test func optionsMatchTheBaseTheBatterReached() throws {
        #expect(PlateAppearanceOutcome.single.reclassificationOptions
                == [.single, .reachedOnError, .fieldersChoice])
        #expect(PlateAppearanceOutcome.double.reclassificationOptions
                == [.double, .singleAdvancedOnError, .reachedOnTwoBaseError, .fieldersChoiceToSecond])
        #expect(PlateAppearanceOutcome.triple.reclassificationOptions.count == 5)
        // Reversible: an error variant offers its way back to the plain hit.
        #expect(PlateAppearanceOutcome.reachedOnTwoBaseError.reclassificationOptions.contains(.double))
        // An out can become a baserunner — the common real correction.
        #expect(PlateAppearanceOutcome.out.reclassificationOptions.contains(.reachedOnError))
        // Nothing sensible to swap a walk to.
        #expect(PlateAppearanceOutcome.walk.reclassificationOptions == [.walk])
    }

    /// Every option leaves the batter where he already was, which is why runners never move.
    @Test func everyOptionKeepsTheBatterOnTheSameBase() throws {
        for outcome in PlateAppearanceOutcome.allCases {
            let options = outcome.reclassificationOptions
            guard options.count > 1, outcome.basesReached != nil else { continue }
            for option in options where option.basesReached != nil {
                #expect(option.basesReached == outcome.basesReached)
            }
        }
    }
}
