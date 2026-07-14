//
//  StartingPitcherView.swift
//  Blitzball Stat Tracker
//
//  Choose a team's starting pitcher during setup. Sets game.homePitcher / awayPitcher, which the
//  live game uses as that side's pitcher from the first pitch.
//

import SwiftUI
import SwiftData

struct StartingPitcherView: View {
    @Bindable var game: Game
    let isHome: Bool
    @Environment(\.dismiss) private var dismiss

    private var lines: [GameStatLine] { game.teamLineup(isHome: isHome) }
    private var current: Player? { isHome ? game.homePitcher : game.awayPitcher }

    var body: some View {
        List(lines) { line in
            Button {
                if isHome { game.homePitcher = line.player } else { game.awayPitcher = line.player }
                dismiss()
            } label: {
                HStack {
                    Text(line.player?.name ?? "—").foregroundStyle(.primary)
                    Spacer()
                    if line.player === current {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle("Starting Pitcher")
        .navigationBarTitleDisplayMode(.inline)
    }
}
