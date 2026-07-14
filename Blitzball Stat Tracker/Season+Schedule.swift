//
//  Season+Schedule.swift
//  Blitzball Stat Tracker
//
//  Keeps a season's weekly games in sync with its `gamesPerSeason` count. Mirrors the syncLineup
//  pattern: create missing weeks, drop extras — preserving weeks that already exist.
//

import Foundation
import SwiftData

extension Season {
    /// The weekly games in order.
    var weeks: [Game] {
        games.sorted { $0.weekNumber < $1.weekNumber }
    }

    /// Every week has both teams chosen (required before Start Season).
    var isScheduleComplete: Bool {
        let ordered = weeks
        return ordered.count == gamesPerSeason
            && ordered.allSatisfy { $0.homeTeam != nil && $0.awayTeam != nil }
    }

    var weeksWithTeamsSet: Int {
        weeks.filter { $0.homeTeam != nil && $0.awayTeam != nil }.count
    }

    /// How many of the season's weekly games have been finished (used for progress on Resume).
    var gamesPlayed: Int {
        games.filter { $0.status == .final }.count
    }

    /// Ensure exactly `gamesPerSeason` weekly games exist (weeks 1...N), each an empty setup game.
    func syncSchedule(using context: ModelContext) {
        var ordered = weeks

        // Remove extra weeks (from the highest week down) if the count was reduced.
        while ordered.count > gamesPerSeason, let last = ordered.popLast() {
            context.delete(last)
        }

        // Add missing weeks.
        let existingWeeks = Set(ordered.map(\.weekNumber))
        for week in 1...max(gamesPerSeason, 1) where !existingWeeks.contains(week) {
            let game = Game(status: .setup, settings: settings)
            game.mode = .season
            game.weekNumber = week
            game.season = self
            context.insert(game)
        }
    }
}
