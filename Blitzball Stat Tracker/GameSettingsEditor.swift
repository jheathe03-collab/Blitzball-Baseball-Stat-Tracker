//
//  GameSettingsEditor.swift
//  Blitzball Stat Tracker
//
//  Reusable editor for a GameSettings rulebook — used by Game Options (a Game's settings) and
//  Season Settings (a Season's settings). Just the Form; the caller sets the navigation title.
//

import SwiftUI

struct GameSettingsEditor: View {
    @Binding var settings: GameSettings

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
                Stepper("Innings: \(settings.innings)",
                        value: $settings.innings, in: GameSettings.inningsRange)

                Toggle("Extra Innings", isOn: $settings.extraInnings)
                Toggle("Substitutions", isOn: $settings.substitutions)
                Toggle("All Team Pitch", isOn: $settings.allTeamPitch)

                Stepper("Max Strikes: \(settings.maxStrikes)",
                        value: $settings.maxStrikes, in: GameSettings.strikesRange)
                Stepper("Max Balls: \(settings.maxBalls)",
                        value: $settings.maxBalls, in: GameSettings.ballsRange)

                Toggle("Ghost Runners", isOn: $settings.ghostRunners)
                Toggle("HBP Walks", isOn: $settings.hbpWalks)
                Toggle("Designated Hitter", isOn: $settings.designatedHitter)

                Stepper("Challenges: \(settings.challenges)",
                        value: $settings.challenges, in: GameSettings.challengesRange)
            }

            Section {
                Button("Reset to Blitzball Defaults") { settings = .blitzballDefaults }
                Button("Reset to Baseball Defaults") { settings = .baseballDefaults }
            }
        }
    }

    /// Reads the DERIVED type (shows "Custom" once anything is tweaked); selecting a preset swaps
    /// the whole struct; selecting "Custom" is a no-op (it's a status, not a preset).
    private var gameTypeBinding: Binding<GameType> {
        Binding(
            get: { settings.matchedType },
            set: { newType in
                switch newType {
                case .blitzball: settings = .blitzballDefaults
                case .baseball:  settings = .baseballDefaults
                case .custom:    break
                }
            }
        )
    }
}
