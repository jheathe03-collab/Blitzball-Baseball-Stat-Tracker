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
    @Query private var games: [Game]   // for deriving each team's W-L
    @State private var showingAddTeam = false
    // The team the user swiped to delete, held while we confirm. nil = nothing pending.
    @State private var teamPendingDeletion: Team?
    // A team the user tried to delete while it's still used by a game (blocked to avoid a crash).
    @State private var teamInUse: Team?

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView(
                    "No Teams Yet",
                    systemImage: "person.3",
                    description: Text("Tap + to add your first team.")
                )
                .foregroundStyle(.white)
            } else {
                List {
                    // Tap a team to manage its roster.
                    Section(header: Text("Teams").foregroundStyle(.white)) {
                        ForEach(teams) { team in
                            NavigationLink(destination: TeamDetailView(team: team)) {
                                HStack {
                                    TeamLogoView(team: team, size: 28)
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
                            guard let index = offsets.first else { return }
                            let team = teams[index]
                            // A team referenced by any game (season or exhibition) can't be deleted:
                            // SwiftData would leave those games pointing at a deleted object → crash.
                            if gamesUsing(team).isEmpty {
                                teamPendingDeletion = team   // safe — ask to confirm
                            } else {
                                teamInUse = team             // blocked — explain why
                            }
                        }
                    }
                    .blitzCardRow()

                    // Win/Loss standings (0-0 for now) + a way into the full stats table.
                    Section(header: Text("Team Leaderboard").foregroundStyle(.white)) {
                        ForEach(teams) { team in
                            let record = team.record(from: games)
                            HStack {
                                TeamLogoView(team: team, size: 24)
                                Text(team.name)
                                Spacer()
                                Text("Wins \(record.wins)  Losses \(record.losses)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        NavigationLink(destination: AllTeamsStatsView()) {
                            Label("Stat Leaders", systemImage: "chart.bar")
                        }
                    }
                    .blitzCardRow()
                }
                .blitzListStyle()
            }
        }
        .navigationTitle("Teams")
        .blitzballBackground()
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
        // Blocked deletion: the team is still used by a game/season.
        .alert("Can't Delete Team", isPresented: teamInUseAlert, presenting: teamInUse) { _ in
            Button("OK", role: .cancel) { }
        } message: { team in
            Text(inUseMessage(for: team))
        }
    }

    /// Games (season or exhibition) that still reference this team on either side.
    private func gamesUsing(_ team: Team) -> [Game] {
        games.filter { $0.homeTeam === team || $0.awayTeam === team }
    }

    private func inUseMessage(for team: Team) -> String {
        let using = gamesUsing(team)
        let seasons = Set(using.compactMap(\.season))
        if !seasons.isEmpty {
            let names = seasons
                .map { $0.name.isEmpty ? "an unnamed season" : "\u{201C}\($0.name)\u{201D}" }
                .sorted()
                .joined(separator: ", ")
            return "\(team.name) is used in \(names). Remove it from those matchups (or delete the season) before deleting the team."
        }
        return "\(team.name) is used in \(using.count) game\(using.count == 1 ? "" : "s"). Delete those games before deleting the team."
    }

    private var teamInUseAlert: Binding<Bool> {
        Binding(get: { teamInUse != nil }, set: { if !$0 { teamInUse = nil } })
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
