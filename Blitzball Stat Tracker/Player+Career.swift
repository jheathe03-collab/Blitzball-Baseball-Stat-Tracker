//
//  Player+Career.swift
//  Blitzball Stat Tracker
//
//  A player's career stats are DERIVED, not stored: sum the batting/pitching lines from their
//  finished games. Because it's computed, correcting or deleting a game automatically fixes a
//  player's career totals everywhere they're shown.
//

import Foundation
import SwiftData

extension Player {
    /// Lines that count toward career totals: finished real games AND imported archived lines.
    var finalStatLines: [GameStatLine] {
        gameStatLines.filter(\.countsAsFinal)
    }

    var careerBatting: BattingStats {
        finalStatLines.reduce(BattingStats()) { $0 + $1.batting }
    }

    var careerPitching: PitchingStats {
        finalStatLines.reduce(PitchingStats()) { $0 + $1.pitching }
    }

    // MARK: - Filtered (by mode and/or year and/or a specific season; nil = "all")

    func statLines(mode: GameMode?, year: Int?, season: Season? = nil) -> [GameStatLine] {
        finalStatLines.filter { line in
            if let mode, line.effectiveMode != mode { return false }
            if let year {
                guard let date = line.effectiveDate,
                      Calendar.current.component(.year, from: date) == year else { return false }
            }
            if let season {
                guard let lineSeason = line.game?.season, lineSeason === season else { return false }
            }
            return true
        }
    }

    func battingStats(mode: GameMode?, year: Int?, season: Season? = nil) -> BattingStats {
        statLines(mode: mode, year: year, season: season).reduce(BattingStats()) { $0 + $1.batting }
    }

    func pitchingStats(mode: GameMode?, year: Int?, season: Season? = nil) -> PitchingStats {
        statLines(mode: mode, year: year, season: season).reduce(PitchingStats()) { $0 + $1.pitching }
    }

    /// Distinct years this player has finished data in, newest first (for the year filter).
    var statYears: [Int] {
        let years = finalStatLines.compactMap { line -> Int? in
            guard let date = line.effectiveDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted(by: >)
    }

    /// Distinct seasons this player has finished data in, newest first (for the season sub-filter).
    var statSeasons: [Season] {
        var seen = Set<PersistentIdentifier>()
        var result: [Season] = []
        for line in finalStatLines {
            if let season = line.game?.season, seen.insert(season.persistentModelID).inserted {
                result.append(season)
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Filtered by a specific Season (real games only — imported lines have no season)

    func statLines(inSeason season: Season) -> [GameStatLine] {
        finalStatLines.filter { line in
            guard let lineSeason = line.game?.season else { return false }
            return lineSeason === season
        }
    }

    func battingStats(inSeason season: Season) -> BattingStats {
        statLines(inSeason: season).reduce(BattingStats()) { $0 + $1.batting }
    }

    func pitchingStats(inSeason season: Season) -> PitchingStats {
        statLines(inSeason: season).reduce(PitchingStats()) { $0 + $1.pitching }
    }

    // MARK: - Filtered by a specific Tournament

    func statLines(inTournament tournament: Tournament) -> [GameStatLine] {
        finalStatLines.filter { $0.game?.tournament === tournament }
    }

    func battingStats(inTournament tournament: Tournament) -> BattingStats {
        statLines(inTournament: tournament).reduce(BattingStats()) { $0 + $1.batting }
    }

    func pitchingStats(inTournament tournament: Tournament) -> PitchingStats {
        statLines(inTournament: tournament).reduce(PitchingStats()) { $0 + $1.pitching }
    }

    // Note: team totals are computed on Team itself (see Team.battingTotals / pitchingTotals),
    // NOT by summing each player's career. Summing a player's career on the team side would
    // double-count anyone who ever played for another team. Don't add a "team career" helper here.
}
