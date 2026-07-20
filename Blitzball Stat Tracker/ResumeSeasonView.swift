//
//  ResumeSeasonView.swift
//  Blitzball Stat Tracker
//
//  Play through an in-progress season. Pick a season → see its weeks (each shows Not Played /
//  In Progress / final score) → tap a week to play it (setup), resume it (in progress), or
//  review its box score (final). Each week is just a Game, so it runs through the same live
//  tracking + End Game pipeline as an exhibition.
//

import SwiftUI
import SwiftData

// MARK: - Choose an in-progress season

struct ResumeSeasonView: View {
    @Query(sort: \Season.createdAt, order: .reverse) private var seasons: [Season]
    @Environment(\.modelContext) private var modelContext
    @State private var seasonToDelete: Season?
    @State private var showingImporter = false

    private var inProgress: [Season] {
        seasons.filter { $0.status == .inProgress }
    }

    // The alert is presented whenever a season is queued for deletion.
    private var confirmingDelete: Binding<Bool> {
        Binding(get: { seasonToDelete != nil }, set: { if !$0 { seasonToDelete = nil } })
    }

    var body: some View {
        List {
            if inProgress.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Seasons in Progress", systemImage: "play.slash.fill")
                    } description: {
                        Text("Start a season from New Season, or import one below to pick up where another device left off.")
                    }
                    .foregroundStyle(.white)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(inProgress) { season in
                        NavigationLink(value: SeasonRoute.games(season)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(season.name.isEmpty ? "Untitled Season" : season.name)
                                    .font(.headline)
                                Text("\(season.gamesPlayed)/\(season.gamesPerSeason) games played")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                seasonToDelete = season
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .blitzCardRow()
                }
            }

            importSection
        }
        .blitzListStyle()
        .navigationTitle("Resume Season")
        .blitzballBackground()
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Season?", isPresented: confirmingDelete, presenting: seasonToDelete) { season in
            Button("Delete Season", role: .destructive) { delete(season) }
            Button("Cancel", role: .cancel) { seasonToDelete = nil }
        } message: { season in
            Text(deleteMessage(for: season))
        }
        .seasonImporter(isPresented: $showingImporter)
    }

    /// Import a season file — the routine after-every-game sync. Same flow as the Season hub, kept
    /// here too since this is where you land to keep playing an in-progress season.
    private var importSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                Label("Import Season…", systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text("Just played on another device? Import the updated season file to sync it here (Season Stats → Export → Season File).")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .blitzCardRow()
    }

    /// Deleting a season cascades to its weekly games and their stat lines. Because career and
    /// team totals are DERIVED by summing game lines, those numbers update automatically. Players
    /// and teams themselves are untouched.
    private func delete(_ season: Season) {
        modelContext.delete(season)
        seasonToDelete = nil
    }

    private func deleteMessage(for season: Season) -> String {
        let name = season.name.isEmpty ? "this season" : season.name
        let count = season.gamesPlayed
        let games = count == 1 ? "1 played game" : "\(count) played games"
        return "This permanently deletes \(name) and \(games). Those stats leave every player's career and team totals. Your players and teams stay. This can't be undone."
    }
}

// MARK: - The season's weekly games

struct SeasonGamesView: View {
    @Bindable var season: Season
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                ForEach(season.weeks) { game in
                    NavigationLink {
                        destination(for: game)
                    } label: {
                        weekRow(game)
                    }
                }
                .blitzCardRow()
            } footer: {
                Text("\(season.gamesPlayed) of \(season.gamesPerSeason) games played.")
            }
        }
        .navigationTitle(season.name.isEmpty ? "Season" : season.name)
        .blitzballBackground()
        .blitzListStyle()
        .navigationBarTitleDisplayMode(.inline)
        // Replace the default back arrow with a jump straight to the Season Mode menu.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Truncate the season stack straight to the hub — one smooth animation.
                    router.goToSeasonMenu()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text("Season Mode")
                    }
                }
            }
        }
        // Make sure the weeks exist (harmless if they already do).
        .onAppear { season.syncSchedule(using: modelContext) }
    }

    // Route each week by its status: not-yet-played → pre-game; in-progress → resume the live
    // game; final → the box score (LiveGameView shows the summary when a game is final).
    @ViewBuilder
    private func destination(for game: Game) -> some View {
        switch game.status {
        case .setup:
            WeekPregameView(game: game)
        case .inProgress, .final:
            LiveGameView(game: game)
        }
    }

    private func weekRow(_ game: Game) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week \(game.weekNumber)").bold()
                Text(matchup(game))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusView(game)
        }
    }

    private func matchup(_ game: Game) -> String {
        let home = game.homeTeam?.name ?? "Home"
        let away = game.awayTeam?.name ?? "Away"
        return "\(home) vs \(away)"
    }

    @ViewBuilder
    private func statusView(_ game: Game) -> some View {
        switch game.status {
        case .setup:
            Text("Not played")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .inProgress:
            Text("In Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        case .final:
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(game.homeScore)–\(game.awayScore)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let winner = winnerText(game) {
                    Text(winner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // Who won a finished game, e.g. "Team01 won" (or a tie).
    private func winnerText(_ game: Game) -> String? {
        if game.homeScore > game.awayScore { return game.homeTeam.map { "\($0.name) won" } }
        if game.awayScore > game.homeScore { return game.awayTeam.map { "\($0.name) won" } }
        return "Tie game"
    }
}
