//
//  PitchingRotationView.swift
//  Blitzball Stat Tracker
//
//  Set a team's pitching rotation (for the Force Pitcher Rotation option): pick which players pitch
//  and drag them into order. The order is stored on each GameStatLine's `pitchingOrder`; the live
//  game auto-advances to the next entry every inning (looping after the last). The first entry is
//  the team's starting pitcher.
//

import SwiftUI
import SwiftData

struct PitchingRotationView: View {
    @Bindable var game: Game
    let isHome: Bool
    @Environment(\.modelContext) private var modelContext

    private var teamLines: [GameStatLine] { game.teamLineup(isHome: isHome) }

    private var rotationLines: [GameStatLine] {
        teamLines.filter { $0.pitchingOrder >= 0 }.sorted { $0.pitchingOrder < $1.pitchingOrder }
    }
    private var availableLines: [GameStatLine] {
        teamLines.filter { $0.pitchingOrder < 0 }
    }

    var body: some View {
        List {
            Section {
                if rotationLines.isEmpty {
                    Text("No pitchers yet — add some from below.")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(Array(rotationLines.enumerated()), id: \.element.persistentModelID) { index, line in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.white.opacity(0.6))
                                .monospacedDigit()
                            Text(line.player?.name ?? "—").foregroundStyle(.white)
                            Spacer()
                            if let number = line.player?.jerseyNumber {
                                Text("#\(number)").foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
            } header: {
                Text("Rotation").foregroundStyle(.white)
            } footer: {
                Text("Each inning the next pitcher takes the mound; after the last it loops back to the top. The first pitcher starts the game. Tap Edit to reorder or remove.")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .blitzCardRow()

            if !availableLines.isEmpty {
                Section(header: Text("Add a Pitcher").foregroundStyle(.white)) {
                    ForEach(availableLines) { line in
                        Button { add(line) } label: {
                            HStack {
                                Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                                Text(line.player?.name ?? "—").foregroundStyle(.white)
                                Spacer()
                                if let number = line.player?.jerseyNumber {
                                    Text("#\(number)").foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .blitzCardRow()
            }
        }
        .blitzListStyle()
        .navigationTitle("Pitching Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .toolbar { EditButton() }
        .onAppear { game.syncLineup(isHome: isHome, using: modelContext) }
    }

    // MARK: - Mutations (renumber contiguously, then keep the starting pitcher in sync)

    private func add(_ line: GameStatLine) {
        line.pitchingOrder = rotationLines.count   // append to the end
        syncStartingPitcher()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = rotationLines
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, line) in ordered.enumerated() { line.pitchingOrder = index }
        syncStartingPitcher()
    }

    private func remove(at offsets: IndexSet) {
        var ordered = rotationLines
        for index in offsets { ordered[index].pitchingOrder = -1 }
        ordered.remove(atOffsets: offsets)
        for (index, line) in ordered.enumerated() { line.pitchingOrder = index }
        syncStartingPitcher()
    }

    /// The first rotation entry is the starting pitcher for this side.
    private func syncStartingPitcher() {
        let first = rotationLines.first?.player
        if isHome { game.homePitcher = first } else { game.awayPitcher = first }
    }
}
