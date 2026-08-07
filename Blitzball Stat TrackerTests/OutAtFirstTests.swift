//
//  OutAtFirstTests.swift
//  Blitzball Stat TrackerTests
//
//  Game.finishOutAtFirst: a ground ball where the batter is out at first and every runner advances
//  one base. A runner coming home from third is resolved Safe (the run counts, RBI to the batter) or
//  Out (a second out at the plate, no run).
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct OutAtFirstTests {

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

    /// Runner on first only: the batter is out at first (one out) and the runner advances to second.
    @Test func runnerOnFirstAdvancesToSecond() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: nil)

        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.game.outs == 1)
        #expect(f.pitcherLine.pitching.outsRecorded == 1)
        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1)?.name == "Rudy")   // 1st → 2nd
    }

    /// Runners on first and second: both advance a base, the batter is out at first.
    @Test func runnersOnFirstAndSecondEachAdvance() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Rudy"), onBase: 0)
        f.game.setRunner(Player(name: "Theo"), onBase: 1)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: nil)

        #expect(f.game.outs == 1)
        #expect(f.game.runner(onBase: 0) == nil)
        #expect(f.game.runner(onBase: 1)?.name == "Rudy")   // 1st → 2nd
        #expect(f.game.runner(onBase: 2)?.name == "Theo")   // 2nd → 3rd
        #expect(f.game.awayScore == 0)
    }

    /// Runner on third, ruled SAFE at home: the run scores (RBI to the batter), the batter is the lone
    /// out, and the bases end empty.
    @Test func runnerHomeSafeScoresWithRBI() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Theo"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: true)

        #expect(f.game.outs == 1)                            // only the batter
        #expect(f.pitcherLine.pitching.outsRecorded == 1)
        #expect(f.game.awayScore == 1)                       // the run counts
        #expect(f.batterLine.batting.rbi == 1)               // credited to the batter
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// Runner on third, ruled OUT at home: no run, and it's a second out on the play (batter + runner).
    @Test func runnerHomeOutIsASecondOut() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Theo"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: false)

        #expect(f.game.outs == 2)                            // batter + runner thrown out at home
        #expect(f.pitcherLine.pitching.outsRecorded == 2)
        #expect(f.game.awayScore == 0)                       // no run
        #expect(f.batterLine.batting.rbi == 0)
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// Bases loaded, SAFE at home: the run scores and the two trailing runners move up a base.
    @Test func basesLoadedSafeScoresAndAdvancesTrailers() {
        let f = makeFixture()
        f.game.setRunner(Player(name: "Al"), onBase: 0)
        f.game.setRunner(Player(name: "Bo"), onBase: 1)
        f.game.setRunner(Player(name: "Cy"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: true)

        #expect(f.game.outs == 1)
        #expect(f.game.awayScore == 1)                       // Cy scores from third
        #expect(f.batterLine.batting.rbi == 1)
        #expect(f.game.runner(onBase: 2)?.name == "Bo")      // 2nd → 3rd
        #expect(f.game.runner(onBase: 1)?.name == "Al")      // 1st → 2nd
        #expect(f.game.runner(onBase: 0) == nil)
    }

    /// An out at home can be the third out that ends the half-inning.
    @Test func runnerHomeOutCanEndTheHalfInning() {
        let f = makeFixture()
        f.game.outs = 1
        f.game.setRunner(Player(name: "Theo"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: false)

        #expect(f.game.isTopInning == false)                 // 1 + 2 = 3 outs → rolled to the bottom
        #expect(f.game.outs == 0)
        #expect(f.game.awayScore == 0)
    }
}
