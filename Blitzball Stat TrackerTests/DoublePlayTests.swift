//
//  DoublePlayTests.swift
//  Blitzball Stat TrackerTests
//
//  Game.recordDoublePlay: the batter is out (an at-bat, no hit) and one runner is doubled off, for
//  two outs on the play — which can end the half-inning. Only the chosen runner is removed.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct DoublePlayTests {

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

    @Test func batterAndRunnerAreOutForTwo() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)

        f.game.recordDoublePlay(secondOutBase: 0)

        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.game.outs == 2)
        #expect(f.pitcherLine.pitching.outsRecorded == 2)
        #expect(f.game.runner(onBase: 0) == nil)          // the doubled runner is gone
    }

    @Test func aDoublePlayCanEndTheHalfInning() {
        let f = makeFixture()
        f.game.outs = 1
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)

        f.game.recordDoublePlay(secondOutBase: 0)

        #expect(f.game.isTopInning == false)   // 1 + 2 = 3 outs → rolled to the bottom
        #expect(f.game.outs == 0)
    }

    /// The "outs" beat of the staged ground-ball double play: after the runner and batter have moved
    /// to their bags, they're cleared and the two outs recorded — same end state as the direct path.
    @Test func groundBallDoublePlayOutsBeatClearsBothForTwo() {
        let f = makeFixture()
        let batter = f.batterLine.player!
        // Simulate the "run" beat: forced runner on 2nd, batter on 1st.
        f.game.setRunner(Player(name: "Rudy"), onBase: 1)
        f.game.setRunner(batter, onBase: 0)

        f.game.finishGroundBallDoublePlay(batterLine: f.batterLine, runnerBase: 1, batterBase: 0)

        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.game.outs == 2)
        #expect(f.pitcherLine.pitching.outsRecorded == 2)
        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1) == nil)
    }

    @Test func onlyTheChosenRunnerIsRemoved() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)
        f.game.setRunner(Player(name: "Theo"), onBase: 2)

        f.game.recordDoublePlay(secondOutBase: 0)

        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 2)?.name == "Theo")   // the runner on third holds
        #expect(f.game.outs == 2)
    }

    /// The 2nd-and-3rd forced double play, resolved OUT: batter out at first, the lead runner (from
    /// third) is out at home (no run), and the trailing runner holds third — two outs.
    @Test func secondThirdDoublePlayOutAtHomeHoldsTrailingRunner() {
        let f = makeFixture()
        let r2 = Player(name: "Rudy"), r3 = Player(name: "Theo")
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2)], outIndex: 0)

        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.game.outs == 2)
        #expect(f.pitcherLine.pitching.outsRecorded == 2)
        #expect(f.game.runner(onBase: 2)?.name == "Rudy")   // trailing runner holds third
        #expect(f.game.runner(onBase: 1) == nil)
        #expect(f.game.awayScore == 0)                       // lead runner out at home — no run
    }

    /// The 2nd-and-3rd forced double play, resolved SAFE: the run counts, the trailing runner is the
    /// second out, and the bases end empty.
    @Test func secondThirdDoublePlaySafeScoresRunAndEmptiesBases() {
        let f = makeFixture()
        let r2 = Player(name: "Rudy"), r3 = Player(name: "Theo")
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2)], outIndex: 1)

        #expect(f.game.outs == 2)
        #expect(f.pitcherLine.pitching.outsRecorded == 2)
        #expect(f.game.awayScore == 1)                       // the run counts
        #expect(f.game.runner(onBase: 1) == nil)             // bases empty
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// The 1st-and-2nd forced double play, OUT at third: batter out at first, the lead runner (from
    /// second) is out at third, and the runner from first holds second. No run — nobody reached home.
    @Test func firstSecondDoublePlayOutAtThirdHoldsRunnerAtSecond() {
        let f = makeFixture()
        let r1 = Player(name: "Rudy"), r2 = Player(name: "Theo")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(1, r2), (0, r1)], outIndex: 0)

        #expect(f.game.outs == 2)
        #expect(f.game.runner(onBase: 1)?.name == "Rudy")   // runner from first holds second
        #expect(f.game.runner(onBase: 2) == nil)            // lead runner out at third
        #expect(f.game.awayScore == 0)
    }

    /// The 1st-and-2nd forced double play, SAFE at third: the lead holds third, the runner from first
    /// is the second out at second, and no run scores.
    @Test func firstSecondDoublePlaySafeAtThirdRetiresTrailer() {
        let f = makeFixture()
        let r1 = Player(name: "Rudy"), r2 = Player(name: "Theo")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(1, r2), (0, r1)], outIndex: 1)

        #expect(f.game.outs == 2)
        #expect(f.game.runner(onBase: 2)?.name == "Theo")   // lead safe at third
        #expect(f.game.runner(onBase: 1) == nil)            // runner from first out at second
        #expect(f.game.awayScore == 0)                       // nobody reached home
    }

    /// Bases loaded, SAFE at the plate then the user marks the runner who went to THIRD out: the lead
    /// scores, that runner (from second) is the second out, and the runner from first holds second.
    @Test func basesLoadedDoublePlaySafeThenRunnerAtThirdOut() {
        let f = makeFixture()
        let r1 = Player(name: "Al"), r2 = Player(name: "Bo"), r3 = Player(name: "Cy")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2), (0, r1)], outIndex: 1)

        #expect(f.game.outs == 2)
        #expect(f.game.awayScore == 1)                       // lead scores
        #expect(f.game.runner(onBase: 1)?.name == "Al")     // runner from first holds second
        #expect(f.game.runner(onBase: 2) == nil)            // runner who went to third is the second out
    }

    /// Bases loaded, SAFE at the plate then the user marks the runner who went to SECOND out: the lead
    /// scores, that runner (from first) is the second out, and the runner from second holds third.
    @Test func basesLoadedDoublePlaySafeThenRunnerAtSecondOut() {
        let f = makeFixture()
        let r1 = Player(name: "Al"), r2 = Player(name: "Bo"), r3 = Player(name: "Cy")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2), (0, r1)], outIndex: 2)

        #expect(f.game.outs == 2)
        #expect(f.game.awayScore == 1)                       // lead scores
        #expect(f.game.runner(onBase: 2)?.name == "Bo")     // runner from second holds third
        #expect(f.game.runner(onBase: 1) == nil)            // runner who went to second is the second out
    }

    /// Bases loaded, OUT at the plate: the lead is out at home (no run), and both trailing runners hold
    /// their new bases (second and third).
    @Test func basesLoadedDoublePlayOutAtHomeHoldsBothTrailers() {
        let f = makeFixture()
        let r1 = Player(name: "Al"), r2 = Player(name: "Bo"), r3 = Player(name: "Cy")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2), (0, r1)], outIndex: 0)

        #expect(f.game.outs == 2)
        #expect(f.game.awayScore == 0)                       // lead out at home — no run
        #expect(f.game.runner(onBase: 1)?.name == "Al")     // from first → second
        #expect(f.game.runner(onBase: 2)?.name == "Bo")     // from second → third
    }
}
