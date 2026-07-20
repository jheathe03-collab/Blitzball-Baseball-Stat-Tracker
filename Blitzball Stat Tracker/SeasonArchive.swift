//
//  SeasonArchive.swift
//  Blitzball Stat Tracker
//
//  A self-contained, versioned JSON archive of a whole season — its rules, the teams it uses (with
//  rosters), the players, and every game (schedule + live state + each player's stat line). Used to
//  move a season between devices (e.g. simulator → phone). Mirrors PlayerArchive.
//
//  Safety: these are plain Codable structs (no @Model changes → no SwiftData migration). Export is
//  read-only. Import is additive — it only CREATES records, reusing existing teams/players by name,
//  and only deletes on an explicit "Replace" (which removes just the prior imported copy of THIS
//  season). Relationships travel by NAME (players/teams are name-unique) and are rebuilt in
//  dependency order, so nothing dangles.
//

import Foundation
import SwiftData

// MARK: - Archive format

struct SeasonArchive: Codable {
    static let currentFormat = "blitzball.season-archive"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date

    var season: SeasonInfoDTO
    var players: [PlayerDTO]
    var teams: [TeamDTO]
    var games: [GameDTO]

    struct SeasonInfoDTO: Codable {
        var name: String
        var gamesPerSeason: Int
        var status: String            // SeasonStatus.rawValue
        var createdAt: Date
        var settings: GameSettings
    }

    struct PlayerDTO: Codable {
        var name: String
        var jerseyNumber: Int?
        var dateAdded: Date
    }

    struct TeamDTO: Codable {
        var name: String
        var logoName: String?
        var logoImageData: Data?      // custom logo photo (optional). Encodes as base64 in JSON.
        var league: String?
        var dateAdded: Date
        var roster: [String]          // player names
    }

    struct GameDTO: Codable {
        var createdAt: Date
        var status: String            // GameStatus.rawValue
        var mode: String              // GameMode.rawValue
        var weekNumber: Int
        var settings: GameSettings

        // Live state
        var currentInning: Int
        var isTopInning: Bool
        var outs: Int
        var awayInningRuns: [Int]
        var homeInningRuns: [Int]
        var homeBatterIndex: Int
        var awayBatterIndex: Int
        var homePitchingSwaps: Int
        var awayPitchingSwaps: Int
        var homePitcherOuts: Int
        var awayPitcherOuts: Int
        // Challenge tallies. Optional so season files made before challenges existed still decode
        // (missing key → nil → treated as 0 on import). Keeps archive currentVersion at 1.
        var homeChallengesUsed: Int?
        var awayChallengesUsed: Int?
        var homeChallengesWon: Int?
        var awayChallengesWon: Int?

        // Relationships, by name
        var homeTeam: String?
        var awayTeam: String?
        var homePitcher: String?
        var awayPitcher: String?
        var runnerFirst: String?
        var runnerSecond: String?
        var runnerThird: String?
        var designatedHitter: String?

        var statLines: [StatLineDTO]
    }

    struct StatLineDTO: Codable {
        var playerName: String?
        var isHome: Bool
        var battingOrder: Int
        var pitchingOrder: Int
        var isActive: Bool
        var isDH: Bool
        var isArchived: Bool
        var archivedAt: Date?
        var archivedMode: String?
        var archivedOpponent: String?
        var archivedSeasonName: String?
        var archivedWeek: Int?
        var batting: BattingStats
        var pitching: PitchingStats
    }
}

// MARK: - Shared JSON coders

extension SeasonArchive {
    static var jsonEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    static var jsonDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Export (read-only)

extension SeasonArchive {
    init(exporting season: Season) {
        format = Self.currentFormat
        version = Self.currentVersion
        exportedAt = .now
        self.season = SeasonInfoDTO(
            name: season.name,
            gamesPerSeason: season.gamesPerSeason,
            status: season.status.rawValue,
            createdAt: season.createdAt,
            settings: season.settings
        )

        // Collect every distinct team + player this season references.
        var teamSeen = Set<PersistentIdentifier>()
        var teamList: [Team] = []
        var playerSeen = Set<PersistentIdentifier>()
        var playerList: [Player] = []

        func addPlayer(_ p: Player?) {
            guard let p, playerSeen.insert(p.persistentModelID).inserted else { return }
            playerList.append(p)
        }
        func addTeam(_ t: Team?) {
            guard let t, teamSeen.insert(t.persistentModelID).inserted else { return }
            teamList.append(t)
            t.players.forEach(addPlayer)
        }

        for game in season.games {
            addTeam(game.homeTeam); addTeam(game.awayTeam)
            addPlayer(game.homePitcher); addPlayer(game.awayPitcher)
            addPlayer(game.runnerFirst); addPlayer(game.runnerSecond); addPlayer(game.runnerThird)
            addPlayer(game.designatedHitter)
            game.statLines.forEach { addPlayer($0.player) }
        }

        players = playerList.map {
            PlayerDTO(name: $0.name, jerseyNumber: $0.jerseyNumber, dateAdded: $0.dateAdded)
        }
        teams = teamList.map {
            TeamDTO(name: $0.name, logoName: $0.logoName, logoImageData: $0.logoImageData,
                    league: $0.league, dateAdded: $0.dateAdded, roster: $0.players.map(\.name))
        }
        games = season.games
            .sorted { $0.weekNumber < $1.weekNumber }
            .map(GameDTO.init(game:))
    }

