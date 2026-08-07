//
//  TriplePlayTests.swift
//  Blitzball Stat TrackerTests
//
//  Game.finishTriplePlay: the batter and two forced runners are all out for three outs on one batted
//  ball. Every out is a force, so no run scores and the bases clear — it ends the half-inning under the
//  standard three-out rule.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct TriplePlayTests {

    private struct Fixture {
        let game: Game
        let batterLine: GameStatLine
        let pitcherLine: GameStatLine
    }

    /// Top of the 1st: away bats, home pitches.
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

    /// Runners on first and second: the batter and both runners are out for three, the bases clear, no
    /// run scores, and the half-inning ends.
    @Test func firstAndSecondClearsForThreeAndEndsInning() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)
        f.game.setRunner(Player(name: "Theo"), onBase: 1)

        f.game.finishTriplePlay(batterLine: f.batterLine)

        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.game.outs == 0)                 // 0 + 3 = 3 → rolled to the next half
        #expect(f.game.isTopInning == false)
        #expect(f.game.awayScore == 0)            // no run on a force triple play
        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1) == nil)
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// Bases loaded: still exactly three outs and no runs — the runner from third never scores (a run
    /// can't count when the third out is a force).
    @Test func basesLoadedScoresNoRunsAndClears() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Al"), onBase: 0)
        f.game.setRunner(Player(name: "Bo"), onBase: 1)
        f.game.setRunner(Player(name: "Cy"), onBase: 2)

        f.game.finishTriplePlay(batterLine: f.batterLine)

        #expect(f.game.outs == 0)                 // 0 + 3 = 3 → half-inning over
        #expect(f.game.isTopInning == false)
        #expect(f.game.awayScore == 0)            // the runner from third does not score
        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1) == nil)
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// The pitcher is charged all three outs.
    @Test func pitcherIsChargedThreeOuts() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)
        f.game.setRunner(Player(name: "Theo"), onBase: 1)

        f.game.finishTriplePlay(batterLine: f.batterLine)

        #expect(f.pitcherLine.pitching.outsRecorded == 3)   // batter + two runners, all charged
    }
}
