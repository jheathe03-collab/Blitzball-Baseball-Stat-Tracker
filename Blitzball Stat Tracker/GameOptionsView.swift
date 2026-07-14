//
//  GameOptionsView.swift
//  Blitzball Stat Tracker
//
//  A single game's rules screen — a thin wrapper around the shared GameSettingsEditor.
//

import SwiftUI
import SwiftData

struct GameOptionsView: View {
    @Bindable var game: Game

    var body: some View {
        GameSettingsEditor(settings: $game.settings)
            .navigationTitle("Game Options")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Game.self, Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let game = Game()
    container.mainContext.insert(game)

    return NavigationStack {
        GameOptionsView(game: game)
    }
    .modelContainer(container)
}