    func encoded() throws -> Data { try Self.jsonEncoder.encode(self) }

    /// Write to a temp file and return its URL (for the share sheet).
    func writeTempFile(seasonName: String) throws -> URL {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let base = Self.sanitizedFilename(seasonName)
        let url = URL.temporaryDirectory.appending(path: "\(base)-season-\(df.string(from: .now)).json")
        try encoded().write(to: url, options: .atomic)
        return url
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: illegal).joined().trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "season" : cleaned
    }
}

extension SeasonArchive.GameDTO {
    init(game: Game) {
        createdAt = game.createdAt
        status = game.status.rawValue
        mode = game.mode.rawValue
        weekNumber = game.weekNumber
        settings = game.settings
        currentInning = game.currentInning
        isTopInning = game.isTopInning
        outs = game.outs
        awayInningRuns = game.awayInningRuns
        homeInningRuns = game.homeInningRuns
        homeBatterIndex = game.homeBatterIndex
        awayBatterIndex = game.awayBatterIndex
        homePitchingSwaps = game.homePitchingSwaps
        awayPitchingSwaps = game.awayPitchingSwaps
        homePitcherOuts = game.homePitcherOuts
        awayPitcherOuts = game.awayPitcherOuts
        homeChallengesUsed = game.homeChallengesUsed
        awayChallengesUsed = game.awayChallengesUsed
        homeChallengesWon = game.homeChallengesWon
        awayChallengesWon = game.awayChallengesWon
        homeTeam = game.homeTeam?.name
        awayTeam = game.awayTeam?.name
        homePitcher = game.homePitcher?.name
        awayPitcher = game.awayPitcher?.name
        runnerFirst = game.runnerFirst?.name
        runnerSecond = game.runnerSecond?.name
        runnerThird = game.runnerThird?.name
        designatedHitter = game.designatedHitter?.name
        statLines = game.statLines.map(SeasonArchive.StatLineDTO.init(line:))
    }
}

extension SeasonArchive.StatLineDTO {
    init(line: GameStatLine) {
        playerName = line.player?.name
        isHome = line.isHome
        battingOrder = line.battingOrder
        pitchingOrder = line.pitchingOrder
        isActive = line.isActive
        isDH = line.isDH
        isArchived = line.isArchived
        archivedAt = line.archivedAt
        archivedMode = line.archivedMode?.rawValue
        archivedOpponent = line.archivedOpponent
        archivedSeasonName = line.archivedSeasonName
        archivedWeek = line.archivedWeek
        batting = line.batting
        pitching = line.pitching
    }
}

// MARK: - Import

enum SeasonImportResolution { case keepBoth, replace }

enum SeasonImportError: LocalizedError {
    case unknownFormat
    case futureVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            return "This file isn't a Blitzball season export."
        case .futureVersion(let v):
            return "This season file was made by a newer version of the app (format v\(v)). Update the app to import it."
        }
    }
}

extension SeasonArchive {
    /// Validate the format/version from a lightweight header FIRST, so a wrong file (e.g. a player
    /// archive) yields the friendly "not a season file" error instead of a cryptic decoding error.
    private struct Header: Codable { var format: String; var version: Int }

    static func decoded(from data: Data) throws -> SeasonArchive {
        let header = try jsonDecoder.decode(Header.self, from: data)
        guard header.format == currentFormat else { throw SeasonImportError.unknownFormat }
        guard header.version <= currentVersion else { throw SeasonImportError.futureVersion(header.version) }
        return try jsonDecoder.decode(SeasonArchive.self, from: data)
    }

    /// A season already on this device from the same export (same name + ~same creation time).
    static func matchingSeason(for archive: SeasonArchive, in seasons: [Season]) -> Season? {
        seasons.first {
            $0.name == archive.season.name
            && abs($0.createdAt.timeIntervalSince(archive.season.createdAt)) < 1
        }
    }

