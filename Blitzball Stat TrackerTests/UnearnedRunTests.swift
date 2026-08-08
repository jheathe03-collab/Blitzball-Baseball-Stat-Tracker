//
//  UnearnedRunTests.swift
//  Blitzball Stat TrackerTests
//
//  A run scored by a runner who reached base ONLY on an error is unearned (rule 9.16): it still
//  counts as a run allowed but not against the pitcher's ERA. The engine auto-detects this narrow,
//  unambiguous case; runs that are unearned only because an error prolonged the inning are left to
//  the manual Edit Play flow. These cover the outcome predicate, the charge split, the reach→score
//  round trip through Game.record, and the bookkeeping (half-inning clear, pinch-runner handoff).
//
//  Models are built standalone (no ModelContainer — the app-hosted test bundle can't create one).
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct UnearnedRunTests {

    private struct Fixture {
        let game: Game
        let batterLine: GameStatLine
        let pitcherLine: GameStatLine
    }

    /// Top of the 1st: away bats, home pitches. Bases empty.
    private func makeFixture() -> Fixture {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true
        game.homeInningRuns = [0]
        game.awayInningRuns = [0]
        game.outs = 0

        let batterLine = GameStatLine(player: Player(name: "Sam"), isHome: false, battingOrder: 0)
        let pitcherLine = GameStatLine(player: Player(name: "Darrin"), isHome: true, battingOrder: 0)
        for line in [batterLine, pitcherLine] { line.game = game }
        game.statLines = [batterLine, pitcherLine]
        game.homePitcher = pitcherLine.player
        return Fixture(game: game, batterLine: batterLine, pitcherLine: pitcherLine)
    }

    /// Only a batter who reached SOLELY on an error qualifies — the "advanced on error" variants
    /// (a real hit where the error just added bases) and clean hits do not.
    @Test func onlyReachedOnErrorOutcomesCountAsUnearned() {
        #expect(PlateAppearanceOutcome.reachedOnError.batterReachedOnError)
        #expect(PlateAppearanceOutcome.reachedOnTwoBaseError.batterReachedOnError)
        #expect(PlateAppearanceOutcome.reachedOnThreeBaseError.batterReachedOnError)
        #expect(!PlateAppearanceOutcome.singleAdvancedOnError.batterReachedOnError)
        #expect(!PlateAppearanceOutcome.single.batterReachedOnError)
        #expect(!PlateAppearanceOutcome.fieldersChoice.batterReachedOnError)
    }

    /// The whole point: a reached-on-error runner scores a run that's charged as allowed but not earned.
    @Test func reachedOnErrorRunnerScoresAnUnearnedRun() {
        let f = makeFixture()
        f.game.record(.reachedOnError)                       // Sam reaches first on an error
        #expect(f.game.reachedOnErrorRunners.contains("Sam"))
        #expect(f.game.runner(onBase: 0)?.name == "Sam")

        f.game.lastPlayUnearnedRuns = 0                      // the live screen resets this each play
        f.game.scoreRunner(onBase: 0, rbiTo: nil)            // Sam comes around to score

        #expect(f.pitcherLine.pitching.runsAllowed == 1)
        #expect(f.pitcherLine.pitching.earnedRuns == 0)      // unearned — he only reached on the error
        #expect(f.game.lastPlayUnearnedRuns == 1)            // surfaced so the play log records it
        #expect(f.game.reachedOnErrorRunners.isEmpty)        // cleared once he scored
    }

    /// A runner who reached cleanly scores an EARNED run — the fix doesn't downgrade ordinary runs.
    @Test func cleanRunnerScoresAnEarnedRun() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Sam"), onBase: 0)     // reached on a hit; not in the error set

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.pitcherLine.pitching.runsAllowed == 1)
        #expect(f.pitcherLine.pitching.earnedRuns == 1)
        #expect(f.game.lastPlayUnearnedRuns == 0)
    }

    /// The error set clears at the end of a half-inning, so an unearned status never bleeds forward.
    @Test func halfInningClearsTheReachedOnErrorSet() {
        let f = makeFixture()
        f.game.reachedOnErrorRunners = ["Sam"]

        f.game.advanceHalfInning()

        #expect(f.game.reachedOnErrorRunners.isEmpty)
    }

    /// A pinch runner taking over the base inherits the unearned status — the run stays unearned.
    @Test func pinchRunnerInheritsTheUnearnedStatus() {
        let f = makeFixture()
        f.game.reachedOnErrorRunners = ["Sam"]

        f.game.transferResponsibility(from: Player(name: "Sam"), to: Player(name: "Jordan"))

        #expect(!f.game.reachedOnErrorRunners.contains("Sam"))
        #expect(f.game.reachedOnErrorRunners.contains("Jordan"))
    }
}
