//
//  AddExistingPlayerView.swift
//  Blitzball Stat Tracker
//
//  A sheet listing players NOT already on the team. Tap to select, then Add.
//

import SwiftUI
import SwiftData

struct AddExistingPlayerView: View {
    @Bindable var team: Team
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Player.name) private var allPlayers: [Player]

    // Which players the user has tapped. We track them by their SwiftData identity.
    @State private var selected: Set<PersistentIdentifier> = []

    // Set when the user taps a player already on another team (we enforce one team per player).
    @State private var conflict: AssignmentConflict?

    // Only offer players who aren't already on this team.
    private var availablePlayers: [Player] {
        allPlayers.filter { player in !team.players.contains { $0 === player } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availablePlayers.isEmpty {
                    ContentUnavailableView(
                        "No Available Players",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("Everyone is already on this team, or you haven't created any players yet.")
                    )
                    .foregroundStyle(.white)
                } else {
                    List(availablePlayers) { player in
                        Button {
                            toggle(player)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.name)
                                        .foregroundStyle(.white)
                                    // Show the current team for players already assigned elsewhere.
                                    if let currentTeam = player.teams.first {
                                        Text("On \(currentTeam.name)")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                Spacer()
                                if selected.contains(player.persistentModelID) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                } else if !player.teams.isEmpty {
                                    // A lock hints that this player is spoken for.
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .blitzCardRow()
                    }
                    .blitzListStyle()
                }
            }
            .navigationTitle("Add Players")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSelected() }
                        .disabled(selected.isEmpty)
                }
            }
            .alert("Already on a Team", isPresented: conflictAlert, presenting: conflict) { _ in
                Button("OK", role: .cancel) { }
            } message: { conflict in
                Text("\(conflict.playerName) is already assigned to \(conflict.teamName). Remove them from \(conflict.teamName) before adding them to \(team.name).")
            }
        }
    }

    private var conflictAlert: Binding<Bool> {
        Binding(get: { conflict != nil },
                set: { if !$0 { conflict = nil } })
    }

    private func toggle(_ player: Player) {
        // One team per player: if they're already on a different team, block and explain.
        if let currentTeam = player.teams.first(where: { $0 !== team }) {
            conflict = AssignmentConflict(playerName: player.name, teamName: currentTeam.name)
            return
        }
        let id = player.persistentModelID
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func addSelected() {
        for player in allPlayers where selected.contains(player.persistentModelID) {
            team.players.append(player)
        }
        dismiss()
    }
}

/// Describes a blocked add: a player who's already assigned to another team. `Identifiable`
/// so SwiftUI can present it, and it carries just the names we need for the message.
private struct AssignmentConflict: Identifiable {
    let id = UUID()
    let playerName: String
    let teamName: String
}

#Preview {
    let container = try! ModelContainer(
        for: Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let team = Team(name: "Preview Team")
    container.mainContext.insert(team)
    container.mainContext.insert(Player(name: "Available One"))
    container.mainContext.insert(Player(name: "Available Two"))

    return AddExistingPlayerView(team: team)
        .modelContainer(container)
}
