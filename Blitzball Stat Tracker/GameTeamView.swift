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

    private var team: Team? { isHome ? game.homeTeam : game.awayTeam }

    /// The batting order in use, in order — reflects substitutions.
    private var lineup: [GameStatLine] { game.lineup(isHome: isHome) }

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
                if lineup.isEmpty {
                    Text("No batting order set.").foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(Array(lineup.enumerated()), id: \.element.persistentModelID) { index, line in
                        HStack {
                            Text("\(index + 1).")
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
                }
            } header: {
                Text("Batting Order").foregroundStyle(.white)
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
                } footer: {
                    Text("Adding or removing players changes the team everywhere. To swap someone "
                         + "mid-game, use Substitute Player from the game menu.")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .blitzCardRow()
            }
        }
        .blitzListStyle()
        .navigationTitle(team?.name ?? (isHome ? "Home" : "Away"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
