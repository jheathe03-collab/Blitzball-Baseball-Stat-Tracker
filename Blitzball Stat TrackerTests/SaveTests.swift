//
//  SaveTests.swift
//  Blitzball Stat TrackerTests
//
//  Tier 3 pitching decisions: Saves (awarded at game end to the winning team's finishing reliever) and
//  Blown Saves (charged live when a reliever protecting a save-able lead lets the tying run score). The
//  save-situation lead window is 1…5 for blitzball.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct SaveTests {

    /// A game with one reliever on `isHome`'s mound, the score set, and that side's save-entry context
    /// primed — enough to exercise `awardSaves` / `checkBlownSaveOnRun` directly.
    private func makeGame(relieverIsHome: Bool,
                          homeScore: Int, awayScore: Int, isTopInning: Bool,
                          entryLead: Int, entryOuts: Int = 0, blownCharged: Bool = false,
                          relieverOuts: Int = 3, relieverIsStarter: Bool = false) -> (game: Game, line: GameStatLine) {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.status = .inProgress
        game.currentInning = 7
        game.isTopInning = isTopInning
        game.homeInningRuns = [homeScore]   // sum is the score; that's all these checks read
        game.awayInningRuns = [awayScore]

        let reliever = Player(name: "Closer")
        let line = GameStatLine(player: reliever, isHome: relieverIsHome, battingOrder: 0)
        line.game = game
        line.isStarter = relieverIsStarter
        line.pitching = PitchingStats(outsRecorded: relieverOuts)
        game.statLines = [line]
        if relieverIsHome { game.homePitcher = reliever } else { game.awayPitcher = reliever }

        if relieverIsHome {
            game.homeSaveEntryLead = entryLead; game.homeSaveEntryOuts = entryOuts
            game.homeBlownSaveCharged = blownCharged
        } else {
            game.awaySaveEntryLead = entryLead; game.awaySaveEntryOuts = entryOuts
            game.awayBlownSaveCharged = blownCharged
        }
        return (game, line)
    }

    // MARK: - Saves

    /// The winning team's finishing reliever, who came in protecting a save-able lead and held it,
    /// earns the save. (Away leads; last half was the bottom, so away was fielding = the finisher.)
    @Test func finishingRelieverHoldingALeadGetsTheSave() {
        let f = makeGame(relieverIsHome: false, homeScore: 3, awayScore: 5, isTopInning: false,
                         entryLead: 2)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 1)
    }

    /// A walk-off (the batting team wins) leaves the fielding finisher on the losing side — no save.
    @Test func walkOffYieldsNoSave() {
        let f = makeGame(relieverIsHome: false, homeScore: 6, awayScore: 5, isTopInning: false,
                         entryLead: 2)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 0)
    }

    /// The starter never earns a save, even finishing a win he was protecting.
    @Test func aStarterNeverGetsASave() {
        let f = makeGame(relieverIsHome: false, homeScore: 3, awayScore: 5, isTopInning: false,
                         entryLead: 2, relieverIsStarter: true)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 0)
    }

    /// A reliever who blew the lead on this outing can't also earn the save.
    @Test func blowingTheLeadForfeitsTheSave() {
        let f = makeGame(relieverIsHome: false, homeScore: 3, awayScore: 5, isTopInning: false,
                         entryLead: 2, blownCharged: true)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 0)
    }

    /// A 6-run lead is outside the 1…5 window, but three innings (9 outs) earns the long save.
    @Test func longSaveOnThreeInningsEvenOutsideTheLeadWindow() {
        let f = makeGame(relieverIsHome: false, homeScore: 1, awayScore: 7, isTopInning: false,
                         entryLead: 6, entryOuts: 0, relieverOuts: 9)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 1)
    }

    /// Coming in with a 6-run lead and recording only two innings is neither a save situation nor a
    /// long save — no save.
    @Test func bigLeadShortOutingIsNoSave() {
        let f = makeGame(relieverIsHome: false, homeScore: 1, awayScore: 7, isTopInning: false,
                         entryLead: 6, entryOuts: 0, relieverOuts: 6)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 0)
    }

    /// A five-run lead is still a save situation (the widened blitzball window).
    @Test func fiveRunLeadIsStillASaveSituation() {
        let f = makeGame(relieverIsHome: false, homeScore: 2, awayScore: 7, isTopInning: false,
                         entryLead: 5)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 1)
    }

    /// A tie game is never a save.
    @Test func tieGameIsNoSave() {
        let f = makeGame(relieverIsHome: false, homeScore: 4, awayScore: 4, isTopInning: false,
                         entryLead: 2)
        f.game.awardSaves()
        #expect(f.line.pitching.saves == 0)
    }

    // MARK: - Blown saves

    /// Home reliever entered up 2 (a save situation); the away team's run just tied it → a blown save.
    /// (Top of the inning: away bats, home fields, so home is the pitcher of record.)
    @Test func tyingRunAgainstASaveSituationIsABlownSave() {
        let f = makeGame(relieverIsHome: true, homeScore: 3, awayScore: 3, isTopInning: true,
                         entryLead: 2)
        f.game.checkBlownSaveOnRun()
        #expect(f.line.pitching.blownSaves == 1)
    }

    /// The lead was erased, but he entered up 8 (never a save situation) → no blown save.
    @Test func erasingANonSaveLeadIsNotABlownSave() {
        let f = makeGame(relieverIsHome: true, homeScore: 3, awayScore: 3, isTopInning: true,
                         entryLead: 8)
        f.game.checkBlownSaveOnRun()
        #expect(f.line.pitching.blownSaves == 0)
    }

    /// Only one blown save per stint, even if called again while still tied.
    @Test func blownSaveIsChargedOncePerStint() {
        let f = makeGame(relieverIsHome: true, homeScore: 3, awayScore: 3, isTopInning: true,
                         entryLead: 2)
        f.game.checkBlownSaveOnRun()
        f.game.checkBlownSaveOnRun()
        #expect(f.line.pitching.blownSaves == 1)
        #expect(f.game.homeBlownSaveCharged == true)
    }

    /// While still leading (down to +1, not tied), no blown save yet.
    @Test func stillLeadingIsNotABlownSave() {
        let f = makeGame(relieverIsHome: true, homeScore: 4, awayScore: 3, isTopInning: true,
                         entryLead: 2)
        f.game.checkBlownSaveOnRun()
        #expect(f.line.pitching.blownSaves == 0)
    }
}
