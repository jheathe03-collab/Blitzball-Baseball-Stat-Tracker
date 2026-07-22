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

    /// "Exhibition · Jul 17, 2026" (or the season name for season games), plus " · Setup" or
    /// " · In progress" while a game isn't final yet.
    static func subtitle(_ game: Game) -> String {
        let kind: String
        switch game.mode {
        case .exhibition: kind = "Exhibition"
        case .season:     kind = (game.season?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Season"
        case .tournament: kind = "Tournament"
        }
        let status: String
        switch game.status {
        case .final:      status = ""
        case .setup:      status = " · Setup"
        case .inProgress: status = " · In progress"
        }
        return "\(kind) · \(Self.dateFormatter.string(from: game.createdAt))\(status)"
    }

    // Hoist the DateFormatter out of subtitle() — configuring one is expensive, and this method
    // is called once per row per render (Season Game History, Player games list). DateFormatter
    // is thread-safe once configured, so a `static let` is fine.
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()
}
