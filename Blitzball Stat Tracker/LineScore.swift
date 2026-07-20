//
//  LineScore.swift
//  Blitzball Stat Tracker
//
//  The inning-by-inning score grid (1 2 3 … R H E) for a game. Used two ways:
//  - LIVE (LiveGameView): pass `onAdjust` so each run cell becomes a tap-to-edit menu.
//  - READ-ONLY (GameSummaryView): omit `onAdjust` and the cells render as plain numbers.
//
//  It reads only already-stored data (`homeInningRuns`/`awayInningRuns` on Game), so it works for
//  any finished game with no extra storage.
//

import SwiftUI

struct LineScore: View {
    @Bindable var game: Game
    /// Provide this (live game) to make run cells editable; omit it (summary) for a read-only grid.
    var onAdjust: ((_ isHome: Bool, _ inning: Int, _ delta: Int) -> Void)? = nil

    private var inningCount: Int {
        max(game.currentInning, game.awayInningRuns.count, game.homeInningRuns.count, 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(1...inningCount, id: \.self) { Text("\($0)").bold() }
                    Text("R").bold(); Text("H").bold(); Text("E").bold()
                }
                row(isHome: false, name: game.awayTeam?.name ?? "Away",
                    runs: game.awayInningRuns, total: game.awayScore, hits: game.hits(isHome: false))
                row(isHome: true, name: game.homeTeam?.name ?? "Home",
                    runs: game.homeInningRuns, total: game.homeScore, hits: game.hits(isHome: true))
            }
            .font(.subheadline.monospacedDigit())
        }
    }

    private func row(isHome: Bool, name: String, runs: [Int], total: Int, hits: Int) -> some View {
        GridRow {
            Text(name).bold().lineLimit(1).gridColumnAlignment(.leading)
            ForEach(0..<inningCount, id: \.self) { i in
                if i < runs.count {
                    if let onAdjust {
                        Menu {
                            Button("Add Run") { onAdjust(isHome, i, 1) }
                            Button("Remove Run") { onAdjust(isHome, i, -1) }
                        } label: {
                            Text("\(runs[i])")
                        }
                    } else {
                        Text("\(runs[i])")
                    }
                } else {
                    Text("")
                }
            }
            Text("\(total)").bold()
            Text("\(hits)")
            Text("0") // errors not tracked yet
        }
    }
}
