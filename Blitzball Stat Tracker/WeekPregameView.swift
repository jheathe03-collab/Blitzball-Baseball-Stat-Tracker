//
//  WeekPregameView.swift
//  Blitzball Stat Tracker
//
//  The pre-game screen for one week of a season. The two teams are already fixed by the schedule,
//  so this just lets the user confirm each side's batting order + starting pitcher (and the DH if
//  that option is on) before "Play Ball" launches the shared live game. Season-flavored cousin of
//  the exhibition SelectTeamsView.
//

import SwiftUI
import SwiftData

struct WeekPregameView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @State private var showingDHPicker = false
    @State private var showStartConfirm = false
    @State private var startGame = false

    // Both teams come from the schedule; we just need players to field a lineup.
    private var ready: Bool {
        (game.homeTeam?.players.isEmpty == false) && (game.awayTeam?.players.isEmpty == false)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text("Week \(game.weekNumber)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("\(game.homeTeam?.name ?? "Home") vs \(game.awayTeam?.name ?? "Away")")
                        .font(.title3).bold()
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            teamSection(isHome: true)
            teamSection(isHome: false)

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
                Button {
                    showStartConfirm = true
                } label: {
                    Label("Start Game", systemImage: "play.fill")
                        .fontWeight(.semibold)
                }
                .disabled(!ready)
            } footer: {
                if !ready {
                    Text("Both teams need at least one player. Add players from a team's Edit Roster on the schedule screen.")
                }
            }
        }
        .navigationTitle("Game Day")
        .blitzballBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDHPicker) {
            DesignatedHitterPicker(game: game)
        }
        .navigationDestination(isPresented: $startGame) {
            LiveGameView(game: game)
        }
        .alert("Ready to Play Ball?", isPresented: $showStartConfirm) {
            Button("Play Ball") { startGame = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Start Week \(game.weekNumber): \(game.homeTeam?.name ?? "Home") vs \(game.awayTeam?.name ?? "Away").")
        }
        // Build/refresh both lineups so the cards show the current batting order.
        .onAppear { syncLineups() }
    }

    // One side: numbered lineup card + Batting Order and Starting Pitcher editors.
    @ViewBuilder
    private func teamSection(isHome: Bool) -> some View {
        let team = isHome ? game.homeTeam : game.awayTeam
        let pitcher = isHome ? game.homePitcher : game.awayPitcher
        let lineup = game.teamLineup(isHome: isHome).compactMap(\.player)

        Section(isHome ? "Home" : "Away") {
            WeekTeamCard(team: team, record: record(for: team), lineup: lineup)

            NavigationLink {
                BattingOrderView(game: game, isHome: isHome)
            } label: {
                Label("Batting Order", systemImage: "figure.baseball")
            }
            NavigationLink {
                StartingPitcherView(game: game, isHome: isHome)
            } label: {
                HStack {
                    Label("Starting Pitcher", systemImage: "baseball.fill")
                    Spacer()
                    Text(pitcher?.name ?? "Not set")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // This team's record within THIS season (only its finished weeks count).
    private func record(for team: Team?) -> (wins: Int, losses: Int) {
        guard let team, let season = game.season else { return (0, 0) }
        return team.record(from: season.games)
    }

    private func syncLineups() {
        game.syncLineup(isHome: true, using: modelContext)
        game.syncLineup(isHome: false, using: modelContext)
        game.syncDesignatedHitter(using: modelContext)
    }
}

// MARK: - A team's header card: name + season W-L + numbered lineup

private struct WeekTeamCard: View {
    let team: Team?
    let record: (wins: Int, losses: Int)
    let lineup: [Player]   // in batting order

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(team?.name ?? "—")
                    .font(.title3).bold()
                Spacer()
                Text("Wins \(record.wins)  Losses \(record.losses)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if lineup.isEmpty {
                Text("No players on this team yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(lineup.enumerated()), id: \.element.persistentModelID) { index, player in
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(player.name)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
