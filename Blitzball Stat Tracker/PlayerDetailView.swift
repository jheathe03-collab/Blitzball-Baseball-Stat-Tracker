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

    var body: some View {
        List {
            Section("Batting") {
                StatCell(label: "AVG", value: StatFormat.rate(player.batting.battingAverage))
                StatCell(label: "OBP", value: StatFormat.rate(player.batting.onBasePercentage))
                StatCell(label: "SLG", value: StatFormat.rate(player.batting.sluggingPercentage))
                StatCell(label: "OPS", value: StatFormat.rate(player.batting.onBasePlusSlugging))
                StatCell(label: "BB%", value: StatFormat.percent(player.batting.walkRate))
                StatCell(label: "K%", value: StatFormat.percent(player.batting.strikeoutRate))
                StatCell(label: "HBP", value: "\(player.batting.hitByPitch)")
            }

            Section("Pitching") {
                StatCell(label: "ERA", value: StatFormat.ratio(player.pitching.earnedRunAverage))
                StatCell(label: "WHIP", value: StatFormat.ratio(player.pitching.walksAndHitsPerInning))
                StatCell(label: "K/BB", value: StatFormat.ratio(player.pitching.strikeoutToWalkRatio))
                StatCell(label: "BAA", value: StatFormat.rate(player.pitching.battingAverageAgainst))
            }
            
          
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.large)
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
    // A little sample data so the preview isn't all zeros.
    let sample = Player(
        name: "Preview Player",
        jerseyNumber: 7,
        batting: BattingStats(plateAppearances: 100, atBats: 90, hits: 30,
                              doubles: 6, triples: 1, homeRuns: 4,
                              walks: 8, strikeouts: 18),
        pitching: PitchingStats(outsRecorded: 90, earnedRuns: 12, hitsAllowed: 28,
                                walksAllowed: 9, strikeouts: 34, atBatsAgainst: 115)
    )
    return NavigationStack {
        PlayerDetailView(player: sample)
    }
}