    /// Rebuild this archive into the store. Additive: creates a new Season and its games/lines,
    /// reusing teams/players by name. `.replace` first deletes `existingSeason` (its games/lines
    /// cascade) — nothing else is ever removed.
    @discardableResult
    func apply(resolution: SeasonImportResolution,
               existingSeason: Season?,
               context: ModelContext) -> (season: Season, players: Int, games: Int) {

        // 1. Players — reuse by name (case-insensitive) on this device, or create.
        //
        // The map is keyed by the DTO's ORIGINAL name (case-preserving), not lowercased. If the
        // archive legitimately contains two distinct players whose names differ only by case
        // (e.g. `mike` and `Mike`), each DTO gets its own map entry and its own destination
        // Player — the old lowercased key would have silently collapsed them, redirecting every
        // stat line and roster reference for one onto the other.
        let existingPlayers = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var playerMap: [String: Player] = [:]
        for dto in players {
            if let existing = existingPlayers.first(where: { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }) {
                // Two DTOs that only differ in case can BOTH resolve to the same existing player
                // here — that's the right merge behavior (this device already knows them as one).
                playerMap[dto.name] = existing
            } else {
                let p = Player(name: dto.name, jerseyNumber: dto.jerseyNumber, dateAdded: dto.dateAdded)
                context.insert(p)
                playerMap[dto.name] = p
            }
        }
        // Roster / stat-line / pitcher / runner / DH references were all serialized from the same
        // `player.name` string, so they match exactly — a plain lookup keeps distinct-case DTOs
        // routed to distinct destination players.
        func player(_ name: String?) -> Player? { name.flatMap { playerMap[$0] } }

        // 2. Teams — same case-preserving map + exact-case lookup story as players.
        let existingTeams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        var teamMap: [String: Team] = [:]
        for dto in teams {
            let team: Team
            if let existing = existingTeams.first(where: { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }) {
                team = existing   // keep its existing name/logo untouched
            } else {
                let t = Team(name: dto.name, league: dto.league, logoName: dto.logoName,
                             logoImageData: dto.logoImageData, dateAdded: dto.dateAdded)
                context.insert(t)
                team = t
            }
            for playerName in dto.roster {
                if let p = player(playerName), !team.players.contains(where: { $0 === p }) {
                    team.players.append(p)
                }
            }
            teamMap[dto.name] = team
        }
        func team(_ name: String?) -> Team? { name.flatMap { teamMap[$0] } }

        // 3. Replace: remove only the prior imported copy of THIS season (cascades its games/lines).
        if resolution == .replace, let existingSeason {
            context.delete(existingSeason)
        }

        // 4. Create the season (always new).
        let newSeason = Season(
            name: season.name,
            gamesPerSeason: season.gamesPerSeason,
            settings: season.settings,
            status: SeasonStatus(rawValue: season.status) ?? .inProgress,
            createdAt: season.createdAt
        )
        context.insert(newSeason)

        // 5. Games + their stat lines.
        for gdto in games {
            let g = Game(
                createdAt: gdto.createdAt,
                status: GameStatus(rawValue: gdto.status) ?? .setup,
                homeTeam: team(gdto.homeTeam),
                awayTeam: team(gdto.awayTeam),
                settings: gdto.settings
            )
            g.mode = GameMode(rawValue: gdto.mode) ?? .season
            g.weekNumber = gdto.weekNumber
            g.season = newSeason
            g.currentInning = gdto.currentInning
            g.isTopInning = gdto.isTopInning
            g.outs = gdto.outs
            g.awayInningRuns = gdto.awayInningRuns
            g.homeInningRuns = gdto.homeInningRuns
            g.homeBatterIndex = gdto.homeBatterIndex
            g.awayBatterIndex = gdto.awayBatterIndex
            g.homePitchingSwaps = gdto.homePitchingSwaps
            g.awayPitchingSwaps = gdto.awayPitchingSwaps
            g.homePitcherOuts = gdto.homePitcherOuts
            g.awayPitcherOuts = gdto.awayPitcherOuts
            g.homeChallengesUsed = gdto.homeChallengesUsed ?? 0
            g.awayChallengesUsed = gdto.awayChallengesUsed ?? 0
            g.homeChallengesWon = gdto.homeChallengesWon ?? 0
            g.awayChallengesWon = gdto.awayChallengesWon ?? 0
            g.homePitcher = player(gdto.homePitcher)
            g.awayPitcher = player(gdto.awayPitcher)
            g.runnerFirst = player(gdto.runnerFirst)
            g.runnerSecond = player(gdto.runnerSecond)
            g.runnerThird = player(gdto.runnerThird)
            g.designatedHitter = player(gdto.designatedHitter)
            context.insert(g)

            for sdto in gdto.statLines {
                guard let p = player(sdto.playerName) else { continue }
                let line = GameStatLine(
                    player: p, isHome: sdto.isHome, battingOrder: sdto.battingOrder,
                    isActive: sdto.isActive, isDH: sdto.isDH,
                    batting: sdto.batting, pitching: sdto.pitching
                )
                line.pitchingOrder = sdto.pitchingOrder
                line.isArchived = sdto.isArchived
                line.archivedAt = sdto.archivedAt
                line.archivedMode = sdto.archivedMode.flatMap { GameMode(rawValue: $0) }
                line.archivedOpponent = sdto.archivedOpponent
                line.archivedSeasonName = sdto.archivedSeasonName
                line.archivedWeek = sdto.archivedWeek
                line.game = g
                context.insert(line)
            }
        }

        return (newSeason, players.count, games.count)
    }
}
