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
    @Environment(\.modelContext) private var modelContext
    // All games, so we can show just this team's history (filtered below).
    @Query private var allGames: [Game]

    @State private var showingAddExisting = false
    @State private var showingCreatePlayer = false
    @State private var showingLogoPicker = false
    @State private var showingRename = false
    // The member swiped for removal, held while we confirm.
    @State private var memberPendingRemoval: Player?
    // A game swiped for deletion in this team's Game History, held while we confirm.
    @State private var gameToDelete: Game?

    // Members shown alphabetically. Sorting a copy for display doesn't change stored order.
    private var sortedMembers: [Player] {
        team.players.sorted { $0.name < $1.name }
    }

    /// This team's played games (finished or in-progress; drafts excluded), newest first.
    private var teamGames: [Game] {
        allGames
            .filter { $0.status != .setup && ($0.homeTeam === team || $0.awayTeam === team) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            // Team logo header — tap to choose/change the logo.
            Section {
                Button {
                    showingLogoPicker = true
                } label: {
                    HStack(spacing: 14) {
                        TeamLogoView(team: team, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name).font(.title3).bold().foregroundStyle(.white)
                            Text(team.logoName == nil && team.logoImageData == nil ? "Add a logo" : "Change logo")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }
            .blitzCardRow()

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
            }
            .blitzCardRow()

            Section(header: Text("Members").foregroundStyle(.white)) {
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
            .blitzCardRow()

            // This team's played games — tap to open a box score; swipe to delete (not season games).
            if !teamGames.isEmpty {
                Section {
                    ForEach(teamGames, id: \.persistentModelID) { game in
                        NavigationLink(destination: GameSummaryView(game: game)) {
                            GameHistoryRow(game: game)
                        }
                        .swipeActions(edge: .trailing) {
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
                        .foregroundStyle(.white.opacity(0.6))
                }
                .blitzCardRow()
            }
        }
        .blitzListStyle()
        .navigationTitle(team.name)
        .blitzballBackground()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingRename = true
                } label: {
                    Label("Rename Team", systemImage: "pencil")
                }
            }
        }
        // Two sheets: pick existing players, or create a brand-new one that joins this team.
        .sheet(isPresented: $showingAddExisting) {
            AddExistingPlayerView(team: team)
        }
        .sheet(isPresented: $showingCreatePlayer) {
            AddPlayerView(team: team)
        }
        .sheet(isPresented: $showingLogoPicker) {
            TeamLogoPicker(logoName: $team.logoName, logoImageData: $team.logoImageData)
        }
        .sheet(isPresented: $showingRename) {
            EditTeamView(team: team)
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
        // Confirm deleting a game from this team's Game History.
        .alert("Delete Game?", isPresented: gameDeleteAlert, presenting: gameToDelete) { _ in
            Button("Delete Game", role: .destructive) {
                if let game = gameToDelete { modelContext.delete(game) }
                gameToDelete = nil
            }
            Button("Cancel", role: .cancel) { gameToDelete = nil }
        } message: { _ in
            Text("This permanently deletes this game and everyone's stats from it. This can't be undone.")
        }
    }

    private var removeMemberAlert: Binding<Bool> {
        Binding(get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } })
    }

    private var gameDeleteAlert: Binding<Bool> {
        Binding(get: { gameToDelete != nil }, set: { if !$0 { gameToDelete = nil } })
    }
}

#Preview {
    // Build a small in-memory team so the preview has something to show.
    let container = try! ModelContainer(
        for: Team.self, Player.self, Game.self, GameStatLine.self, Season.self,
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
