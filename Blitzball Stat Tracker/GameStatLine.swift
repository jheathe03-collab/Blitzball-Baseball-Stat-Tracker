//
//  GameStatLine.swift
//  Blitzball Stat Tracker
//
//  One player's stat line FOR ONE GAME. This is the atom the whole app aggregates from:
//  a player's career = the sum of their game lines; a team's stats = the sum of its players'.
//

import Foundation
import SwiftData

@Model
final class GameStatLine {

    /// Which side this player is on in THIS game (snapshot, in case rosters change later).
    var isHome: Bool

    /// Lineup position, used for auto-advancing the batting order.
    var battingOrder: Int

    /// Still in the game? (Used when we add substitutions later.)
    var isActive: Bool

    /// True for the neutral Designated Hitter's single shared line (belongs to neither team;
    /// bats in both lineups). Kept out of team totals so DH stats stay personal-only.
    var isDH: Bool = false

    // MARK: - Archived (imported) line context
    // A line imported from another device has NO real `game`. These fields carry the context the
    // aggregations need — `archivedAt` (year filter), `archivedMode` (mode filter) — plus labels,
    // so an imported line counts toward a player's career WITHOUT fabricating a fake Game.
    var isArchived: Bool = false
    var archivedAt: Date? = nil
    var archivedMode: GameMode? = nil
    var archivedOpponent: String? = nil
    var archivedSeasonName: String? = nil
    var archivedWeek: Int? = nil

    /// This player's batting and pitching for this game only.
    var batting: BattingStats
    var pitching: PitchingStats

    /// The game this line belongs to. (Inverse is declared on `Game.statLines`.)
    var game: Game?

    /// The player this line is for. (Inverse is `Player.gameStatLines`.)
    @Relationship(inverse: \Player.gameStatLines) var player: Player?

    init(
        player: Player,
        isHome: Bool,
        battingOrder: Int,
        isActive: Bool = true,
        isDH: Bool = false,
        batting: BattingStats = BattingStats(),
        pitching: PitchingStats = PitchingStats()
    ) {
        self.player = player
        self.isHome = isHome
        self.battingOrder = battingOrder
        self.isActive = isActive
        self.isDH = isDH
        self.batting = batting
        self.pitching = pitching
    }
}

// MARK: - Derivation helpers (real game OR imported archive)

extension GameStatLine {
    /// Counts toward career totals: a finished real game, or an imported archived line.
    var countsAsFinal: Bool {
        isArchived || game?.status == .final
    }

    /// Date used for the year filter — the real game's date, or the archived date.
    var effectiveDate: Date? {
        game?.createdAt ?? archivedAt
    }

    /// Mode used for the mode filter — the real game's mode, or the archived mode.
    var effectiveMode: GameMode? {
        game?.mode ?? archivedMode
    }
}
