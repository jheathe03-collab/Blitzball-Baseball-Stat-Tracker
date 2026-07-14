//
//  TeamPickerView.swift
//  Blitzball Stat Tracker
//
//  A sheet for choosing a team. Reusable for both the Home and Away slots.
//

import SwiftUI
import SwiftData

struct TeamPickerView: View {
    /// A team to leave out of the list (the one already chosen for the other slot), so the
    /// same team can't be picked for both sides.
    let excluding: Team?
    /// Called with the chosen team; the caller stores it and we dismiss.
    let onSelect: (Team) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showingAddTeam = false

    private var selectableTeams: [Team] {
        teams.filter { $0 !== excluding }
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectableTeams.isEmpty {
                    ContentUnavailableView {
                        Label("No Teams to Pick", systemImage: "person.3")
                    } description: {
                        Text("Create a team to add here.")
                    } actions: {
                        Button("Create Team") { showingAddTeam = true }
                    }
                } else {
                    List(selectableTeams) { team in
                        Button {
                            onSelect(team)
                            dismiss()
                        } label: {
                            HStack {
                                Text(team.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(team.players.count) players")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddTeam = true } label: {
                        Label("New Team", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTeam) {
                AddTeamView()
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Team(name: "Sluggers"))
    container.mainContext.insert(Team(name: "Mashers"))

    return TeamPickerView(excluding: nil) { _ in }
        .modelContainer(container)
}
