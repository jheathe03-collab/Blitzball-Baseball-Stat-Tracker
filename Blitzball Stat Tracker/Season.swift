//
//  Season.swift
//  Blitzball Stat Tracker
//
//  A league season: a named run of N weekly games with one shared rulebook. Each week is a Game
//  (reusing all our game infra), linked back here so its stats can be filtered by season.
//

import Foundation
import SwiftData

enum SeasonStatus: String, Codable {
    case setup       // being configured
    case inProgress  // started, playing through the weeks
    case final       // finished
}

@Model
final class Season {
    var name: String
    /// Number of weekly games (one matchup per week).
    var gamesPerSeason: Int
    /// The rulebook applied to every game this season — stored as a JSON blob (see BlobCoder) so
    /// new rules can be added later without a schema change. Access via `settings` (extension below).
    var settingsData: Data
    var status: SeasonStatus
    var createdAt: Date

    /// The weekly games. Deleting the season deletes its games (cascade). `Game.season` is the inverse.
    @Relationship(deleteRule: .cascade, inverse: \Game.season) var games: [Game] = []

    init(
        name: String = "",
        gamesPerSeason: Int = 7,
        settings: GameSettings = .blitzballDefaults,
        status: SeasonStatus = .setup,
        createdAt: Date = .now
    ) {
        self.name = name
        self.gamesPerSeason = gamesPerSeason
        self.settingsData = BlobCoder.encode(settings)
        self.status = status
        self.createdAt = createdAt
    }
}

extension Season {
    /// This season's rulebook, decoded from its blob. Setting re-encodes it.
    var settings: GameSettings {
        get { BlobCoder.decode(settingsData) ?? .blitzballDefaults }
        set { settingsData = BlobCoder.encode(newValue) }
    }
}
