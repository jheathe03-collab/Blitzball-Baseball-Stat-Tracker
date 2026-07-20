//
//  StatsCSVExport.swift
//  Blitzball Stat Tracker
//
//  Read-only CSV export of stats we already compute, so a season (or the all-teams table) can be
//  shared as a plain spreadsheet (opens in Numbers / Excel / Google Sheets). One combined .csv file
//  per export, laid out as labeled sections. No import — this is purely a formatter + file writer.
//

import Foundation
import SwiftData

enum StatsCSV {

    // MARK: - Column headers (shared by season + all-teams)

    private static let battingHeaders =
        ["PA", "AB", "R", "H", "1B", "2B", "3B", "HR", "RBI", "BB", "HBP", "SO", "Kl", "SF", "SB",
         "AVG", "OBP", "SLG", "OPS"]

    private static let pitchingHeaders =
        ["IP", "Outs", "H", "R", "ER", "HR", "BB", "SO", "BAA", "ERA", "WHIP", "K/BB", "SV", "QS"]

    // MARK: - Public builders

    /// Everything for one season: standings, per-team season totals, and every player's season line.
    static func seasonCSV(_ season: Season) -> String {
        var rows: [[String]] = []
        let df = DateFormatter(); df.dateStyle = .medium

        rows.append(["Blitzball — Season: \(season.name.isEmpty ? "Untitled Season" : season.name)"])
        rows.append(["Generated: \(df.string(from: .now))"])
        rows.append(["Games played: \(season.gamesPlayed)/\(season.gamesPerSeason)"])
        rows.append([])

        let teams = seasonTeams(season)
        let teamTotals = seasonTeamTotals(season)   // [Team id → (batting, pitching)]
        let playerTeam = seasonPlayerTeams(season)  // [Player id → Team name]

        // Standings
        rows.append(["STANDINGS"])
        rows.append(["Team", "Wins", "Losses"])
        let standings = teams
            .map { (team: $0, record: $0.record(from: season.games)) }
            .sorted { $0.record.wins != $1.record.wins ? $0.record.wins > $1.record.wins
                                                        : $0.record.losses < $1.record.losses }
        for entry in standings {
            rows.append([entry.team.name, "\(entry.record.wins)", "\(entry.record.losses)"])
        }
        rows.append([])

        // Team batting / pitching (season totals)
        rows.append(["TEAM BATTING (season totals)"])
        rows.append(["Team"] + battingHeaders)
        for team in teams {
            let b = teamTotals[team.persistentModelID]?.batting ?? BattingStats()
            rows.append([team.name] + battingRow(b))
        }
        rows.append([])

        rows.append(["TEAM PITCHING (season totals)"])
        rows.append(["Team"] + pitchingHeaders)
        for team in teams {
            let p = teamTotals[team.persistentModelID]?.pitching ?? PitchingStats()
            rows.append([team.name] + pitchingRow(p))
        }
        rows.append([])

        // Player batting (season totals), best OPS first
        let batters = seasonPlayers(season)
            .map { (player: $0, stats: $0.battingStats(inSeason: season)) }
            .filter { $0.stats.plateAppearances > 0 }
            .sorted { $0.stats.onBasePlusSlugging > $1.stats.onBasePlusSlugging }
        rows.append(["PLAYER BATTING (season totals)"])
        rows.append(["Player", "Team"] + battingHeaders)
        for entry in batters {
            let team = playerTeam[entry.player.persistentModelID] ?? ""
            rows.append([entry.player.name, team] + battingRow(entry.stats))
        }
        rows.append([])

        // Player pitching (season totals), lowest ERA first
        let pitchers = seasonPlayers(season)
            .map { (player: $0, stats: $0.pitchingStats(inSeason: season)) }
            .filter { $0.stats.outsRecorded > 0 }
            .sorted { $0.stats.earnedRunAverage < $1.stats.earnedRunAverage }
        rows.append(["PLAYER PITCHING (season totals)"])
        rows.append(["Player", "Team"] + pitchingHeaders)
        for entry in pitchers {
            let team = playerTeam[entry.player.persistentModelID] ?? ""
            rows.append([entry.player.name, team] + pitchingRow(entry.stats))
        }

        return encode(rows)
    }

    /// The all-teams career aggregate: team totals + every player's career line.
    static func allTeamsCSV(teams: [Team], games: [Game]) -> String {
        var rows: [[String]] = []
        let df = DateFormatter(); df.dateStyle = .medium

        rows.append(["Blitzball — All Teams Stats"])
        rows.append(["Generated: \(df.string(from: .now))"])
        rows.append([])

        rows.append(["TEAM BATTING (career)"])
        rows.append(["Team", "Wins", "Losses"] + battingHeaders)
        for team in teams {
            let r = team.record(from: games)
            rows.append([team.name, "\(r.wins)", "\(r.losses)"] + battingRow(team.battingTotals))
        }
        rows.append([])

        rows.append(["TEAM PITCHING (career)"])
        rows.append(["Team"] + pitchingHeaders)
        for team in teams {
            rows.append([team.name] + pitchingRow(team.pitchingTotals))
        }
        rows.append([])

        // Distinct players across all teams, alphabetical.
        var seen = Set<PersistentIdentifier>()
        let players = teams.flatMap(\.players)
            .filter { seen.insert($0.persistentModelID).inserted }
            .sorted { $0.name < $1.name }

        rows.append(["PLAYER BATTING (career)"])
        rows.append(["Player", "Team"] + battingHeaders)
        for player in players where player.careerBatting.plateAppearances > 0 {
            rows.append([player.name, teamNames(player)] + battingRow(player.careerBatting))
        }
        rows.append([])

        rows.append(["PLAYER PITCHING (career)"])
        rows.append(["Player", "Team"] + pitchingHeaders)
        for player in players where player.careerPitching.outsRecorded > 0 {
            rows.append([player.name, teamNames(player)] + pitchingRow(player.careerPitching))
        }

        return encode(rows)
    }

