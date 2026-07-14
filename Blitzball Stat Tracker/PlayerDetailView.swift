//
//  PlayerDetailView.swift
//  Blitzball Stat Tracker
//
//  Shows a single player's stat card. For now it's read-only; next we'll add stat entry.
//

import SwiftUI
import SwiftData

struct PlayerDetailView: View {
    // The player to display. `@Bindable` lets us both read this SwiftData object and (later)
    // edit it with two-way bindings — we'll lean on that when we add stat entry.
    @Bindable var player: Player
    @State private var showingEdit = false

    var body: some View {
        List {
            Section("Batting") {
                StatCell(label: "AVG", value: StatFormat.rate(player.careerBatting.battingAverage))
                StatCell(label: "OBP", value: StatFormat.rate(player.careerBatting.onBasePercentage))
                StatCell(label: "SLG", value: StatFormat.rate(player.careerBatting.sluggingPercentage))
                StatCell(label: "OPS", value: StatFormat.rate(player.careerBatting.onBasePlusSlugging))
                StatCell(label: "BB%", value: StatFormat.percent(player.careerBatting.walkRate))
                StatCell(label: "K%", value: StatFormat.percent(player.careerBatting.strikeoutRate))
                StatCell(label: "HBP", value: "\(player.careerBatting.hitByPitch)")
            }

            Section("Pitching") {
                StatCell(label: "ERA", value: StatFormat.ratio(player.careerPitching.earnedRunAverage))
                StatCell(label: "WHIP", value: StatFormat.ratio(player.careerPitching.walksAndHitsPerInning))
                StatCell(label: "K/BB", value: StatFormat.ratio(player.careerPitching.strikeoutToWalkRatio))
                StatCell(label: "BAA", value: StatFormat.rate(player.careerPitching.battingAverageAgainst))
            }
            
          
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditPlayerView(player: player)
        }
    }
}

/// A single labeled stat: the abbreviation on the left, the value on the right.
private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit()) // digits line up neatly column-to-column
                .bold()
        }
    }
}

#Preview {
    // Career stats are derived from finished games, so seed one so the preview isn't all zeros.
    let container = try! ModelContainer(
        for: Player.self, Team.self, Game.self, GameStatLine.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let player = Player(name: "Preview Player", jerseyNumber: 7)
    container.mainContext.insert(player)
    let game = Game(status: .final)
    container.mainContext.insert(game)
    let line = GameStatLine(
        player: player, isHome: true, battingOrder: 0,
        batting: BattingStats(plateAppearances: 100, atBats: 90, hits: 30,
                              doubles: 6, triples: 1, homeRuns: 4, walks: 8, strikeouts: 18),
        pitching: PitchingStats(outsRecorded: 90, earnedRuns: 12, runsAllowed: 12,
                                hitsAllowed: 28, walksAllowed: 9, strikeouts: 34, atBatsAgainst: 115)
    )
    line.game = game
    container.mainContext.insert(line)

    return NavigationStack {
        PlayerDetailView(player: player)
    }
    .modelContainer(container)
}
