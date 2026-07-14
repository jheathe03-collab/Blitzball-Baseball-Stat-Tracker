//
//  PlayersView.swift
//  Blitzball Stat Tracker
//
//  The Players feature: add players and see their stats. (Formerly ContentView.)
//  This screen is PUSHED onto the Main Menu's navigation stack, so it does NOT create
//  its own NavigationStack — it uses the one the menu provides.
//

import SwiftUI
import SwiftData

struct PlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @State private var showingAddPlayer = false
    // The player swiped for deletion, held while we confirm.
    @State private var playerPendingDeletion: Player?
    // The player being edited (drives the edit sheet).
    @State private var playerToEdit: Player?

    var body: some View {
        // No NavigationStack here anymore — the Main Menu owns it. We just describe the
        // content plus its title and toolbar, and they attach to the parent stack.
        Group {
            if players.isEmpty {
                ContentUnavailableView(
                    "No Players Yet",
                    systemImage: "figure.baseball",
                    description: Text("Tap + to add your first player.")
                )
            } else {
                List {
                    ForEach(players) { player in
                        NavigationLink(destination: PlayerDetailView(player: player)) {
                            PlayerRow(player: player)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { playerToEdit = player }
                                .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            playerPendingDeletion = players[index]
                        }
                    }
                }
            }
        }
        .navigationTitle("Players")
        .toolbar {
            // Edit + Add live on the trailing side so they don't collide with the
            // system back button (which sits on the leading side after a push).
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                Button {
                    showingAddPlayer = true
                } label: {
                    Label("Add Player", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            AddPlayerView()
        }
        .sheet(item: $playerToEdit) { player in
            EditPlayerView(player: player)
        }
        .alert("Delete Player?", isPresented: deletePlayerAlert, presenting: playerPendingDeletion) { player in
            Button("Delete \(player.name)", role: .destructive) {
                modelContext.delete(player)
            }
            Button("Cancel", role: .cancel) { }
        } message: { player in
            Text("Are you sure you want to delete \(player.name)? This removes them from any team and can't be undone.")
        }
    }

    private var deletePlayerAlert: Binding<Bool> {
        Binding(get: { playerPendingDeletion != nil },
                set: { if !$0 { playerPendingDeletion = nil } })
    }
}

/// One row in the players list.
private struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack {
            Text(player.name)
                .font(.headline)
            Spacer()
            if let number = player.jerseyNumber {
                Text("#\(number)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    // Previewed inside a NavigationStack to mimic being pushed from the menu.
    NavigationStack {
        PlayersView()
    }
    .modelContainer(for: Player.self, inMemory: true)
}
