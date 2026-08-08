//
//  ThirdOutTimingTests.swift
//  Blitzball Stat TrackerTests
//
//  MLB rule 5.08(a): no run scores when a play's inning-ending third out is a force out or the
//  batter-runner is retired before reaching first base. The multi-out finishers score a forced/
//  driven-in run BEFORE the out count is applied, so each must void that run when the play makes
//  the third out. The happy-path (fewer than two outs) versions live in DoublePlayTests /
//  OutAtFirstTests; these cover only the third-out boundary those files never exercise.
//
//  Models are built standalone (no ModelContainer — the app-hosted test bundle can't create one).
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct ThirdOutTimingTests {

    private struct Fixture {
        let game: Game
        let batterLine: GameStatLine
        let pitcherLine: GameStatLine
    }

    /// Top of the 1st: away bats, home pitches. Default rules ⇒ three outs per half-inning.
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

    /// Bases loaded, ONE out. A forced double play (batter out at first + the runner from second)
    /// makes the second and third outs. The runner from third is forced home, but 5.08(a) voids that
    /// run because the inning-ending out is a force. (With zero outs the same play DOES score it —
    /// see DoublePlayTests.basesLoadedDoublePlaySafeThenRunnerAtSecondOut.)
    @Test func forcedDoublePlayForTheThirdOutVoidsTheForcedRun() {
        let f = makeFixture()
        f.game.outs = 1
        let r1 = Player(name: "Al"), r2 = Player(name: "Bo"), r3 = Player(name: "Cy")
        f.game.setRunner(r1, onBase: 0)
        f.game.setRunner(r2, onBase: 1)
        f.game.setRunner(r3, onBase: 2)

        f.game.finishForcedDoublePlay(batterLine: f.batterLine,
                                      runnersLeadFirst: [(2, r3), (1, r2), (0, r1)], outIndex: 1)

        #expect(f.game.awayScore == 0)                       // forced run on the 3rd out does not count
        #expect(f.pitcherLine.pitching.earnedRuns == 0)
    }

    /// Runner on third, TWO outs. The batter is thrown out at first for the third out. Even though the
    /// runner "beat the throw" home (Safe), 5.08(a)(1) — the batter-runner retired before first — voids
    /// the run. (With zero outs the run counts — see OutAtFirstTests.runnerHomeSafeScoresWithRBI.)
    @Test func outAtFirstForTheThirdOutVoidsTheRunFromThird() {
        let f = makeFixture()
        f.game.outs = 2
        f.game.setRunner(Player(name: "Cy"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: true)

        #expect(f.game.awayScore == 0)                       // no run on the batter's out at first
        #expect(f.batterLine.batting.rbi == 0)               // and no phantom RBI
        #expect(f.pitcherLine.pitching.earnedRuns == 0)
    }

    /// Guard rail: the same out-at-first with fewer than two outs still scores the run, so the fix
    /// didn't over-suppress. (Mirrors OutAtFirstTests but kept here next to the boundary case.)
    @Test func outAtFirstWithOneOutStillScoresTheRunFromThird() {
        let f = makeFixture()
        f.game.outs = 1
        f.game.setRunner(Player(name: "Cy"), onBase: 2)

        f.game.finishOutAtFirst(batterLine: f.batterLine, runnerHomeSafe: true)

        #expect(f.game.awayScore == 1)                       // batter out is only the 2nd out — run counts
        #expect(f.batterLine.batting.rbi == 1)
    }
}
