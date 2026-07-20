//
//  TournamentArchive.swift
//  Blitzball Stat Tracker
//
//  A self-contained, versioned JSON archive of a whole bracket — its rules, seeding, teams (with
//  rosters), players, and every match (with results + live state). Mirrors SeasonArchive: export is
//  read-only; import is additive (reuse teams/players by name; the only delete is a chosen Replace
//  of a prior import of the same bracket). Reuses SeasonArchive's Player/Team/StatLine DTOs + coders.
//

import Foundation
import SwiftData

struct TournamentArchive: Codable {
    static let currentFormat = "blitzball.tournament-archive"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date

    var tournament: TournamentInfoDTO
    var players: [SeasonArchive.PlayerDTO]
    var teams: [SeasonArchive.TeamDTO]
    var matches: [MatchDTO]

    struct TournamentInfoDTO: Codable {
        var name: String
        var status: String            // TournamentStatus.rawValue
        var createdAt: Date
        var decideTiesManually: Bool
        var settings: GameSettings
        var seedOrder: [String]
    }

    struct MatchDTO: Codable {
        var createdAt: Date
        var status: String            // GameStatus.rawValue
        var settings: GameSettings
        var bracketRound: Int
        var bracketSlot: Int
        var manualTieWinnerIsHome: Bool?

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

        // Challenge tallies. Optional so bracket files made before challenges existed still decode.
        var homeChallengesUsed: Int?
        var awayChallengesUsed: Int?
        var homeChallengesWon: Int?
        var awayChallengesWon: Int?

        var homeTeam: String?
        var awayTeam: String?
        var homePitcher: String?
        var awayPitcher: String?
        var runnerFirst: String?
        var runnerSecond: String?
        var runnerThird: String?
        var designatedHitter: String?

        var statLines: [SeasonArchive.StatLineDTO]
    }
}

// MARK: - Export (read-only)

extension TournamentArchive {
    init(exporting t: Tournament) {
        format = Self.currentFormat
        version = Self.currentVersion
        exportedAt = .now
        tournament = TournamentInfoDTO(
            name: t.name, status: t.status.rawValue, createdAt: t.createdAt,
            decideTiesManually: t.decideTiesManually, settings: t.settings, seedOrder: t.seedOrder
        )

        var teamSeen = Set<PersistentIdentifier>()
        var teamList: [Team] = []
        var playerSeen = Set<PersistentIdentifier>()
        var playerList: [Player] = []
        func addPlayer(_ p: Player?) {
            guard let p, playerSeen.insert(p.persistentModelID).inserted else { return }
            playerList.append(p)
        }
        func addTeam(_ team: Team?) {
            guard let team, teamSeen.insert(team.persistentModelID).inserted else { return }
            teamList.append(team)
            team.players.forEach(addPlayer)
        }

        for match in t.matches {
            addTeam(match.homeTeam); addTeam(match.awayTeam)
            addPlayer(match.homePitcher); addPlayer(match.awayPitcher)
            addPlayer(match.runnerFirst); addPlayer(match.runnerSecond); addPlayer(match.runnerThird)
            addPlayer(match.designatedHitter)
            match.statLines.forEach { addPlayer($0.player) }
        }

        players = playerList.map {
            SeasonArchive.PlayerDTO(name: $0.name, jerseyNumber: $0.jerseyNumber, dateAdded: $0.dateAdded)
        }
        teams = teamList.map {
            SeasonArchive.TeamDTO(name: $0.name, logoName: $0.logoName, league: $0.league,
                                  dateAdded: $0.dateAdded, roster: $0.players.map(\.name))
        }
        matches = t.matches
            .sorted { ($0.bracketRound, $0.bracketSlot) < ($1.bracketRound, $1.bracketSlot) }
            .map(MatchDTO.init(match:))
    }

    func encoded() throws -> Data { try SeasonArchive.jsonEncoder.encode(self) }

    func writeTempFile(baseName: String) throws -> URL {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = baseName.components(separatedBy: illegal).joined().trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "bracket" : cleaned
        let url = URL.temporaryDirectory.appending(path: "\(base)-bracket-\(df.string(from: .now)).json")
        try encoded().write(to: url, options: .atomic)
        return url
    }
}

extension TournamentArchive.MatchDTO {
    init(match g: Game) {
        createdAt = g.createdAt
        status = g.status.rawValue
        settings = g.settings
        bracketRound = g.bracketRound
        bracketSlot = g.bracketSlot
        manualTieWinnerIsHome = g.manualTieWinnerIsHome
        currentInning = g.currentInning
        isTopInning = g.isTopInning
        outs = g.outs
        awayInningRuns = g.awayInningRuns
        homeInningRuns = g.homeInningRuns
        homeBatterIndex = g.homeBatterIndex
        awayBatterIndex = g.awayBatterIndex
        homePitchingSwaps = g.homePitchingSwaps
        awayPitchingSwaps = g.awayPitchingSwaps
        homePitcherOuts = g.homePitcherOuts
        awayPitcherOuts = g.awayPitcherOuts
        homeChallengesUsed = g.homeChallengesUsed
        awayChallengesUsed = g.awayChallengesUsed
        homeChallengesWon = g.homeChallengesWon
        awayChallengesWon = g.awayChallengesWon
        homeTeam = g.homeTeam?.name
        awayTeam = g.awayTeam?.name
        homePitcher = g.homePitcher?.name
        awayPitcher = g.awayPitcher?.name
        runnerFirst = g.runnerFirst?.name
        runnerSecond = g.runnerSecond?.name
        runnerThird = g.runnerThird?.name
        designatedHitter = g.designatedHitter?.name
        statLines = g.statLines.map(SeasonArchive.StatLineDTO.init(line:))
    }
}

