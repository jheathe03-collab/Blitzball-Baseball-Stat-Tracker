//
//  Player+Career.swift
//  Blitzball Stat Tracker
//
//  A player's career stats are DERIVED, not stored: sum the batting/pitching lines from their
//  finished games. Because it's computed, correcting or deleting a game automatically fixes a
//  player's career totals everywhere they're shown.
//

import Foundation

extension Player {
    /// Only completed games count toward career totals.
    var finalStatLines: [GameStatLine] {
        gameStatLines.filter { $0.game?.status == .final }
    }

    var careerBatting: BattingStats {
        finalStatLines.reduce(BattingStats()) { $0 + $1.batting }
    }

    var careerPitching: PitchingStats {
        finalStatLines.reduce(PitchingStats()) { $0 + $1.pitching }
    }

    // MARK: - Filtered (by mode and/or year; nil = "all")

    func statLines(mode: GameMode?, year: Int?) -> [GameStatLine] {
        finalStatLines.filter { line in
            guard let game = line.game else { return false }
            if let mode, game.mode != mode { return false }
            if let year, Calendar.current.component(.year, from: game.createdAt) != year { return false }
            return true
        }
    }

    func battingStats(mode: GameMode?, year: Int?) -> BattingStats {
        statLines(mode: mode, year: year).reduce(BattingStats()) { $0 + $1.batting }
    }

    func pitchingStats(mode: GameMode?, year: Int?) -> PitchingStats {
        statLines(mode: mode, year: year).reduce(PitchingStats()) { $0 + $1.pitching }
    }

    /// Distinct years this player has finished-game data in, newest first (for the year filter).
    var statYears: [Int] {
        let years = finalStatLines.compactMap { line -> Int? in
            guard let game = line.game else { return nil }
            return Calendar.current.component(.year, from: game.createdAt)
        }
        return Array(Set(years)).sorted(by: >)
    }
}
