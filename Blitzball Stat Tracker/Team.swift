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

    // Win/Loss is no longer stored — it's DERIVED from finished games (see record(from:) below).

    /// Placeholder for the future League feature. Optional (`String?`) since it's unset for now.
    var league: String?

    /// When the team was created (handy for sorting later).
    var dateAdded: Date

    /// The players on this team. This is the "many players" side of a many-to-many relationship;
    /// `Player.teams` is the other side. SwiftData keeps the two in sync automatically.
    @Relationship var players: [Player] = []

    init(
        name: String,
        league: String? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.league = league
        self.dateAdded = dateAdded
    }
}

// MARK: - Aggregated team stats (computed from the roster)

extension Team {
    /// The whole roster's batting summed into one line. `reduce` starts from an empty
    /// `BattingStats()` and keeps adding each player's `batting` with our `+` operator.
    /// Uses `teamCareerBatting` so imported/archived history (not tied to this team) is excluded.
    var battingTotals: BattingStats {
        players.reduce(BattingStats()) { running, player in running + player.teamCareerBatting }
    }

    /// The whole roster's pitching summed into one line (also excludes imported/archived history).
    var pitchingTotals: PitchingStats {
        players.reduce(PitchingStats()) { running, player in running + player.teamCareerPitching }
    }

    /// Win/Loss record DERIVED from finished games (games are the source). Pass the games list
    /// (e.g. from an @Query). Ties count as neither.
    func record(from games: [Game]) -> (wins: Int, losses: Int) {
        var wins = 0
        var losses = 0
        for game in games where game.status == .final {
            let isHome = game.homeTeam === self
            let isAway = game.awayTeam === self
            guard isHome || isAway else { continue }
            let mine = isHome ? game.homeScore : game.awayScore
            let theirs = isHome ? game.awayScore : game.homeScore
            if mine > theirs { wins += 1 } else if mine < theirs { losses += 1 }
        }
        return (wins, losses)
    }
}
