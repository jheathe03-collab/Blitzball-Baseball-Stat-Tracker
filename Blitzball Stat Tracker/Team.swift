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

    /// The bundled logo asset this team uses (see TeamLogo). nil = no logo chosen.
    var logoName: String?

    /// When the team was created (handy for sorting later).
    var dateAdded: Date

    /// The players on this team. This is the "many players" side of a many-to-many relationship;
    /// `Player.teams` is the other side. SwiftData keeps the two in sync automatically.
    @Relationship var players: [Player] = []

    init(
        name: String,
        league: String? = nil,
        logoName: String? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.league = league
        self.logoName = logoName
        self.dateAdded = dateAdded
    }
}

// MARK: - Aggregated team stats (computed from the roster)

extension Team {
    /// Every stat line the current roster actually earned wearing THIS team's uniform. We can't
    /// just sum each player's career, because a player who used to be on another team would drag
    /// those other-team games in and double-count. Instead we keep only lines whose game had this
    /// team on the matching side (home/away), and drop the neutral Designated Hitter's lines (they
    /// belong to neither team — see the DH note in the project docs). Imported/archived lines
    /// (game == nil) are naturally excluded by the `guard let game` here.
    private var teamStatLines: [GameStatLine] {
        players.flatMap { player in
            player.gameStatLines.filter { line in
                guard !line.isDH, let game = line.game, game.status == .final else { return false }
                return line.isHome ? (game.homeTeam === self) : (game.awayTeam === self)
            }
        }
    }

    /// The whole roster's batting summed into one line — only games played FOR this team count.
    var battingTotals: BattingStats {
        teamStatLines.reduce(BattingStats()) { $0 + $1.batting }
    }

    /// The whole roster's pitching summed into one line — only games played FOR this team count.
    var pitchingTotals: PitchingStats {
        teamStatLines.reduce(PitchingStats()) { $0 + $1.pitching }
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
