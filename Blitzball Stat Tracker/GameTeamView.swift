//
//  GameTeamView.swift
//  Blitzball Stat Tracker
//
//  One team as it stands in THIS game: the batting order actually in use, plus the full roster,
//  with a link out to Edit Roster for adding or removing players.
//
//  The lineup and the roster aren't the same list — a substituted-out player keeps his stats and
//  leaves the order, and a rostered player who isn't in the order won't appear in it. Showing both
//  makes that difference visible mid-game.
//

import SwiftUI
import SwiftData

struct GameTeamView: View {
    @Bindable var game: Game
    /// Which side this screen is showing.
    let isHome: Bool
    @State private var showSubstitution = false

    private var team: Team? { isHome ? game.homeTeam : game.awayTeam }

    /// The batting order in use, in order — reflects substitutions.
    private var lineup: [GameStatLine] { game.lineup(isHome: isHome) }

    /// The team's own batters (reorderable). The shared DH always bats last and isn't reordered.
    private var teamBatters: [GameStatLine] { game.teamLineup(isHome: isHome) }
    private var dhLine: GameStatLine? { lineup.first { $0.isDH } }

    /// Players on the team who aren't in the batting order (bench, or subbed out).
    private var bench: [Player] {
        let inLineup = lineup.compactMap(\.player)
        return (team?.players ?? [])
            .filter { player in !inLineup.contains { $0 === player } }
            .sorted { $0.name < $1.name }
    }

    private var pitcher: Player? { isHome ? game.homePitcher : game.awayPitcher }

    var body: some View {
        List {
            Section {
                HStack {
                    TeamLogoView(team: team, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team?.name ?? (isHome ? "Home" : "Away"))
                            .font(.title3.bold()).foregroundStyle(.white)
                        Text(isHome ? "Home" : "Away")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if let pitcher {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Pitching").font(.caption).foregroundStyle(.white.opacity(0.6))
                            Text(pitcher.name).font(.subheadline).foregroundStyle(.white)
                        }
                    }
                }
            }
            .blitzCardRow()

            Section {
                if teamBatters.isEmpty {
                    Text("No batting order set.").foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(teamBatters) { line in
                        batterRow(line, position: (teamBatters.firstIndex { $0 === line } ?? 0) + 1)
                    }
                    .onMove(perform: moveBatters)
                }
                // The shared DH bats last and isn't part of the reorder.
                if let dhLine {
                    batterRow(dhLine, position: teamBatters.count + 1)
                }
            } header: {
                Text("Batting Order").foregroundStyle(.white)
            } footer: {
                Text("Tap Edit, then drag to reorder. The batting spot stays put — whoever you move "
                     + "into it hits next.")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .blitzCardRow()

            if !bench.isEmpty {
                Section {
                    ForEach(bench, id: \.persistentModelID) { player in
                        HStack {
                            Text(player.name).foregroundStyle(.white)
                            Spacer()
                            if let number = player.jerseyNumber {
                                Text("#\(number)").foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                } header: {
                    Text("Not in the Order").foregroundStyle(.white)
                } footer: {
                    Text("On the roster but not batting — subbed out, or never added to the order.")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .blitzCardRow()
            }

            if let team {
                Section {
                    NavigationLink {
                        TeamDetailView(team: team)
                    } label: {
                        Label("Edit Roster", systemImage: "square.and.pencil")
                    }
                    Button {
                        showSubstitution = true
                    } label: {
                        Label("Substitute Player", systemImage: "arrow.left.arrow.right")
                    }
                } footer: {
                    Text("Edit Roster changes the team everywhere. Substitute Player swaps someone in "
                         + "or out of the batting order for this game only.")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .blitzCardRow()
            }
        }
        .sheet(isPresented: $showSubstitution) {
            SubstitutionView(game: game)
        }
        .blitzListStyle()
        .navigationTitle(team?.name ?? (isHome ? "Home" : "Away"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    /// One batting-order row: spot number, name, the "at bat" badge, and jersey number.
    private func batterRow(_ line: GameStatLine, position: Int) -> some View {
        HStack {
            Text("\(position).")
                .foregroundStyle(.white.opacity(0.5)).monospacedDigit()
            Text(line.player?.name ?? "—").foregroundStyle(.white)
            if line.player === game.currentBatterLine?.player {
                Text("at bat")
                    .font(.caption2).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.yellow, in: Capsule())
            }
            Spacer()
            if let number = line.player?.jerseyNumber {
                Text("#\(number)").foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// Reorder the team's batters and rewrite each line's `battingOrder`. The current-batter pointer
    /// is a fixed slot, so whoever lands in that spot bats next (no pointer follow, by design).
    private func moveBatters(from source: IndexSet, to destination: Int) {
        var ordered = teamBatters
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, line) in ordered.enumerated() {
            line.battingOrder = index
        }
    }
}
