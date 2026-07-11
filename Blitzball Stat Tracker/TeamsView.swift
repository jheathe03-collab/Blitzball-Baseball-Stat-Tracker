//
//  TeamsView.swift
//  Blitzball Stat Tracker
//
//  Teams feature overview: a Teams list, a Win/Loss leaderboard, and a link to the
//  aggregated All Teams Stats table. Pushed onto the Main Menu's navigation stack.
//

import SwiftUI
import SwiftData

struct TeamsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showingAddTeam = false
    // The team the user swiped to delete, held while we confirm. nil = nothing pending.
    @State private var teamPendingDeletion: Team?

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView(
                    "No Teams Yet",
                    systemImage: "person.3",
                    description: Text("Tap + to add your first team.")
                )
            } else {
                List {
                    // Tap a team to manage its roster.
                    Section("Teams") {
                        ForEach(teams) { team in
                            NavigationLink(destination: TeamDetailView(team: team)) {
                                HStack {
                                    Text(team.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(team.players.count) players")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            // Don't delete yet — stash the team and ask for confirmation first.
                            if let index = offsets.first {
                                teamPendingDeletion = teams[index]
                            }
                        }
                    }

                    // Win/Loss standings (0-0 for now) + a way into the full stats table.
                    Section("Team Leaderboard") {
                        ForEach(teams) { team in
                            HStack {
                                Text(team.name)
                                Spacer()
                                Text("Wins \(team.wins)  Losses \(team.losses)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        NavigationLink(destination: AllTeamsStatsView()) {
                            Label("All Teams Stats", systemImage: "tablecells")
                        }
                    }
                }
            }
        }
        .navigationTitle("Teams")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddTeam = true
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTeam) {
            AddTeamView()
        }
        // Confirm before actually deleting. `presenting:` hands the pending team into the
        // closures so we can name it in the buttons and message.
        .alert("Delete Team?", isPresented: deleteTeamAlert, presenting: teamPendingDeletion) { team in
            Button("Delete \u{201C}\(team.name)\u{201D}", role: .destructive) {
                modelContext.delete(team)
            }
            Button("Cancel", role: .cancel) { }
        } message: { team in
            Text("Are you sure you want to delete \u{201C}\(team.name)\u{201D}? This cannot be undone. (Players stay in your Players list.)")
        }
    }

    /// A Bool binding derived from the optional: true while a team is pending deletion,
    /// and clearing the optional when the alert dismisses.
    private var deleteTeamAlert: Binding<Bool> {
        Binding(get: { teamPendingDeletion != nil },
                set: { if !$0 { teamPendingDeletion = nil } })
    }
}

#Preview {
    NavigationStack {
        TeamsView()
    }
    .modelContainer(for: [Player.self, Team.self], inMemory: true)
}
