//
//  ExhibitionHistoryView.swift
//  Blitzball Stat Tracker
//
//  One place to review and delete finished Exhibition games — reached from the Exhibition setup
//  screen. Before this, deleting a played exhibition game meant digging into a player's stats and
//  scrolling to the bottom; this gathers them all in a single list. In-progress ("paused") games are
//  resumed from Exhibition instead, so they're intentionally not listed here.
//

import SwiftUI
import SwiftData

struct ExhibitionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allGames: [Game]
    @State private var gameToDelete: Game?

    /// Finished exhibition games, newest first.
    private var playedGames: [Game] {
        allGames
            .filter { $0.mode == .exhibition && $0.status == .final }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if playedGames.isEmpty {
                Section {
                    Text("No finished exhibition games yet.")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .blitzCardRow()
            } else {
                Section {
                    ForEach(playedGames, id: \.persistentModelID) { game in
                        NavigationLink(destination: GameSummaryView(game: game)) {
                            GameHistoryRow(game: game)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { gameToDelete = game } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Tap a game to see its box score. Swipe a game to delete it.")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .blitzCardRow()
            }
        }
        .blitzListStyle()
        .blitzballBackground()
        .navigationTitle("Previous Games")
        .navigationBarTitleDisplayMode(.inline)
        // Same confirmation and permanence as deleting from a team's Game History.
        .alert("Delete Game?", isPresented: deleteAlert, presenting: gameToDelete) { _ in
            Button("Delete Game", role: .destructive) {
                if let game = gameToDelete { modelContext.delete(game) }
                gameToDelete = nil
            }
            Button("Cancel", role: .cancel) { gameToDelete = nil }
        } message: { _ in
            Text("This permanently deletes this game and everyone's stats from it. This can't be undone.")
        }
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { gameToDelete != nil }, set: { if !$0 { gameToDelete = nil } })
    }
}
