//
//  CurrentGameOptionsView.swift
//  Blitzball Stat Tracker
//
//  A read-only glance at the rulebook in force for the game being tracked — reached from the live
//  game menu's "See Current Game Options". Deliberately NOT the editor (`GameSettingsEditor`): mid-game
//  the rules are fixed, so this just reports what's enabled rather than risking a change.
//

import SwiftUI

struct CurrentGameOptionsView: View {
    let settings: GameSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    optionRow("Game Type", settings.matchedType.displayName)
                }
                .blitzCardRow()

                Section(header: Text("Rules").foregroundStyle(.white)) {
                    optionRow("Innings", "\(settings.innings)")
                    optionRow("Outs Per Inning", "\(settings.outsPerInning)")
                    optionRow("Extra Innings", onOff(settings.extraInnings))
                    optionRow("Substitutions", onOff(settings.substitutions))
                    optionRow("All Team Pitch", onOff(settings.allTeamPitch))
                    optionRow("Force Pitcher Rotation", onOff(settings.forcePitcherRotation))
                    optionRow("Max Strikes", "\(settings.maxStrikes)")
                    optionRow("Max Balls", "\(settings.maxBalls)")
                    optionRow("Ghost Runners", onOff(settings.ghostRunners))
                    optionRow("HBP Walks", onOff(settings.hbpWalks))
                    optionRow("Designated Hitter", onOff(settings.designatedHitter))
                    optionRow("Record Balls and Strikes", onOff(settings.recordBallsAndStrikes))
                    optionRow("Record Pitch Type", onOff(settings.recordPitchType))
                    optionRow("Challenges", settings.challenges == 0 ? "Off" : "\(settings.challenges)")
                }
                .blitzCardRow()
            }
            .blitzListStyle()
            .blitzDarkBackground()
            .navigationTitle("Current Game Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A label on the left and its current value on the right — the whole point is glanceability.
    private func optionRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func onOff(_ on: Bool) -> String { on ? "On" : "Off" }
}
