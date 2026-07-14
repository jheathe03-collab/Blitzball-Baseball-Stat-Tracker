//
//  SubstitutionView.swift
//  Blitzball Stat Tracker
//
//  Swap a player out of a game and bring another in. The player leaving goes inactive but keeps
//  their stats (still shown in the box score); the incoming player takes their lineup spot.
//

import SwiftUI
import SwiftData

struct SubstitutionView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Player.name) private var allPlayers: [Player]

    @State private var outLine: GameStatLine?     // who's coming out
    @State private var inPlayer: Player?          // who's coming in
    @State private var showingNewPlayer = false
    @State private var newPlayerName = ""

    /// Active players on a side, in batting order.
    private func activeLines(isHome: Bool) -> [GameStatLine] {
        game.statLines
            .filter { $0.isActive && !$0.isDH && $0.isHome == isHome }
            .sorted { $0.battingOrder < $1.battingOrder }
    }

    /// Any player in the app who isn't already active in this game.
    private var availablePlayers: [Player] {
        allPlayers.filter { player in
            !game.statLines.contains { $0.player === player && $0.isActive }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                comingOutSection(isHome: false, teamName: game.awayTeam?.name ?? "Away")
                comingOutSection(isHome: true, teamName: game.homeTeam?.name ?? "Home")

                Section("Coming In") {
                    Button {
                        showingNewPlayer = true
                    } label: {
                        Label("Create New Player", systemImage: "plus")
                    }
                    ForEach(availablePlayers) { player in
                        selectRow(title: player.name, selected: inPlayer === player) {
                            inPlayer = player
                        }
                    }
                }
            }
            .navigationTitle("Substitute Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Substitute") { performSubstitution() }
                        .disabled(outLine == nil || inPlayer == nil)
                }
            }
            .alert("New Player", isPresented: $showingNewPlayer) {
                TextField("Name", text: $newPlayerName)
                Button("Create") { createAndSelectNewPlayer() }
                Button("Cancel", role: .cancel) { newPlayerName = "" }
            }
        }
    }

    @ViewBuilder
    private func comingOutSection(isHome: Bool, teamName: String) -> some View {
        let lines = activeLines(isHome: isHome)
        if !lines.isEmpty {
            Section("Coming Out — \(teamName)") {
                ForEach(lines) { line in
                    selectRow(title: line.player?.name ?? "—", selected: outLine === line) {
                        outLine = line
                    }
                }
            }
        }
    }

    private func selectRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }

    private func createAndSelectNewPlayer() {
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        newPlayerName = ""
        guard !name.isEmpty else { return }
        let player = Player(name: name)
        modelContext.insert(player)
        inPlayer = player
    }

    private func performSubstitution() {
        guard let outLine, let inPlayer else { return }

        // The incoming player takes the outgoing player's side + lineup spot.
        let newLine = GameStatLine(
            player: inPlayer,
            isHome: outLine.isHome,
            battingOrder: outLine.battingOrder,
            isActive: true
        )
        newLine.game = game
        modelContext.insert(newLine)

        // The outgoing player leaves the lineup but keeps their stats.
        outLine.isActive = false

        // If they were pitching, the sub takes the mound.
        if game.homePitcher === outLine.player { game.homePitcher = inPlayer }
        if game.awayPitcher === outLine.player { game.awayPitcher = inPlayer }

        // If they were a ghost runner on base, the sub pinch-runs.
        for base in 0..<3 where game.runner(onBase: base) === outLine.player {
            game.setRunner(inPlayer, onBase: base)
        }

        dismiss()
    }
}
