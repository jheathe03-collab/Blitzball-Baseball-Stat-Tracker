//
//  LiveStatsView.swift
//  Blitzball Stat Tracker
//
//  The live game's Stats tab: this game's batting and pitching so far, per team.
//
//  Moved off the scoring screen so that screen fits without scrolling. Reuses the same
//  `BattingBox` / `PitchingBox` tables as the finished-game box score, so the numbers are laid out
//  identically live and after the fact.
//
//  Intentionally basic for now — this screen is slated for its own redesign.
//

import SwiftUI
import SwiftData

struct LiveStatsView: View {
    @Bindable var game: Game
    @State private var side: StatSide = .batting
    /// true = home team shown.
    @State private var showingHome = true

    private enum StatSide: Hashable { case batting, pitching }

    private var lines: [GameStatLine] {
        game.statLines
            .filter { $0.isHome == showingHome && !$0.isDH }
            .sorted { $0.battingOrder < $1.battingOrder }
    }
    private var dhLines: [GameStatLine] { game.statLines.filter(\.isDH) }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Team", selection: $showingHome) {
                Text(game.homeTeam?.name ?? "Home").tag(true)
                Text(game.awayTeam?.name ?? "Away").tag(false)
            }
            .pickerStyle(.segmented)

            Picker("Stat", selection: $side) {
                Text("Batting").tag(StatSide.batting)
                Text("Pitching").tag(StatSide.pitching)
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch side {
                    case .batting:
                        BattingBox(lines: lines)
                        if !dhLines.isEmpty {
                            Text("Designated Hitter").font(.headline).foregroundStyle(.white)
                            BattingBox(lines: dhLines, showTotals: false)
                        }
                    case .pitching:
                        let pitchers = lines.filter { $0.pitching.outsRecorded > 0 }
                        if pitchers.isEmpty {
                            Text("No pitching recorded for this team yet.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        } else {
                            PitchingBox(lines: pitchers)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}
