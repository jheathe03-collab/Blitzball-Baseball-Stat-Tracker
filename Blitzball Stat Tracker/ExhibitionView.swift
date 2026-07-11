//
//  ExhibitionView.swift
//  Blitzball Stat Tracker
//
//  Exhibition, Phase 1: pick a Home and Away team for a one-off game. "Start Game" (live
//  stat tracking) comes next; for now it's gated and opens a placeholder.
//

import SwiftUI
import SwiftData

// MARK: - Entry point: find-or-create the current setup game

struct ExhibitionView: View {
    @Environment(\.modelContext) private var modelContext
    // The in-setup game we're configuring. Loaded/created once when the screen appears.
    @State private var game: Game?

    var body: some View {
        Group {
            if let game {
                SelectTeamsView(game: game)
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: loadOrCreateGame)
    }

    /// Reuse the existing setup game so team picks survive leaving the screen; otherwise make one.
    private func loadOrCreateGame() {
        guard game == nil else { return }
        let descriptor = FetchDescriptor<Game>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let games = (try? modelContext.fetch(descriptor)) ?? []
        if let existingSetup = games.first(where: { $0.status == .setup }) {
            game = existingSetup
        } else {
            let newGame = Game()
            modelContext.insert(newGame)
            game = newGame
        }
    }
}

// MARK: - Which slot we're filling

enum TeamRole: String, Identifiable {
    case home, away
    var id: String { rawValue }
    var title: String { self == .home ? "Home Team" : "Away Team" }
    var placeholder: String { self == .home ? "Select Home Team" : "Select Away Team" }
}

// MARK: - The Select Teams screen

struct SelectTeamsView: View {
    @Bindable var game: Game
    // Non-nil while the team picker sheet is open; also tells us which slot to fill.
    @State private var picking: TeamRole?

    private var bothTeamsChosen: Bool {
        game.homeTeam != nil && game.awayTeam != nil
    }

    var body: some View {
        List {
            Section {
                TeamSlot(role: .home, team: game.homeTeam,
                         onSelect: { picking = .home },
                         onClear: { game.homeTeam = nil })
            }
            Section {
                TeamSlot(role: .away, team: game.awayTeam,
                         onSelect: { picking = .away },
                         onClear: { game.awayTeam = nil })
            }

            Section {
                // Jump into the Teams area; returning (back) keeps our picks intact.
                NavigationLink {
                    TeamsView()
                } label: {
                    Label("Edit Teams", systemImage: "pencil")
                }

                // The game's rulebook. Always available, regardless of team selection.
                // The trailing subheadline shows the chosen preset (or "Custom").
                NavigationLink {
                    GameOptionsView(game: game)
                } label: {
                    HStack {
                        Label("Game Options", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(game.settings.matchedType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Gated until both teams are chosen. Placeholder destination for now.
                NavigationLink {
                    ComingSoonView(title: "Start Game", systemImage: "baseball.fill")
                } label: {
                    Label("Start Game", systemImage: "play.fill")
                        .fontWeight(.semibold)
                }
                .disabled(!bothTeamsChosen)
            } footer: {
                if !bothTeamsChosen {
                    Text("Pick a Home and Away team to start the game.")
                }
            }
        }
        .navigationTitle("Select Teams")
        // One sheet serves both slots; `item:` passes in which role we're filling.
        .sheet(item: $picking) { role in
            TeamPickerView(excluding: role == .home ? game.awayTeam : game.homeTeam) { team in
                switch role {
                case .home: game.homeTeam = team
                case .away: game.awayTeam = team
                }
            }
        }
    }
}

// MARK: - One team slot (header + Select button + filled card or placeholder)

struct TeamSlot: View {
    let role: TeamRole
    let team: Team?
    let onSelect: () -> Void
    let onClear: () -> Void

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(role.title)
                    .font(.headline)
                Spacer()
                // Only shown once a team is chosen. Clearing reveals the "+ Select ..." card
                // again, which is now the single way to pick a team.
                if team != nil {
                    Button("Clear Selection", action: onClear)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }

            if let team {
                filledCard(team)
            } else {
                placeholderCard
            }
        }
        .padding(.vertical, 4)
    }

    // The card shown once a team is chosen: name + W-L + roster grid.
    // (Future: this card is where a horizontal stat expansion could live.)
    private func filledCard(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(team.name)
                    .font(.title3).bold()
                Spacer()
                Text("Wins \(team.wins)  Losses \(team.losses)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if team.players.isEmpty {
                Text("No players on this team yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(team.players.sorted { $0.name < $1.name }) { player in
                        Label(player.name, systemImage: "person.fill")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // The tappable "empty" state prompting a selection.
    private var placeholderCard: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "plus")
                Text(role.placeholder)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Game.self, Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let home = Team(name: "Sluggers")
    home.players.append(Player(name: "Mike", jerseyNumber: 7))
    home.players.append(Player(name: "Sam"))
    container.mainContext.insert(home)
    container.mainContext.insert(Team(name: "Mashers"))
    let game = Game(homeTeam: home)
    container.mainContext.insert(game)

    return NavigationStack {
        SelectTeamsView(game: game)
    }
    .modelContainer(container)
}
