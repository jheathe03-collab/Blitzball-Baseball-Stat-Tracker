//
//  InheritedRunnerTests.swift
//  Blitzball Stat TrackerTests
//
//  A relief pitcher is never charged with a run scored by a runner who was already on base when he
//  entered (MLB 9.16). These cover the charge path end to end: who gets billed, the fallback when a
//  runner isn't on anyone's tab, the pinch-runner handoff, and the half-inning reset.
//
//  Models are built standalone (no ModelContainer — the app-hosted test bundle can't create one),
//  with relationship arrays set explicitly rather than relying on inverse propagation.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct InheritedRunnerTests {

    /// Top of the 1st: away team batting, so the HOME pitcher is on the mound.
    private struct Fixture {
        let game: Game
        let starter: Player
        let reliever: Player
        let starterLine: GameStatLine
        let relieverLine: GameStatLine
        let runner: Player
    }

    private func makeFixture() -> Fixture {
        let home = Team(name: "Sluggers")
        let away = Team(name: "Mashers")
        let game = Game(homeTeam: home, awayTeam: away)
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true          // away bats ⇒ home pitches
        game.homeInningRuns = [0]
        game.awayInningRuns = [0]

        let starter = Player(name: "Darrin")
        let reliever = Player(name: "Kelsie")
        let runner = Player(name: "Sam")

        // Pitchers field for the home side; the runner bats for the away side.
        let starterLine = GameStatLine(player: starter, isHome: true, battingOrder: 0)
        let relieverLine = GameStatLine(player: reliever, isHome: true, battingOrder: 1)
        let runnerLine = GameStatLine(player: runner, isHome: false, battingOrder: 0)
        for line in [starterLine, relieverLine, runnerLine] { line.game = game }
        game.statLines = [starterLine, relieverLine, runnerLine]

        game.homePitcher = starter
        return Fixture(game: game, starter: starter, reliever: reliever,
                       starterLine: starterLine, relieverLine: relieverLine, runner: runner)
    }

    /// The whole point: the starter puts a runner on, the reliever takes over, the runner scores —
    /// the run belongs to the starter.
    @Test func inheritedRunnerIsChargedToThePitcherWhoPutHimOn() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)          // starter is pitching ⇒ Sam is on his tab
        f.game.homePitcher = f.reliever                // pitching change

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.starterLine.pitching.runsAllowed == 1)
        #expect(f.starterLine.pitching.earnedRuns == 1)
        #expect(f.relieverLine.pitching.runsAllowed == 0)
        #expect(f.relieverLine.pitching.earnedRuns == 0)
    }

    /// No pitching change: the run just goes to the pitcher on the mound, and nothing is flagged
    /// for confirmation.
    @Test func ownRunnerIsChargedToTheCurrentPitcher() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.starterLine.pitching.runsAllowed == 1)
        #expect(f.game.lastPlayInheritedCharges.isEmpty)
    }

    /// A runner nobody is on the hook for (e.g. placed before this rule existed) falls back to the
    /// current pitcher rather than losing the run.
    @Test func unmappedRunnerFallsBackToCurrentPitcher() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        f.game.runnerResponsibility = [:]              // wipe the tab
        f.game.homePitcher = f.reliever

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.relieverLine.pitching.runsAllowed == 1)
        #expect(f.starterLine.pitching.runsAllowed == 0)
    }

    /// An inherited run is reported so the live screen can confirm it; an own run is not.
    @Test func inheritedRunIsFlaggedForConfirmation() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        f.game.homePitcher = f.reliever

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.game.lastPlayInheritedCharges.count == 1)
        #expect(f.game.lastPlayInheritedCharges.first?.runner == "Sam")
        #expect(f.game.lastPlayInheritedCharges.first?.chargedTo == "Darrin")
    }

    /// Overriding moves the run off the inherited pitcher and onto the current one.
    @Test func reassigningMovesTheRunToTheCurrentPitcher() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        f.game.homePitcher = f.reliever
        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        let charge = try #require(f.game.lastPlayInheritedCharges.first)
        f.game.reassignInheritedCharge(charge)

        #expect(f.starterLine.pitching.runsAllowed == 0)
        #expect(f.starterLine.pitching.earnedRuns == 0)
        #expect(f.relieverLine.pitching.runsAllowed == 1)
        #expect(f.relieverLine.pitching.earnedRuns == 1)
    }

    /// Two of the starter's runners plus one of the reliever's: 2 runs to the starter, 1 to the
    /// reliever — the split a bases-clearing hit produces.
    @Test func mixedRunnersSplitBetweenBothPitchers() throws {
        let f = makeFixture()
        let second = Player(name: "Ian")
        let third = Player(name: "Nevin")
        for p in [second, third] {
            let line = GameStatLine(player: p, isHome: false, battingOrder: 1)
            line.game = f.game
            f.game.statLines.append(line)
        }

        f.game.setRunner(f.runner, onBase: 0)          // starter's
        f.game.setRunner(second, onBase: 1)            // starter's
        f.game.homePitcher = f.reliever                // pitching change
        f.game.setRunner(third, onBase: 2)             // reliever's own

        f.game.scoreRunner(onBase: 0, rbiTo: nil)
        f.game.scoreRunner(onBase: 1, rbiTo: nil)
        f.game.scoreRunner(onBase: 2, rbiTo: nil)

        #expect(f.starterLine.pitching.runsAllowed == 2)
        #expect(f.relieverLine.pitching.runsAllowed == 1)
    }

    /// A pinch runner takes over the base — and the tab. The starter still owns the run.
    @Test func pinchRunnerInheritsTheResponsibility() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        let pinch = Player(name: "Jordan")
        let pinchLine = GameStatLine(player: pinch, isHome: false, battingOrder: 2)
        pinchLine.game = f.game
        f.game.statLines.append(pinchLine)

        f.game.transferResponsibility(from: f.runner, to: pinch)
        f.game.setRunner(pinch, onBase: 0)
        f.game.homePitcher = f.reliever

        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.starterLine.pitching.runsAllowed == 1)
        #expect(f.relieverLine.pitching.runsAllowed == 0)
    }

    /// Nobody is left on base at the end of a half-inning, so no pitcher stays on the hook.
    @Test func halfInningClearsResponsibility() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        #expect(f.game.runnerResponsibility["Sam"] == "Darrin")

        f.game.advanceHalfInning()

        #expect(f.game.runnerResponsibility.isEmpty)
    }

    /// Scoring clears the runner's tab, so a second trip on base the same inning is charged to
    /// whoever is pitching then.
    @Test func secondTripOnBaseIsChargedAfresh() throws {
        let f = makeFixture()
        f.game.setRunner(f.runner, onBase: 0)
        f.game.scoreRunner(onBase: 0, rbiTo: nil)      // charged to the starter
        f.game.homePitcher = f.reliever
        f.game.setRunner(f.runner, onBase: 0)          // reaches base again, new pitcher
        f.game.scoreRunner(onBase: 0, rbiTo: nil)

        #expect(f.starterLine.pitching.runsAllowed == 1)
        #expect(f.relieverLine.pitching.runsAllowed == 1)
    }
}
