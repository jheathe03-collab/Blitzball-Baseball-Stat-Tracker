//
//  Game.swift
//  Blitzball Stat Tracker
//
//  A single game (for now, an exhibition). Right now it just holds the matchup — the two
//  teams — and a status. Live stat tracking (scores, per-player game lines) gets added here
//  when we build the Start Game phase.
//

import Foundation
import SwiftData

/// Where a game is in its lifecycle. String-backed + Codable so SwiftData can store it.
enum GameStatus: String, Codable {
    case setup       // still choosing teams
    case inProgress  // being played / tracked live (future)
    case final       // finished (future)
}

@Model
final class Game {

    /// When this game was created — used to find the most recent setup game.
    var createdAt: Date

    /// Lifecycle stage. New games start in `.setup` while teams are being chosen.
    var status: GameStatus

    /// The two sides. Optional to-one relationships: a game in setup may not have picked yet.
    /// These are unidirectional (no inverse on Team) because there are two links to the same
    /// type and we don't need to look a game up *from* a team yet. If a Team is deleted, these
    /// simply become nil (the game isn't deleted).
    @Relationship var homeTeam: Team?
    @Relationship var awayTeam: Team?

    /// The rules for this game (game type, innings, strikes/balls, ...). Stored as a Codable
    /// struct, the same way Player stores its BattingStats. New games start on Blitzball defaults.
    var settings: GameSettings

    init(
        createdAt: Date = .now,
        status: GameStatus = .setup,
        homeTeam: Team? = nil,
        awayTeam: Team? = nil,
        settings: GameSettings = .blitzballDefaults
    ) {
        self.createdAt = createdAt
        self.status = status
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.settings = settings
    }
}
