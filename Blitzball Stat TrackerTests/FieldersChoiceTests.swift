//
//  FieldersChoiceTests.swift
//  Blitzball Stat TrackerTests
//
//  A fielder's choice: the batter reaches (an at-bat, no hit — so it drags AVG and OBP), the defense
//  plays on a runner, and if that runner is retired it's a real out. These cover the runner logic
//  (removed if out, forced along if safe) and the batter's stat treatment.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct FieldersChoiceTests {

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

    /// Runner on first, played on and OUT: he's removed, the out is recorded (and charged to the
    /// pitcher), the batter takes first — an at-bat with no hit, so his AVG and OBP both drop.
    @Test func runnerOutRemovesHimAndRecordsTheOut() {
        let f = makeFixture()
        let runner = Player(name: "Rudy")
        f.game.setRunner(runner, onBase: 0)

        f.game.recordFieldersChoice(.fieldersChoice, playedOnBase: 0, runnerOut: true)

        #expect(f.batterLine.batting.plateAppearances == 1)
        #expect(f.batterLine.batting.atBats == 1)
        #expect(f.batterLine.batting.hits == 0)
        #expect(f.batterLine.batting.battingAverage == 0)
        #expect(f.batterLine.batting.onBasePercentage == 0)   // 0 on-base / 1 AB

        #expect(f.game.outs == 1)
        #expect(f.pitcherLine.pitching.outsRecorded == 1)
        #expect(f.pitcherLine.pitching.atBatsAgainst == 1)

        #expect(f.game.runner(onBase: 0)?.name == "Sam")      // batter on first
        #expect(f.game.runner(onBase: 1) == nil)              // retired runner is gone
        #expect(f.game.runner(onBase: 2) == nil)
    }

    /// Runner on first, played on but SAFE: no out, and the batter taking first forces the runner on
    /// to second (they can't share the bag).
    @Test func runnerSafeIsForcedAlongWithNoOut() {
        let f = makeFixture()
        let runner = Player(name: "Rudy")
        f.game.setRunner(runner, onBase: 0)

        f.game.recordFieldersChoice(.fieldersChoice, playedOnBase: 0, runnerOut: false)

        #expect(f.game.outs == 0)
        #expect(f.game.runner(onBase: 0)?.name == "Sam")      // batter on first
        #expect(f.game.runner(onBase: 1)?.name == "Rudy")     // runner forced to second
    }

    /// Runners on the corners; the defense forces the trailing runner (first) and gets him. The lead
    /// runner on third is untouched — the whole point of asking which runner was played on.
    @Test func onlyThePlayedOnRunnerIsAffected() {
        let f = makeFixture()
        let onFirst = Player(name: "Rudy")
        let onThird = Player(name: "Theo")
        f.game.setRunner(onFirst, onBase: 0)
        f.game.setRunner(onThird, onBase: 2)

        f.game.recordFieldersChoice(.fieldersChoice, playedOnBase: 0, runnerOut: true)

        #expect(f.game.outs == 1)
        #expect(f.game.runner(onBase: 0)?.name == "Sam")      // batter on first
        #expect(f.game.runner(onBase: 1) == nil)
        #expect(f.game.runner(onBase: 2)?.name == "Theo")     // lead runner holds on third
    }
}