    // MARK: - Row formatters

    private static func battingRow(_ b: BattingStats) -> [String] {
        ["\(b.plateAppearances)", "\(b.atBats)", "\(b.runsScored)", "\(b.hits)", "\(b.singles)",
         "\(b.doubles)", "\(b.triples)", "\(b.homeRuns)", "\(b.rbi)", "\(b.walks)", "\(b.hitByPitch)",
         "\(b.strikeouts)", "\(b.strikeoutsLooking)", "\(b.sacrificeFlies)", "\(b.stolenBases)",
         rate(b.battingAverage), rate(b.onBasePercentage), rate(b.sluggingPercentage),
         rate(b.onBasePlusSlugging)]
    }

    private static func pitchingRow(_ p: PitchingStats) -> [String] {
        let kbb = p.strikeoutToWalkRatio.map { ratio($0) } ?? "—"
        return [ip(outs: p.outsRecorded), "\(p.outsRecorded)", "\(p.hitsAllowed)", "\(p.runsAllowed)",
                "\(p.earnedRuns)", "\(p.homeRunsAllowed)", "\(p.walksAllowed)", "\(p.strikeouts)",
                rate(p.battingAverageAgainst), ratio(p.earnedRunAverage), ratio(p.walksAndHitsPerInning),
                kbb, "\(p.saves)", "\(p.qualityStarts)"]
    }

    // MARK: - Season participant derivation (mirrors SeasonStatsDetailView)

    private static func seasonTeams(_ season: Season) -> [Team] {
        var seen = Set<PersistentIdentifier>()
        var result: [Team] = []
        for game in season.weeks {
            for team in [game.homeTeam, game.awayTeam].compactMap({ $0 })
            where seen.insert(team.persistentModelID).inserted { result.append(team) }
        }
        return result
    }

    private static func seasonPlayers(_ season: Season) -> [Player] {
        var seen = Set<PersistentIdentifier>()
        var result: [Player] = []
        for game in season.games {
            for line in game.statLines {
                if let player = line.player, seen.insert(player.persistentModelID).inserted {
                    result.append(player)
                }
            }
        }
        return result
    }

    /// Sum every stat line in the season, attributed to the team on that line's side of the game.
    private static func seasonTeamTotals(_ season: Season)
        -> [PersistentIdentifier: (batting: BattingStats, pitching: PitchingStats)] {
        var totals: [PersistentIdentifier: (batting: BattingStats, pitching: PitchingStats)] = [:]
        for game in season.games {
            for line in game.statLines {
                guard let team = line.isHome ? game.homeTeam : game.awayTeam else { continue }
                let id = team.persistentModelID
                let current = totals[id] ?? (BattingStats(), PitchingStats())
                totals[id] = (current.batting + line.batting, current.pitching + line.pitching)
            }
        }
        return totals
    }

    /// Each player's team for this season — the side team on their season stat lines.
    private static func seasonPlayerTeams(_ season: Season) -> [PersistentIdentifier: String] {
        var map: [PersistentIdentifier: String] = [:]
        for game in season.games {
            for line in game.statLines {
                guard let player = line.player else { continue }
                let id = player.persistentModelID
                guard map[id] == nil else { continue }
                if let team = line.isHome ? game.homeTeam : game.awayTeam { map[id] = team.name }
            }
        }
        return map
    }

    private static func teamNames(_ player: Player) -> String {
        player.teams.map(\.name).sorted().joined(separator: " / ")
    }

    // MARK: - Formatting helpers

    static func rate(_ d: Double) -> String { String(format: "%.3f", d) }
    static func ratio(_ d: Double) -> String { String(format: "%.2f", d) }
    static func ip(outs: Int) -> String { "\(outs / 3).\(outs % 3)" }

    /// Turn rows of fields into CSV text, escaping any field that needs it.
    private static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\n")
    }

    /// CSV-escape one field:
    ///   1. Neutralize formula-injection prefixes. Excel / Numbers / Google Sheets treat a cell
    ///      starting with `=`, `+`, `-`, `@`, tab, or CR as a formula — so a team name like
    ///      `=HYPERLINK(...)` becomes an active hyperlink on import, and older Excel builds could
    ///      run `=cmd|'/c calc'!A0`. Prepending a single quote makes those cells literal text
    ///      (Excel treats leading `'` as an invisible text-prefix marker; other tools may show
    ///      it, which is an acceptable trade for correctness).
    ///   2. Wrap in quotes (doubling internal quotes) if the value contains a comma, a quote,
    ///      LF, or CR — so names like "O'Brien, Jr." don't shift columns, and Word/Windows
    ///      paste artifacts (`\r`) don't split the row.
    private static func field(_ value: String) -> String {
        let injectionPrefixes: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
        var v = value
        if let first = v.first, injectionPrefixes.contains(first) {
            v = "'" + v
        }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    // MARK: - File writing

    /// Write the CSV to a temp file and return its URL (for the share sheet).
    static func writeTempFile(_ csv: String, baseName: String) throws -> URL {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let name = "\(sanitized(baseName))-stats-\(df.string(from: .now)).csv"
        let url = URL.temporaryDirectory.appending(path: name)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func sanitized(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: illegal).joined().trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "stats" : cleaned
    }
}

/// A CSV file ready to share (Identifiable so it can drive `.sheet(item:)`).
struct CSVExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
