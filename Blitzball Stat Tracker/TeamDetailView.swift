//
//  TeamDetailView.swift
//  Blitzball Stat Tracker
//
//  A team's roster: actions to add players, and the member list (tap a player → their stats).
//

import SwiftUI
import SwiftData

struct TeamDetailView: View {
    // `@Bindable` gives us a live, editable reference to this SwiftData team.
    @Bindable var team: Team

    @State private var showingAddExisting = false
    @State private var showingCreatePlayer = false
    // The member swiped for removal, held while we confirm.
    @State private var memberPendingRemoval: Player?

    // Members shown alphabetically. Sorting a copy for display doesn't change stored order.
    private var sortedMembers: [Player] {
        team.players.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingAddExisting = true
                } label: {
                    Label("Add an Existing Player", systemImage: "person.badge.plus")
                }
                Button {
                    showingCreatePlayer = true
                } label: {
                    Label("Create a New Player", systemImage: "plus.circle")
                }
                // Placeholder for the future League feature.
                Label("League (coming soon)", systemImage: "flag.2.crossed")
                    .foregroundStyle(.secondary)
            }

            Section("Members") {
                if team.players.isEmpty {
                    Text("No players yet — add some above.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedMembers) { player in
                        NavigationLink(destination: PlayerDetailView(player: player)) {
                            HStack {
                                Text(player.name)
                                Spacer()
                                if let number = player.jerseyNumber {
                                    Text("#\(number)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            memberPendingRemoval = sortedMembers[index]
                        }
                    }
                }
            }
        }
        .navigationTitle(team.name)
        // Two sheets: pick existing players, or create a brand-new one that joins this team.
        .sheet(isPresented: $showingAddExisting) {
            AddExistingPlayerView(team: team)
        }
        .sheet(isPresented: $showingCreatePlayer) {
            AddPlayerView(team: team)
        }
        // Confirm before removing a member. This only un-links — the Player record stays.
        .alert("Remove Player?", isPresented: removeMemberAlert, presenting: memberPendingRemoval) { player in
            Button("Remove \(player.name)", role: .destructive) {
                team.players.removeAll { $0 === player }
            }
            Button("Cancel", role: .cancel) { }
        } message: { player in
            Text("Remove \(player.name) from \(team.name)? They will stay in your Players list and keep their stats.")
        }
    }

    private var removeMemberAlert: Binding<Bool> {
        Binding(get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } })
    }
}

#Preview {
    // Build a small in-memory team so the preview has something to show.
    let container = try! ModelContainer(
        for: Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let team = Team(name: "Preview Team")
    let mike = Player(name: "Mike", jerseyNumber: 7)
    team.players.append(mike)
    container.mainContext.insert(team)

    return NavigationStack {
        TeamDetailView(team: team)
    }
    .modelContainer(container)
}