// MARK: - Import

enum TournamentImportError: LocalizedError {
    case unknownFormat
    case futureVersion(Int)
    var errorDescription: String? {
        switch self {
        case .unknownFormat:      return "This file isn't a Blitzball bracket export."
        case .futureVersion(let v): return "This bracket file was made by a newer version of the app (format v\(v)). Update the app to import it."
        }
    }
}

extension TournamentArchive {
    private struct Header: Codable { var format: String; var version: Int }

    static func decoded(from data: Data) throws -> TournamentArchive {
        let header = try SeasonArchive.jsonDecoder.decode(Header.self, from: data)
        guard header.format == currentFormat else { throw TournamentImportError.unknownFormat }
        guard header.version <= currentVersion else { throw TournamentImportError.futureVersion(header.version) }
        return try SeasonArchive.jsonDecoder.decode(TournamentArchive.self, from: data)
    }

    static func matchingTournament(for archive: TournamentArchive, in tournaments: [Tournament]) -> Tournament? {
        tournaments.first {
            $0.name == archive.tournament.name
            && abs($0.createdAt.timeIntervalSince(archive.tournament.createdAt)) < 1
        }
    }

    /// Rebuild this archive. Additive: creates a new Tournament + its matches, reusing teams/players
    /// by name. `.replace` first deletes `existing` (its matches cascade).
    @discardableResult
    func apply(resolution: SeasonImportResolution,
               existing: Tournament?,
               context: ModelContext) -> (tournament: Tournament, players: Int, matches: Int) {

        // Players — reuse by name or create.
        let existingPlayers = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var playerMap: [String: Player] = [:]
        for dto in players {
            let key = dto.name.lowercased()
            if let match = existingPlayers.first(where: { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }) {
                playerMap[key] = match
            } else {
                let p = Player(name: dto.name, jerseyNumber: dto.jerseyNumber, dateAdded: dto.dateAdded)
                context.insert(p); playerMap[key] = p
            }
        }
        func player(_ name: String?) -> Player? { name.flatMap { playerMap[$0.lowercased()] } }

        // Teams — reuse by name or create; append roster (never remove/overwrite).
        let existingTeams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        var teamMap: [String: Team] = [:]
        for dto in teams {
            let team: Team
            if let match = existingTeams.first(where: { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }) {
                team = match
            } else {
                let t = Team(name: dto.name, league: dto.league, logoName: dto.logoName, dateAdded: dto.dateAdded)
                context.insert(t); team = t
            }
            for name in dto.roster {
                if let p = player(name), !team.players.contains(where: { $0 === p }) { team.players.append(p) }
            }
            teamMap[dto.name.lowercased()] = team
        }
        func team(_ name: String?) -> Team? { name.flatMap { teamMap[$0.lowercased()] } }

        if resolution == .replace, let existing { context.delete(existing) }

        let newTournament = Tournament(
            name: tournament.name,
            settings: tournament.settings,
            decideTiesManually: tournament.decideTiesManually,
            status: TournamentStatus(rawValue: tournament.status) ?? .inProgress,
            createdAt: tournament.createdAt
        )
        newTournament.seedOrder = tournament.seedOrder
        context.insert(newTournament)

        for dto in matches {
            let g = Game(createdAt: dto.createdAt,
                         status: GameStatus(rawValue: dto.status) ?? .setup,
                         homeTeam: team(dto.homeTeam), awayTeam: team(dto.awayTeam),
                         settings: dto.settings)
            g.mode = .tournament
            g.tournament = newTournament
            g.bracketRound = dto.bracketRound
            g.bracketSlot = dto.bracketSlot
            g.manualTieWinnerIsHome = dto.manualTieWinnerIsHome
            g.currentInning = dto.currentInning
            g.isTopInning = dto.isTopInning
            g.outs = dto.outs
            g.awayInningRuns = dto.awayInningRuns
            g.homeInningRuns = dto.homeInningRuns
            g.homeBatterIndex = dto.homeBatterIndex
            g.awayBatterIndex = dto.awayBatterIndex
            g.homePitchingSwaps = dto.homePitchingSwaps
            g.awayPitchingSwaps = dto.awayPitchingSwaps
            g.homePitcherOuts = dto.homePitcherOuts
            g.awayPitcherOuts = dto.awayPitcherOuts
            g.homeChallengesUsed = dto.homeChallengesUsed ?? 0
            g.awayChallengesUsed = dto.awayChallengesUsed ?? 0
            g.homeChallengesWon = dto.homeChallengesWon ?? 0
            g.awayChallengesWon = dto.awayChallengesWon ?? 0
            g.homePitcher = player(dto.homePitcher)
            g.awayPitcher = player(dto.awayPitcher)
            g.runnerFirst = player(dto.runnerFirst)
            g.runnerSecond = player(dto.runnerSecond)
            g.runnerThird = player(dto.runnerThird)
            g.designatedHitter = player(dto.designatedHitter)
            context.insert(g)

            for sdto in dto.statLines {
                guard let p = player(sdto.playerName) else { continue }
                let line = GameStatLine(player: p, isHome: sdto.isHome, battingOrder: sdto.battingOrder,
                                        isActive: sdto.isActive, isDH: sdto.isDH,
                                        batting: sdto.batting, pitching: sdto.pitching)
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

        return (newTournament, players.count, matches.count)
    }
}
