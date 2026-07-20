//
//  GameHistoryRow.swift
//  Blitzball Stat Tracker
//
//  One row in a "Game History" list: the score line plus a subtitle (kind · date · status).
//  Shared by the Teams overview (all games) and a single team's detail page (that team's games),
//  so both render identically and the date/subtitle formatting lives in one place.
//

import SwiftUI

struct GameHistoryRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(game.homeTeam?.name ?? "Home") \(game.homeScore)–\(game.awayScore) \(game.awayTeam?.name ?? "Away")")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(Self.subtitle(game))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// "Exhibition · Jul 17, 2026" (or the season name for season games), plus "· In progress"
    /// while a game isn't final yet.
    static func subtitle(_ game: Game) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let date = df.string(from: game.createdAt)
        let kind: String
        switch game.mode {
        case .exhibition: kind = "Exhibition"
        case .season:     kind = (game.season?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Season"
        case .tournament: kind = "Tournament"
        }
        let status = game.status == .final ? "" : " · In progress"
        return "\(kind) · \(date)\(status)"
    }
}
