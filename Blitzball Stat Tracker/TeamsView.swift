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
    // A game swiped for deletion in the Game History list, held while we confirm.
    @State private var gameToDelete: Game?

    /// Played games (finished or in-progress) across the whole league, newest first — the drafts
    /// (setup weeks / unstarted exhibitions) are excluded.
    private var playedGames: [Game] {
        games.filter { $0.status != .setup }
            .sorted { $0.createdAt > $1.createdAt }
    }

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
                                    TeamLogoView(logoName: team.logoName, size: 28)
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
                                TeamLogoView(logoName: team.logoName, size: 24)
                                Text(team.name)
                                Spacer()
                                Text("Wins \(record.wins)  Losses \(record.losses)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        NavigationLink(destination: AllTeamsStatsView()) {
                            Label("All Teams Stats", systemImage: "tablecells")
                        }
                    }
                    .blitzCardRow()

                    // Every played game — tap to open its box score (Game Summary).
                    if !playedGames.isEmpty {
                        Section {
                            ForEach(playedGames, id: \.persistentModelID) { game in
                                NavigationLink(destination: GameSummaryView(game: game)) {
                                    gameRow(game)
                                }
                                .swipeActions(edge: .trailing) {
                                    // Season games are removed via the season, not one at a time.
                                    if game.season == nil {
                                        Button(role: .destructive) { gameToDelete = game } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Game History").foregroundStyle(.white)
                        } footer: {
                            Text("Tap a game to see its summary. Swipe an exhibition or tournament game to delete it.")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .blitzCardRow()
                    }
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
        // Confirm deleting a game from the Game History list.
        .alert("Delete Game?", isPresented: gameDeleteAlert, presenting: gameToDelete) { game in
            Button("Delete Game", role: .destructive) {
                modelContext.delete(game)
                gameToDelete = nil
            }
            Button("Cancel", role: .cancel) { gameToDelete = nil }
        } message: { _ in
            Text("This permanently deletes this game and everyone's stats from it. This can't be undone.")
        }
    }

    // MARK: - Game history rows

    private func gameRow(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(game.homeTeam?.name ?? "Home") \(game.homeScore)–\(game.awayScore) \(game.awayTeam?.name ?? "Away")")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(gameSubtitle(game))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func gameSubtitle(_ game: Game) -> String {
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

    private var gameDeleteAlert: Binding<Bool> {
        Binding(get: { gameToDelete != nil }, set: { if !$0 { gameToDelete = nil } })
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
