//
//  Team.swift
//  Blitzball Stat Tracker
//
//  A team is a named group of players. Its stats aren't stored — they're COMPUTED by summing
//  the roster's stat lines (reusing the + operators on BattingStats/PitchingStats), so a team's
//  numbers always stay in sync with its players.
//

import Foundation
import SwiftData

@Model
final class Team {

    /// The team's name (e.g. "The Sluggers").
    var name: String

    /// Win/Loss record. Display-only for now — these will be driven by games (Exhibition /
    /// Tournament) once those features exist.
    var wins: Int
    var losses: Int

    /// Placeholder for the future League feature. Optional (`String?`) since it's unset for now.
    var league: String?

    /// When the team was created (handy for sorting later).
    var dateAdded: Date

    /// The players on this team. This is the "many players" side of a many-to-many relationship;
    /// `Player.teams` is the other side. SwiftData keeps the two in sync automatically.
    @Relationship var players: [Player] = []

    init(
        name: String,
        wins: Int = 0,
        losses: Int = 0,
        league: String? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.wins = wins
        self.losses = losses
        self.league = league
        self.dateAdded = dateAdded
    }
}

// MARK: - Aggregated team stats (computed from the roster)

extension Team {
    /// The whole roster's batting summed into one line. `reduce` starts from an empty
    /// `BattingStats()` and keeps adding each player's `batting` with our `+` operator.
    var battingTotals: BattingStats {
        players.reduce(BattingStats()) { running, player in running + player.batting }
    }

    /// The whole roster's pitching summed into one line.
    var pitchingTotals: PitchingStats {
        players.reduce(PitchingStats()) { running, player in running + player.pitching }
    }

    /// A tidy "W-L" string for the leaderboard, e.g. "3-2".
    var record: String {
        "\(wins)-\(losses)"
    }
}
