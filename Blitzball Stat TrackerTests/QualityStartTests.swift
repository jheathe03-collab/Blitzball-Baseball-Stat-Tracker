//
//  QualityStartTests.swift
//  Blitzball Stat TrackerTests
//
//  Tier 2 pitching decisions: Quality Starts auto-awarded at game end. The innings bar scales to the
//  game's length (about two-thirds of regulation), paired with the classic ≤3 earned-runs cap, and
//  only the starter can earn one.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct QualityStartTests {

    /// The innings bar scales with game length: 6 IP for 9-inning baseball, 5 IP for 7-inning blitzball.
    @Test func thresholdScalesToGameLength() {
        #expect(GameSettings.baseballDefaults.qualityStartOutsThreshold == 18)   // 6 IP × 3 outs
        #expect(GameSettings.blitzballDefaults.qualityStartOutsThreshold == 15)  // 5 IP × 3 outs
    }

    private func makeStarter(settings: GameSettings, outs: Int, earnedRuns: Int,
                             isStarter: Bool = true) -> (game: Game, line: GameStatLine) {
        let game = Game(homeTeam: Team(name: "Sluggers"), awayTeam: Team(name: "Mashers"))
        game.settings = settings
        let line = GameStatLine(player: Player(name: "Ace"), isHome: true, battingOrder: 0)
        line.game = game
        line.isStarter = isStarter
        line.pitching = PitchingStats(outsRecorded: outs, earnedRuns: earnedRuns)
        game.statLines = [line]
        return (game, line)
    }

    /// Blitzball: a starter who goes 5 innings (15 outs) with 3 earned runs clears the scaled bar.
    @Test func blitzballFiveInningsThreeEarnedIsAQS() {
        let f = makeStarter(settings: .blitzballDefaults, outs: 15, earnedRuns: 3)
        f.game.awardQualityStarts()
        #expect(f.line.pitching.qualityStarts == 1)
    }

    /// One out short of the blitzball bar (14 outs) is not a QS, however few runs he allowed.
    @Test func justShortOfTheInningsBarIsNoQS() {
        let f = makeStarter(settings: .blitzballDefaults, outs: 14, earnedRuns: 0)
        f.game.awardQualityStarts()
        #expect(f.line.pitching.qualityStarts == 0)
    }

    /// A fourth earned run disqualifies a QS even on a deep outing.
    @Test func fourEarnedRunsIsNoQS() {
        let f = makeStarter(settings: .baseballDefaults, outs: 21, earnedRuns: 4)   // 7 IP, 4 ER
        f.game.awardQualityStarts()
        #expect(f.line.pitching.qualityStarts == 0)
    }

    /// A reliever never earns a QS, no matter how long he goes.
    @Test func aRelieverNeverEarnsAQS() {
        let f = makeStarter(settings: .baseballDefaults, outs: 24, earnedRuns: 0, isStarter: false)
        f.game.awardQualityStarts()
        #expect(f.line.pitching.qualityStarts == 0)
    }

    /// `finalize()` awards the QS and marks the game final — and calling it again never double-counts.
    @Test func finalizeAwardsOnceAndMarksFinal() {
        let f = makeStarter(settings: .baseballDefaults, outs: 18, earnedRuns: 3)   // 6 IP, 3 ER
        f.game.finalize()
        #expect(f.game.status == .final)
        #expect(f.game.pitchingDecisionsRecorded == true)
        #expect(f.line.pitching.qualityStarts == 1)

        f.game.finalize()
        #expect(f.line.pitching.qualityStarts == 1)   // still one — no double-count
    }
}
