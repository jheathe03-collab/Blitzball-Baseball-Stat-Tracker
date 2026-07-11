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

    // MARK: - Live game state (meaningful once the game is in progress)

    /// 1-based inning number.
    var currentInning: Int = 1
    /// Top of the inning = away team batting (home fields); bottom = home bats.
    var isTopInning: Bool = true
    /// Outs in the current half-inning (0...3).
    var outs: Int = 0
    /// Runs scored per inning by each side; index = inning - 1. Their sums are the scoreboard R.
    var awayInningRuns: [Int] = []
    var homeInningRuns: [Int] = []
    /// Which lineup spot is up next for each side (auto-advances after each plate appearance).
    var homeBatterIndex: Int = 0
    var awayBatterIndex: Int = 0

    /// The current pitcher for each side. The ACTIVE pitcher is the fielding side's — home
    /// pitches during the top of the inning, away during the bottom.
    @Relationship var homePitcher: Player?
    @Relationship var awayPitcher: Player?

    /// Ghost runners currently on base (only the batting team has runners). Cleared each
    /// half-inning. Access them positionally via the `bases` helper in Game+Live.
    @Relationship var runnerFirst: Player?
    @Relationship var runnerSecond: Player?
    @Relationship var runnerThird: Player?

    /// Every player's stat line for this game. Deleting the game deletes its lines (cascade).
    @Relationship(deleteRule: .cascade, inverse: \GameStatLine.game) var statLines: [GameStatLine] = []

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

extension Game {
    /// Scoreboard run totals, summed from the per-inning arrays.
    var awayScore: Int { awayInningRuns.reduce(0, +) }
    var homeScore: Int { homeInningRuns.reduce(0, +) }
}
