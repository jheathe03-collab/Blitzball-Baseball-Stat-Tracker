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
        ["PA", "AB", "R", "H", "1B", "2B", "3B", "HR", "RBI", "BB", "HBP", "SO", "Kl", "SF", "SB", "CS",
         "AVG", "OBP", "SLG", "OPS"]

    private static let pitchingHeaders =
        ["IP", "Outs", "H", "R", "ER", "HR", "BB", "SO", "SOL", "BAA", "ERA", "WHIP", "K/BB", "SV", "QS", "BS"]

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
        // Built step by step with explicit types rather than as one map/sorted chain: the element is
        // a tuple containing another tuple, and threading that through chained generic calls is
        // something the Swift type-checker is slow at. Same result, far cheaper to compile.
        var standings: [(team: Team, record: (wins: Int, losses: Int))] = []
        for team in teams {
            let record: (wins: Int, losses: Int) = team.record(from: season.games)
            standings.append((team: team, record: record))
        }
        standings.sort { lhs, rhs in
            lhs.record.wins != rhs.record.wins
                ? lhs.record.wins > rhs.record.wins
                : lhs.record.losses < rhs.record.losses
        }
        for entry in standings {
            rows.append([entry.team.name, String(entry.record.wins), String(entry.record.losses)])
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

    /// ONE game's box score: the line score plus both teams' batting and pitching. This is the
    /// "share tonight's game with the team" export — season/all-teams exports are unaffected.
    static func gameCSV(_ game: Game) -> String {
        var rows: [[String]] = []
        let df = DateFormatter(); df.dateStyle = .medium
        let home = game.homeTeam?.name ?? "Home"
        let away = game.awayTeam?.name ?? "Away"

        rows.append(["Blitzball — Game: \(away) at \(home)"])
        rows.append(["Generated: \(df.string(from: .now))"])
        rows.append(["Played: \(df.string(from: game.createdAt))"])
        rows.append(["Type: \(gameContext(game))"])
        rows.append(["Final: \(away) \(game.awayScore), \(home) \(game.homeScore)"])
        rows.append([])

        // Line score — away on top, the way a scoreboard reads.
        let innings = max(game.awayInningRuns.count, game.homeInningRuns.count, 1)
        rows.append(["LINE SCORE"])
        rows.append(["Team"] + (1...innings).map { "\($0)" } + ["R", "H", "E"])
        rows.append(lineScoreRow(name: away, runs: game.awayInningRuns, innings: innings,
                                 total: game.awayScore, hits: game.hits(isHome: false),
                                 errors: game.awayErrors))
        rows.append(lineScoreRow(name: home, runs: game.homeInningRuns, innings: innings,
                                 total: game.homeScore, hits: game.hits(isHome: true),
                                 errors: game.homeErrors))
        rows.append([])

        // Both teams, away first to match the line score above.
        for isHome in [false, true] {
            let teamName = isHome ? home : away
            let lines = game.statLines
                .filter { $0.isHome == isHome && !$0.isDH }
                .sorted { $0.battingOrder < $1.battingOrder }

            rows.append(["\(teamName) — BATTING"])
            rows.append(["Player"] + battingHeaders)
            var teamBatting = BattingStats()
            for line in lines {
                teamBatting = teamBatting + line.batting
                rows.append([line.player?.name ?? "—"] + battingRow(line.batting))
            }
            rows.append(["TEAM"] + battingRow(teamBatting))
            rows.append([])

            let pitchers = lines.filter { $0.pitching.outsRecorded > 0 }
            rows.append(["\(teamName) — PITCHING"])
            rows.append(["Pitcher"] + pitchingHeaders)
            if pitchers.isEmpty {
                rows.append(["No pitching recorded for this team."])
            } else {
                var teamPitching = PitchingStats()
                for line in pitchers {
                    teamPitching = teamPitching + line.pitching
                    rows.append([line.player?.name ?? "—"] + pitchingRow(line.pitching))
                }
                rows.append(["TEAM"] + pitchingRow(teamPitching))
            }
            rows.append([])
        }

        // The neutral DH bats for both sides, so its line is personal — listed on its own.
        let dhLines = game.statLines.filter { $0.isDH }
        if !dhLines.isEmpty {
            rows.append(["DESIGNATED HITTER — BATTING"])
            rows.append(["Player"] + battingHeaders)
            for line in dhLines {
                rows.append([line.player?.name ?? "—"] + battingRow(line.batting))
            }
            let dhPitchers = dhLines.filter { $0.pitching.outsRecorded > 0 }
            if !dhPitchers.isEmpty {
                rows.append([])
                rows.append(["DESIGNATED HITTER — PITCHING"])
                rows.append(["Pitcher"] + pitchingHeaders)
                for line in dhPitchers {
                    rows.append([line.player?.name ?? "—"] + pitchingRow(line.pitching))
                }
            }
        }

        return encode(rows)
    }

    /// Where this game came from: "Season: Summer — Week 2", "Cup — Quarterfinals", "Exhibition".
    private static func gameContext(_ game: Game) -> String {
        switch game.mode {
        case .season:
            let name = game.season?.name ?? ""
            let label = name.isEmpty ? "Season" : "Season: \(name)"
            return "\(label) — Week \(game.weekNumber)"
        case .tournament:
            let name = game.tournament?.displayName ?? "Tournament"
            let round = game.tournament?.roundName(game.bracketRound) ?? "Round \(game.bracketRound + 1)"
            return "\(name) — \(round)"
        case .exhibition:
            return "Exhibition"
        }
    }

    /// One line-score row. Innings the team never batted stay blank.
    private static func lineScoreRow(name: String, runs: [Int], innings: Int,
                                     total: Int, hits: Int, errors: Int) -> [String] {
        var row = [name]
        for i in 0..<innings { row.append(i < runs.count ? "\(runs[i])" : "") }
        return row + ["\(total)", "\(hits)", "\(errors)"]
    }

    // MARK: - Row formatters

    private static func battingRow(_ b: BattingStats) -> [String] {
        ["\(b.plateAppearances)", "\(b.atBats)", "\(b.runsScored)", "\(b.hits)", "\(b.singles)",
         "\(b.doubles)", "\(b.triples)", "\(b.homeRuns)", "\(b.rbi)", "\(b.walks)", "\(b.hitByPitch)",
         "\(b.strikeouts)", "\(b.strikeoutsLooking)", "\(b.sacrificeFlies)", "\(b.stolenBases)",
         "\(b.caughtStealing)",
         rate(b.battingAverage), rate(b.onBasePercentage), rate(b.sluggingPercentage),
         rate(b.onBasePlusSlugging)]
    }

    private static func pitchingRow(_ p: PitchingStats) -> [String] {
        let kbb = p.strikeoutToWalkRatio.map { ratio($0) } ?? "—"
        return [ip(outs: p.outsRecorded), "\(p.outsRecorded)", "\(p.hitsAllowed)", "\(p.runsAllowed)",
                "\(p.earnedRuns)", "\(p.homeRunsAllowed)", "\(p.walksAllowed)", "\(p.strikeouts)",
                "\(p.strikeoutsLooking)",
                rate(p.battingAverageAgainst), ratio(p.earnedRunAverage), ratio(p.walksAndHitsPerInning),
                kbb, "\(p.saves)", "\(p.qualityStarts)", "\(p.blownSaves)"]
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
