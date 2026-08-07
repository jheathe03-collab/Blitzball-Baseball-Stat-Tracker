//
//  GameSettingsEditor.swift
//  Blitzball Stat Tracker
//
//  Reusable editor for a GameSettings rulebook — used by Game Options (a Game's settings) and
//  Season Settings (a Season's settings). Just the Form; the caller sets the navigation title.
//
//  The bound `settings` is a JSON-blob-backed computed property (see Game.settings): every read
//  decodes it and every write re-encodes it AND writes a SwiftData property, which invalidates the
//  whole screen (and the pregame screen underneath). Doing that on every toggle made the controls
//  feel laggy. So we edit a LOCAL copy — instant, no decode/encode churn — and commit back to the
//  bound blob exactly once, when the screen goes away (or the app backgrounds mid-edit).
//

import SwiftUI

struct GameSettingsEditor: View {
    @Binding var settings: GameSettings
    @State private var draft: GameSettings
    @Environment(\.scenePhase) private var scenePhase

    init(settings: Binding<GameSettings>) {
        _settings = settings
        _draft = State(initialValue: settings.wrappedValue)
    }

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
                    .foregroundStyle(.white.opacity(0.6))
            }
            .blitzCardRow()

            Section(header: Text("Rules").foregroundStyle(.white)) {
                Stepper("Innings: \(draft.innings)",
                        value: $draft.innings, in: GameSettings.inningsRange)
                Stepper("Outs Per Inning: \(draft.outsPerInning)",
                        value: $draft.outsPerInning, in: GameSettings.outsRange)

                Toggle("Extra Innings", isOn: $draft.extraInnings)
                Toggle("Substitutions", isOn: $draft.substitutions)
                Toggle("All Team Pitch", isOn: $draft.allTeamPitch)
                Toggle("Force Pitcher Rotation", isOn: $draft.forcePitcherRotation)

                Stepper("Max Strikes: \(draft.maxStrikes)",
                        value: $draft.maxStrikes, in: GameSettings.strikesRange)
                Stepper("Max Balls: \(draft.maxBalls)",
                        value: $draft.maxBalls, in: GameSettings.ballsRange)

                Toggle("Ghost Runners", isOn: $draft.ghostRunners)
                Toggle("HBP Walks", isOn: $draft.hbpWalks)
                Toggle("Designated Hitter", isOn: $draft.designatedHitter)

                // Turning off ball/strike tracking also turns off pitch-type tracking (the pair).
                Toggle("Record Balls and Strikes", isOn: Binding(
                    get: { draft.recordBallsAndStrikes },
                    set: { on in
                        draft.recordBallsAndStrikes = on
                        if !on { draft.recordPitchType = false }
                    }
                ))
                // Pitch type enriches ball/strike tracking, so it can't be enabled on its own.
                Toggle("Record Pitch Type", isOn: $draft.recordPitchType)
                    .disabled(!draft.recordBallsAndStrikes)

                Stepper("Challenges: \(draft.challenges)",
                        value: $draft.challenges, in: GameSettings.challengesRange)
            }
            .blitzCardRow()

            Section {
                Button("Reset to Blitzball Defaults") { draft = .blitzballDefaults }
                Button("Reset to Baseball Defaults") { draft = .baseballDefaults }
            }
            .blitzCardRow()
        }
        // Persist the edits once, on the way out (or if the app backgrounds mid-edit).
        .onDisappear { commit() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commit() }
        }
    }

    /// Write the local draft back to the bound blob — but only if something actually changed, so we
    /// don't trigger a needless SwiftData write (and screen invalidation) when nothing was edited.
    private func commit() {
        if draft != settings { settings = draft }
    }

    /// Reads the DERIVED type (shows "Custom" once anything is tweaked); selecting a preset swaps
    /// the whole struct; selecting "Custom" is a no-op (it's a status, not a preset).
    private var gameTypeBinding: Binding<GameType> {
        Binding(
            get: { draft.matchedType },
            set: { newType in
                switch newType {
                case .blitzball: draft = .blitzballDefaults
                case .baseball:  draft = .baseballDefaults
                case .custom:    break
                }
            }
        )
    }
}
