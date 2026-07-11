//
//  GameOptionsView.swift
//  Blitzball Stat Tracker
//
//  The rules screen for a game. Everything here writes straight onto game.settings (persisted).
//  Start Game will read these values when we build live tracking.
//

import SwiftUI
import SwiftData

struct GameOptionsView: View {
    @Bindable var game: Game

    var body: some View {
        Form {
            Section {
                Picker("Game Type", selection: gameTypeBinding) {
                    ForEach(GameType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Switching type resets all options to that type's defaults.")
            }

            Section("Rules") {
                // Steppers clamp to the ranges defined on GameSettings.
                Stepper("Innings: \(game.settings.innings)",
                        value: $game.settings.innings, in: GameSettings.inningsRange)

                Toggle("Extra Innings", isOn: $game.settings.extraInnings)
                Toggle("Substitutions", isOn: $game.settings.substitutions)
                Toggle("All Team Pitch", isOn: $game.settings.allTeamPitch)

                Stepper("Max Strikes: \(game.settings.maxStrikes)",
                        value: $game.settings.maxStrikes, in: GameSettings.strikesRange)
                Stepper("Max Balls: \(game.settings.maxBalls)",
                        value: $game.settings.maxBalls, in: GameSettings.ballsRange)

                Toggle("Ghost Runners", isOn: $game.settings.ghostRunners)

                Stepper("Challenges: \(game.settings.challenges)",
                        value: $game.settings.challenges, in: GameSettings.challengesRange)
            }

            Section {
                // Quick shortcuts back to either preset.
                Button("Reset to Blitzball Defaults") {
                    game.settings = .blitzballDefaults
                }
                Button("Reset to Baseball Defaults") {
                    game.settings = .baseballDefaults
                }
            }
        }
        .navigationTitle("Game Options")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The game-type picker reads the DERIVED type (so it shows "Custom" once the user tweaks
    /// anything), and selecting a preset swaps the whole settings struct. Selecting "Custom"
    /// itself does nothing — it's a status, not a preset to apply.
    private var gameTypeBinding: Binding<GameType> {
        Binding(
            get: { game.settings.matchedType },
            set: { newType in
                switch newType {
                case .blitzball: game.settings = .blitzballDefaults
                case .baseball:  game.settings = .baseballDefaults
                case .custom:    break
                }
            }
        )
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
