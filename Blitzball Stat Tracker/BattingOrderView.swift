//
//  BattingOrderView.swift
//  Blitzball Stat Tracker
//
//  Drag-to-reorder a team's batting order before the game starts. Reordering rewrites each
//  line's battingOrder, which is what the live game uses to advance the lineup.
//

import SwiftUI
import SwiftData

struct BattingOrderView: View {
    @Bindable var game: Game
    let isHome: Bool
    @Environment(\.modelContext) private var modelContext

    private var lines: [GameStatLine] {
        // The team's own batters only — the shared DH always bats last and isn't reordered here.
        game.teamLineup(isHome: isHome)
    }

    var body: some View {
        List {
            Section {
                ForEach(lines) { line in
                    let position = (lines.firstIndex { $0 === line } ?? 0) + 1
                    HStack {
                        Text("\(position).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(line.player?.name ?? "—")
                        Spacer()
                        if let number = line.player?.jerseyNumber {
                            Text("#\(number)").foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Tap Edit, then drag to reorder the batting order.")
            }
        }
        .navigationTitle("Batting Order")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .toolbar {
            EditButton()
        }
        // Make sure the lineup exists / matches the current roster.
        .onAppear { game.syncLineup(isHome: isHome, using: modelContext) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = lines
        ordered.move(fromOffsets: source, toOffset: destination)
        // Rewrite batting order to match the new arrangement.
        for (index, line) in ordered.enumerated() {
            line.battingOrder = index
        }
    }
}
