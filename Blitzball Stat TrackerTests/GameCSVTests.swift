//
//  GameCSVTests.swift
//  Blitzball Stat TrackerTests
//
//  Covers the single-game box-score CSV: both teams appear, per-team totals add up, and the line
//  score renders innings/R/H. Models are built standalone (no ModelContainer — the app-hosted test
//  bundle can't create one), which is fine because gameCSV only reads already-set properties.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct GameCSVTests {

    /// A finished 2-inning game: Away (Mashers) 3, Home (Sluggers) 1, with one batter each side.
    private func makeGame() -> Game {
        let home = Team(name: "Sluggers")
        let away = Team(name: "Mashers")
        let game = Game(homeTeam: home, awayTeam: away)
        game.mode = .exhibition
        game.status = .final
        game.awayInningRuns = [2, 1]
        game.homeInningRuns = [1, 0]

        let mike = Player(name: "Mike")     // home
        let sam = Player(name: "Sam")       // away

        let homeLine = GameStatLine(
            player: mike, isHome: true, battingOrder: 0,
            batting: BattingStats(plateAppearances: 3, atBats: 3, hits: 1),
            pitching: PitchingStats(outsRecorded: 6, strikeouts: 4, strikeoutsLooking: 2)
        )
        let awayLine = GameStatLine(
            player: sam, isHome: false, battingOrder: 0,
            batting: BattingStats(plateAppearances: 4, atBats: 4, hits: 2, homeRuns: 1)
        )
        homeLine.game = game
        awayLine.game = game
        game.statLines = [homeLine, awayLine]
        return game
    }

    @Test func includesBothTeamsBattingAndPitching() throws {
        let csv = StatsCSV.gameCSV(makeGame())

        // Both teams get their own labeled sections — not just the one on screen.
        #expect(csv.contains("Sluggers — BATTING"))
        #expect(csv.contains("Mashers — BATTING"))
        #expect(csv.contains("Sluggers — PITCHING"))
        #expect(csv.contains("Mike"))
        #expect(csv.contains("Sam"))
    }

    @Test func lineScoreHasInningsAndTotals() throws {
        let csv = StatsCSV.gameCSV(makeGame())
        let lines = csv.components(separatedBy: "\n")

        #expect(csv.contains("LINE SCORE"))
        // Header: Team,1,2,R,H,E for a two-inning game.
        #expect(lines.contains("Team,1,2,R,H,E"))
        // Away on top with its per-inning runs, then R (3) and H (2).
        #expect(lines.contains { $0.hasPrefix("Mashers,2,1,3,2,") })
        #expect(lines.contains { $0.hasPrefix("Sluggers,1,0,1,1,") })
    }

    @Test func teamTotalsSumThePlayerLines() throws {
        let csv = StatsCSV.gameCSV(makeGame())
        let lines = csv.components(separatedBy: "\n")

        // One batter per side, so each TEAM row must equal that batter's row (minus the name).
        let teamRows = lines.filter { $0.hasPrefix("TEAM,") }
        #expect(teamRows.count == 3)   // batting + pitching for the away/home split

        // Mashers' lone batter: 4 PA, 4 AB, 2 H, 1 HR → the team batting total matches.
        let samRow = try #require(lines.first { $0.hasPrefix("Sam,") })
        let samStats = samRow.dropFirst("Sam,".count)
        #expect(teamRows.contains { $0.dropFirst("TEAM,".count) == samStats })
    }

    /// A pitcher's called-third-strikes show up in the pitching section (the Kʟ column we added).
    @Test func pitchingIncludesStrikeoutsLooking() throws {
        let csv = StatsCSV.gameCSV(makeGame())
        let mikePitching = csv.components(separatedBy: "\n")
            .first { $0.hasPrefix("Mike,2.0,") }
        #expect(mikePitching != nil)
    }
}
