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
    /// The rulebook applied to every game this season (same GameSettings as exhibition).
    var settings: GameSettings
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
        self.settings = settings
        self.status = status
        self.createdAt = createdAt
    }
}
