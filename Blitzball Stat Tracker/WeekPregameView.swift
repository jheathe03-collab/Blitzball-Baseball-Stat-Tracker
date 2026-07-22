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
    @State private var showPitcherWarning = false

    // Both teams come from the schedule; we just need players to field a lineup.
    private var ready: Bool {
        (game.homeTeam?.players.isEmpty == false) && (game.awayTeam?.players.isEmpty == false)
    }

    private var pitcherWarningMessage: String {
        var missing: [String] = []
        if game.homePitcher == nil { missing.append(game.homeTeam?.name ?? "the home team") }
        if game.awayPitcher == nil { missing.append(game.awayTeam?.name ?? "the away team") }
        let teams = missing.joined(separator: " and ")
        let what = game.settings.forcePitcherRotation ? "pitching rotation" : "starting pitcher"
        return "Set a \(what) for \(teams) before starting the game."
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

            // Per-game rulebook. Each week's game carries its OWN settings copy, so tweaking these
            // affects only this game — never other weeks or games already played.
            Section {
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
            } footer: {
                Text("Rules for this game only — changing them here won't affect other weeks or games already played.")
                    .foregroundStyle(.white.opacity(0.6))
            }

            Section {
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
                .disabled(!ready)
            } footer: {
                if !ready {
                    Text("Both teams need at least one player. Use Edit Roster above to add players.")
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
        .alert("Set a Starting Pitcher", isPresented: $showPitcherWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pitcherWarningMessage)
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

            // Add/remove players for game day without leaving this screen. The lineup refreshes
            // via syncLineups() when we return (see .onAppear).
            EditRosterLink(team: team)

            NavigationLink {
                BattingOrderView(game: game, isHome: isHome)
            } label: {
                Label("Batting Order", systemImage: "figure.baseball")
            }
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
                        Text(pitcher?.name ?? "Not set")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func rotationLabel(isHome: Bool) -> String {
        let count = game.pitchingRotation(isHome: isHome).count
        return count == 0 ? "Not set" : "\(count) pitcher\(count == 1 ? "" : "s")"
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
                TeamLogoView(team: team, size: 32)
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
