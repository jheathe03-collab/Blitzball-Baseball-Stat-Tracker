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
        // Only reuse an EXHIBITION draft. Season/tournament games are also created as `.setup`
        // (scheduled weeks), so without the mode check Exhibition could hijack an unplayed season
        // week — and finishing it would wrongly mark that week as played.
        if let existingSetup = games.first(where: { $0.status == .setup && $0.mode == .exhibition }) {
            game = existingSetup
        } else {
            let newGame = Game()   // defaults to mode == .exhibition
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
    @Environment(\.modelContext) private var modelContext
    @Query private var allGames: [Game]   // for deriving each team's W-L
    // Non-nil while the team picker sheet is open; also tells us which slot to fill.
    @State private var picking: TeamRole?
    @State private var showingDHPicker = false
    @State private var showStartConfirm = false
    @State private var startGame = false
    @State private var showPitcherWarning = false

    private var bothTeamsChosen: Bool {
        game.homeTeam != nil && game.awayTeam != nil
    }

    private var pitcherWarningMessage: String {
        var missing: [String] = []
        if game.homePitcher == nil { missing.append(game.homeTeam?.name ?? "the home team") }
        if game.awayPitcher == nil { missing.append(game.awayTeam?.name ?? "the away team") }
        let teams = missing.joined(separator: " and ")
        let what = game.settings.forcePitcherRotation ? "pitching rotation" : "starting pitcher"
        return "Set a \(what) for \(teams) before starting the game."
    }

    /// Starting Pitcher — or the Pitching Rotation editor when Force Pitcher Rotation is on.
    @ViewBuilder
    private func pitcherRow(isHome: Bool) -> some View {
        if game.settings.forcePitcherRotation {
            NavigationLink {
                PitchingRotationView(game: game, isHome: isHome)
            } label: {
                HStack {
                    Label("Pitching Rotation", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(rotationLabel(isHome: isHome))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }
        } else {
            NavigationLink {
                StartingPitcherView(game: game, isHome: isHome)
            } label: {
                HStack {
                    Label("Starting Pitcher", systemImage: "baseball.fill")
                    Spacer()
                    Text((isHome ? game.homePitcher : game.awayPitcher)?.name ?? "Not set")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rotationLabel(isHome: Bool) -> String {
        let count = game.pitchingRotation(isHome: isHome).count
        return count == 0 ? "Not set" : "\(count) pitcher\(count == 1 ? "" : "s")"
    }

    var body: some View {
        List {
            Section {
                TeamSlot(role: .home, team: game.homeTeam, games: allGames,
                         lineup: game.teamLineup(isHome: true).compactMap(\.player),
                         onSelect: { picking = .home },
                         onClear: { game.homeTeam = nil; game.homePitcher = nil; syncLineups() })
                if game.homeTeam != nil {
                    NavigationLink {
                        BattingOrderView(game: game, isHome: true)
                    } label: {
                        Label("Batting Order", systemImage: "figure.baseball")
                    }
                    pitcherRow(isHome: true)
                }
            }
            Section {
                TeamSlot(role: .away, team: game.awayTeam, games: allGames,
                         lineup: game.teamLineup(isHome: false).compactMap(\.player),
                         onSelect: { picking = .away },
                         onClear: { game.awayTeam = nil; game.awayPitcher = nil; syncLineups() })
                if game.awayTeam != nil {
                    NavigationLink {
                        BattingOrderView(game: game, isHome: false)
                    } label: {
                        Label("Batting Order", systemImage: "figure.baseball")
                    }
                    pitcherRow(isHome: false)
                }
            }

            // The neutral Designated Hitter (only when that Game Option is on).
            if game.settings.designatedHitter {
                Section("Designated Hitter") {
                    if let dh = game.designatedHitter {
                        HStack {
                            Label(dh.name, systemImage: "star.fill")
                            Spacer()
                            Button("Clear") {
                                game.designatedHitter = nil
                                syncLineups()
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    Button {
                        showingDHPicker = true
                    } label: {
                        Label(game.designatedHitter == nil ? "Select Designated Hitter" : "Change Designated Hitter",
                              systemImage: "person.badge.plus")
                    }
                }
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
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                // Gated until both teams are chosen. Also requires a starting pitcher per side.
                Button {
                    if game.homePitcher == nil || game.awayPitcher == nil {
                        showPitcherWarning = true
                    } else {
                        showStartConfirm = true
                    }
                } label: {
                    Label("Start Game", systemImage: "play.fill")
                        .fontWeight(.semibold)
                }
                .disabled(!bothTeamsChosen)
            } footer: {
                if !bothTeamsChosen {
                    Text("Pick a Home and Away team to start the game.")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("Select Teams")
        .blitzballBackground()
        // One sheet serves both slots; `item:` passes in which role we're filling.
        .sheet(item: $picking) { role in
            TeamPickerView(excluding: role == .home ? game.awayTeam : game.homeTeam) { team in
                switch role {
                case .home: game.homeTeam = team; game.homePitcher = nil
                case .away: game.awayTeam = team; game.awayPitcher = nil
                }
                syncLineups()
            }
        }
        .sheet(isPresented: $showingDHPicker) {
            DesignatedHitterPicker(game: game)
        }
        .navigationDestination(isPresented: $startGame) {
            LiveGameView(game: game)
        }
        .alert("Settings look good?", isPresented: $showStartConfirm) {
            Button("Start Game") { startGame = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Starting a \(game.settings.matchedType.displayName) game.")
        }
        .alert("Set a Starting Pitcher", isPresented: $showPitcherWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pitcherWarningMessage)
        }
        // Build/refresh both lineups so the team cards show the current batting order.
        .onAppear { syncLineups() }
    }

    /// Keep both lineups (and the DH) in sync with the current selections.
    private func syncLineups() {
        game.syncLineup(isHome: true, using: modelContext)
        game.syncLineup(isHome: false, using: modelContext)
        game.syncDesignatedHitter(using: modelContext)
    }
}

// MARK: - One team slot (header + Select button + filled card or placeholder)

struct TeamSlot: View {
    let role: TeamRole
    let team: Team?
    let games: [Game]
    let lineup: [Player]   // in batting order
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
        let record = team.record(from: games)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TeamLogoView(team: team, size: 32)
                Text(team.name)
                    .font(.title3).bold()
                Spacer()
                Text("Wins \(record.wins)  Losses \(record.losses)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .monospacedDigit()
            }

            if lineup.isEmpty {
                Text("No players on this team yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                // Players shown in batting order (updates when you edit Batting Order).
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(lineup.enumerated()), id: \.element.persistentModelID) { index, player in
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .monospacedDigit()
                            Text(player.name)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // The tappable "empty" state prompting a selection.
    private var placeholderCard: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "plus")
                Text(role.placeholder)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Game.self, Team.self, Player.self, GameStatLine.self,
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
