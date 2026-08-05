//
//  SacrificeFlyTests.swift
//  Blitzball Stat TrackerTests
//
//  A sacrifice fly is an out that scores the runner from third: the batter is charged a plate
//  appearance but NOT an at-bat, gets the RBI, and the run is charged to the pitcher. These cover the
//  full recording path through `Game.record(.sacrificeFly)` plus the OBP-denominator rule.
//
//  Models are built standalone (no ModelContainer — the app-hosted test bundle can't create one),
//  with the relationship arrays set explicitly, same as InheritedRunnerTests.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct SacrificeFlyTests {

    private struct Fixture {
        let game: Game
        let batterLine: GameStatLine
        let runnerLine: GameStatLine
        let pitcherLine: GameStatLine
    }

    /// Top of the 1st: away team bats, home pitches. A runner is standing on third.
    private func makeFixture() -> Fixture {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true          // away bats ⇒ home pitches
        game.homeInningRuns = [0]
        game.awayInningRuns = [0]
        game.outs = 0

        let batter = Player(name: "Sam")
        let runner = Player(name: "Rudy")
        let pitcher = Player(name: "Darrin")

        let batterLine = GameStatLine(player: batter, isHome: false, battingOrder: 0)
        let runnerLine = GameStatLine(player: runner, isHome: false, battingOrder: 1)
        let pitcherLine = GameStatLine(player: pitcher, isHome: true, battingOrder: 0)
        for line in [batterLine, runnerLine, pitcherLine] { line.game = game }
        game.statLines = [batterLine, runnerLine, pitcherLine]

        game.homePitcher = pitcher
        game.setRunner(runner, onBase: 2)   // runner on third, ready to tag
        return Fixture(game: game, batterLine: batterLine, runnerLine: runnerLine, pitcherLine: pitcherLine)
    }

    /// The whole play: out recorded, run scored from third, RBI to the batter, no at-bat charged, and
    /// the run (earned) charged to the pitcher.
    @Test func sacrificeFlyScoresTheRunnerWithoutChargingAnAtBat() throws {
        let f = makeFixture()

        f.game.record(.sacrificeFly)

        // Batter: a plate appearance and an SF, but no at-bat and no hit; credited the RBI.
        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.batterLine.batting.atBats == 0)
        #expect(f.batterLine.batting.sacrificeFlies == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.batterLine.batting.rbi == 1)

        // The out was recorded and the runner scored from third (base now empty).
        #expect(f.game.outs == 1)
        #expect(f.game.awayScore == 1)
        #expect(f.runnerLine.batting.runsScored == 1)
        #expect(f.game.runner(onBase: 2) == nil)

        // Pitcher: an out, an (earned) run allowed, but not an at-bat against.
        #expect(f.pitcherLine.pitching.outsRecorded == 1)
        #expect(f.pitcherLine.pitching.atBatsAgainst == 0)
        #expect(f.pitcherLine.pitching.runsAllowed == 1)
        #expect(f.pitcherLine.pitching.earnedRuns == 1)
    }

    /// A sac fly is not an at-bat, so it leaves batting average alone — but it DOES sit in the OBP
    /// denominator, which is what separates it from a walk.
    @Test func sacrificeFlyLiftsOnBaseDenominatorButNotAverage() {
        // 1 hit, 2 at-bats, 1 sac fly.
        let line = BattingStats(atBats: 2, hits: 1, sacrificeFlies: 1)
        #expect(line.battingAverage == 0.5)                       // 1 / 2 — SF ignored
        #expect(line.onBasePercentage == 1.0 / 3.0)              // 1 / (2 + 1) — SF counts
    }
}
