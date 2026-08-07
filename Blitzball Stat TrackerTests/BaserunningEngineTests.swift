//
//  BaserunningEngineTests.swift
//  Blitzball Stat TrackerTests
//
//  Phase 2 of drag-to-steal: Game.recordSafeAdvance / recordBaserunningOut. A safe advance moves the
//  runner (or scores him at home with no RBI) and applies the reason's credit; an out removes him and
//  records the out. Covers the stat effects, scoring, error charging, and ending the half-inning.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct BaserunningEngineTests {

    private struct Fixture {
        let game: Game
        let runnerLine: GameStatLine
        let pitcherLine: GameStatLine
    }

    /// Top of the 1st: away bats, home pitches. A runner is standing on first.
    private func makeFixture(runnerOn base: Int = 0) -> Fixture {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true
        game.homeInningRuns = [0]
        game.awayInningRuns = [0]
        game.outs = 0

        let runnerLine = GameStatLine(player: Player(name: "Rudy"), isHome: false, battingOrder: 0)
        let pitcherLine = GameStatLine(player: Player(name: "Darrin"), isHome: true, battingOrder: 0)
        for line in [runnerLine, pitcherLine] { line.game = game }
        game.statLines = [runnerLine, pitcherLine]
        game.homePitcher = pitcherLine.player
        game.setRunner(runnerLine.player, onBase: base)
        return Fixture(game: game, runnerLine: runnerLine, pitcherLine: pitcherLine)
    }

    @Test func stolenBaseMovesRunnerAndCreditsSB() {
        let f = makeFixture(runnerOn: 0)
        let line = f.game.recordSafeAdvance(fromBase: 0, toBase: 1, reason: .stolenBase)

        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1)?.name == "Rudy")
        #expect(f.runnerLine.batting.stolenBases == 1)
        #expect(f.game.outs == 0)
        #expect(line == "Rudy steals second.")
    }

    @Test func throwingErrorAdvancesWithoutSBAndChargesFieldingTeam() {
        let f = makeFixture(runnerOn: 0)
        f.game.recordSafeAdvance(fromBase: 0, toBase: 1, reason: .throwingError)

        #expect(f.game.runner(onBase: 1)?.name == "Rudy")
        #expect(f.runnerLine.batting.stolenBases == 0)     // no steal on an error
        #expect(f.game.homeErrors == 1)                    // charged to the fielding (home) team
    }

    @Test func stealOfHomeScoresWithNoRBI() {
        let f = makeFixture(runnerOn: 2)   // runner on third
        let line = f.game.recordSafeAdvance(fromBase: 2, toBase: 3, reason: .stolenBase)

        #expect(f.game.runner(onBase: 2) == nil)
        #expect(f.game.awayScore == 1)                     // the run counts
        #expect(f.runnerLine.batting.runsScored == 1)
        #expect(f.runnerLine.batting.rbi == 0)             // a steal of home is never an RBI
        #expect(f.runnerLine.batting.stolenBases == 1)
        #expect(line == "Rudy steals home.")
    }

    @Test func caughtStealingRemovesRunnerAndRecordsOut() {
        let f = makeFixture(runnerOn: 0)
        let line = f.game.recordBaserunningOut(fromBase: 0, toBase: 1, reason: .caughtStealing)

        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.outs == 1)
        #expect(f.pitcherLine.pitching.outsRecorded == 1)
        #expect(f.runnerLine.batting.caughtStealing == 1)
        #expect(line == "Rudy caught stealing at second.")
    }

    @Test func pickedOffRecordsOutWithoutCaughtStealing() {
        let f = makeFixture(runnerOn: 0)
        f.game.recordBaserunningOut(fromBase: 0, toBase: 0, reason: .pickedOff)

        #expect(f.game.outs == 1)
        #expect(f.runnerLine.batting.caughtStealing == 0)
    }

    @Test func aBaserunningOutCanEndTheHalfInning() {
        let f = makeFixture(runnerOn: 1)
        f.game.outs = 2   // two away already
        f.game.recordBaserunningOut(fromBase: 1, toBase: 2, reason: .caughtStealing)

        #expect(f.game.isTopInning == false)   // rolled to the bottom half
        #expect(f.game.outs == 0)              // fresh half-inning
    }
}
