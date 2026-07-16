//
//  PlayerArchive.swift
//  Blitzball Stat Tracker
//
//  The JSON format for exporting/importing ONE player's complete finished-game history, plus the
//  builders that turn a Player into an archive and apply an archive back into the store.
//
//  Imported lines become "archived" GameStatLines (game == nil) that carry their own context, so
//  they count toward the player's career/filters WITHOUT fabricating fake Games (which would
//  corrupt team records + season schedules). See GameStatLine's archived* fields.
//

import Foundation
import SwiftData

// MARK: - Versioned archive format (independent of the @Model types)

struct PlayerArchive: Codable {
    static let currentFormat = "blitzball.player-archive"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var player: PlayerInfo
    var statLines: [ArchivedStatLineDTO]

    struct PlayerInfo: Codable {
        var name: String
        var jerseyNumber: Int?
    }

    struct ArchivedStatLineDTO: Codable {
        var date: Date
        var mode: String?          // GameMode.rawValue — string so unknown future modes decode to nil
        var seasonName: String?
        var week: Int?
        var opponent: String?
        var isHome: Bool
        var isDH: Bool
        var batting: BattingStats  // already Codable
        var pitching: PitchingStats
    }
}

// MARK: - Shared JSON coders

extension PlayerArchive {
    static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Export

extension PlayerArchive {
    /// Capture a player's complete finished-game history (real games + any prior imports).
    init(exporting player: Player) {
        format = Self.currentFormat
        version = Self.currentVersion
        exportedAt = .now
        self.player = PlayerInfo(name: player.name, jerseyNumber: player.jerseyNumber)
        statLines = player.finalStatLines.map { line in
            if line.isArchived {
                // Already a standalone archived line — read its stored context directly.
                return ArchivedStatLineDTO(
                    date: line.archivedAt ?? .now,
                    mode: line.archivedMode?.rawValue,
                    seasonName: line.archivedSeasonName,
                    week: line.archivedWeek,
                    opponent: line.archivedOpponent,
                    isHome: line.isHome,
                    isDH: line.isDH,
                    batting: line.batting,
                    pitching: line.pitching
                )
            } else {
                // A real finished game — derive the context from the game + matchup.
                let game = line.game
                let opponent = line.isHome ? game?.awayTeam?.name : game?.homeTeam?.name
                let week = (game?.weekNumber ?? 0) == 0 ? nil : game?.weekNumber
                return ArchivedStatLineDTO(
                    date: game?.createdAt ?? .now,
                    mode: game?.mode.rawValue,
                    seasonName: game?.season?.name,
                    week: week,
                    opponent: opponent,
                    isHome: line.isHome,
                    isDH: line.isDH,
                    batting: line.batting,
                    pitching: line.pitching
                )
            }
        }
    }

    func encoded() throws -> Data {
        try Self.jsonEncoder.encode(self)
    }
}

// MARK: - Import

enum ImportResolution {
    case createNew
    case merge
    case replace
}

enum PlayerImportError: LocalizedError {
    case unknownFormat
    case futureVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            return "This file isn't a Blitzball player export."
        case .futureVersion(let v):
            return "This file was made by a newer version of the app (format v\(v)). Update the app to import it."
        }
    }
}

/// Identifies an archived stat line for dedup during merge. Two lines with the same signature
/// are treated as the same historical game — matches how a re-export of the same source game
/// serializes (same date/season/week/opponent/side).
private struct ArchivedLineKey: Hashable {
    let date: Date
    let opponent: String?
    let seasonName: String?
    let week: Int?
    let isHome: Bool
    let isDH: Bool

    init(line: GameStatLine) {
        self.date = line.archivedAt ?? .distantPast
        self.opponent = line.archivedOpponent
        self.seasonName = line.archivedSeasonName
        self.week = line.archivedWeek
        self.isHome = line.isHome
        self.isDH = line.isDH
    }

    init(dto: PlayerArchive.ArchivedStatLineDTO) {
        self.date = dto.date
        self.opponent = dto.opponent
        self.seasonName = dto.seasonName
        self.week = dto.week
        self.isHome = dto.isHome
        self.isDH = dto.isDH
    }
}

extension PlayerArchive {
    /// Decode + validate an archive from raw file data.
    static func decoded(from data: Data) throws -> PlayerArchive {
        let archive = try jsonDecoder.decode(PlayerArchive.self, from: data)
        guard archive.format == currentFormat else { throw PlayerImportError.unknownFormat }
        guard archive.version <= currentVersion else { throw PlayerImportError.futureVersion(archive.version) }
        return archive
    }

    /// Apply this archive to the store per the chosen resolution.
    /// - Parameter existing: a stored player with the same name (nil ⇒ createNew).
    /// - Returns: the number of stat lines actually inserted (merge skips duplicates).
    @discardableResult
    func apply(resolution: ImportResolution, existing: Player?, context: ModelContext) -> Int {
        let target: Player
        // Signatures of archived lines already on the target — used to skip duplicates on merge,
        // so re-importing the same file (or a superset) doesn't double-count history.
        var existingKeys: Set<ArchivedLineKey> = []

        switch resolution {
        case .createNew:
            let player = Player(name: player.name, jerseyNumber: player.jerseyNumber)
            context.insert(player)
            target = player

        case .merge:
            guard let existing else { return 0 }
            if existing.jerseyNumber == nil { existing.jerseyNumber = player.jerseyNumber }
            existingKeys = Set(existing.gameStatLines
                .filter { $0.isArchived && $0.game == nil }
                .map(ArchivedLineKey.init(line:)))
            target = existing

        case .replace:
            guard let existing else { return 0 }
            // Remove ONLY previously-imported archived lines — never lines tied to a real game.
            // Snapshot first so we're not mutating the relationship we're iterating.
            let toDelete = existing.gameStatLines.filter { $0.isArchived && $0.game == nil }
            for line in toDelete { context.delete(line) }
            if existing.jerseyNumber == nil { existing.jerseyNumber = player.jerseyNumber }
            target = existing
        }

        var added = 0
        for dto in statLines {
            let key = ArchivedLineKey(dto: dto)
            guard existingKeys.insert(key).inserted else { continue }
            makeLine(from: dto, for: target, in: context)
            added += 1
        }
        return added
    }

    /// Turn one DTO into a standalone archived GameStatLine (game == nil) attached to `player`.
    private func makeLine(from dto: ArchivedStatLineDTO, for player: Player, in context: ModelContext) {
        let line = GameStatLine(
            player: player,
            isHome: dto.isHome,
            battingOrder: 0,
            isActive: true,
            isDH: dto.isDH,
            batting: dto.batting,
            pitching: dto.pitching
        )
        line.isArchived = true
        line.archivedAt = dto.date
        line.archivedMode = dto.mode.flatMap { GameMode(rawValue: $0) }
        line.archivedOpponent = dto.opponent
        line.archivedSeasonName = dto.seasonName
        line.archivedWeek = dto.week
        context.insert(line)
    }
}
