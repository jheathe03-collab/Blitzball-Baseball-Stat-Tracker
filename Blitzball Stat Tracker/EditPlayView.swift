//
//  EditPlayView.swift
//  Blitzball Stat Tracker
//
//  Correct one recorded play: re-score the result, move it to a different batter or pitcher, or
//  mark its runs unearned. Every change writes straight through to the affected stat lines, so the
//  box score and every derived number update as soon as you back out.
//

import SwiftUI
import SwiftData

struct EditPlayView: View {
    @Bindable var game: Game
    @Bindable var play: PlayEvent
    @Environment(\.dismiss) private var dismiss

    /// The lineup that was batting when this play happened — not whoever is up now.
    private var battingLineup: [GameStatLine] {
        game.lineup(isHome: !play.isTopInning)
    }
    private var fieldingLineup: [GameStatLine] {
        game.lineup(isHome: play.isTopInning)
    }

    private var options: [PlateAppearanceOutcome] {
        play.outcome?.reclassificationOptions ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(play.summary)
                        .foregroundStyle(.white)
                    HStack {
                        Text("\(play.halfInningLabel) · \(play.outsBefore) out\(play.outsBefore == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        if play.runsScored > 0 {
                            Text("\(play.runsScored) run\(play.runsScored == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                } header: {
                    Text("Play").foregroundStyle(.white)
                }
                .blitzCardRow()

                resultSection
                if play.outcome?.isBattedBall == true { battedBallSection }
                peopleSection
                if play.runsScored > 0 { earnedSection }
            }
            .navigationTitle("Edit Play")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if options.count > 1 {
            Section {
                ForEach(options, id: \.self) { option in
                    Button {
                        game.reclassify(play, to: option)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.playLabel).foregroundStyle(.white)
                                Text(creditDescription(option))
                                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            if play.outcome == option {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Change outcome to").foregroundStyle(.white)
            } footer: {
                Text("Every option leaves the batter on the base he already reached, so runners "
                     + "don't move. Turning an out into a baserunner? Place him on the diamond.")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .blitzCardRow()
        }
    }

    /// Spell out what the batter is actually credited with, so the difference between
    /// "Double" and "Single + 2nd on Error" is visible at the moment of choosing.
    private func creditDescription(_ outcome: PlateAppearanceOutcome) -> String {
        var parts: [String] = []
        let batting = Game.battingDelta(for: outcome)
        if batting.hits > 0 {
            if batting.homeRuns > 0 { parts.append("home run") }
            else if batting.triples > 0 { parts.append("triple") }
            else if batting.doubles > 0 { parts.append("double") }
            else { parts.append("single") }
        } else if outcome.isAtBat {
            parts.append("at-bat, no hit")
        }
        if outcome.chargesError { parts.append("error charged") }
        if outcome.isOut { parts.append("out") }
        return parts.isEmpty ? "no batting credit" : parts.joined(separator: " · ")
    }

    // MARK: - Batted ball (contact type + location)

    /// Edit how the ball was hit and where it went. Bound straight to the play — these carry no stat
    /// deltas, so there's nothing to re-apply; the summary above updates the moment they change. Both
    /// allow "—" so a play scored before this existed (or a mis-tap) can be left or cleared.
    private var battedBallSection: some View {
        Section {
            Picker("Contact", selection: $play.battedBallType) {
                Text("—").tag(Optional<BattedBallType>.none)
                ForEach(BattedBallType.menuOrder, id: \.self) { type in
                    Text(type.label).tag(Optional(type))
                }
            }
            Picker("Location", selection: $play.fieldPosition) {
                Text("—").tag(Optional<FieldPosition>.none)
                ForEach(FieldPosition.byNumber, id: \.self) { position in
                    Text("\(position.fullName.capitalized) (\(position.abbreviation))").tag(Optional(position))
                }
            }
        } header: {
            Text("Batted Ball").foregroundStyle(.white)
        } footer: {
            Text("How the ball was hit and where it went. Shows in the play summary.")
                .foregroundStyle(.white.opacity(0.55))
        }
        .blitzCardRow()
    }

    // MARK: - Batter / pitcher

    private var peopleSection: some View {
        Section {
            Picker("Batter", selection: batterBinding) {
                ForEach(battingLineup, id: \.persistentModelID) { line in
                    Text(line.player?.name ?? "—").tag(line.player?.persistentModelID)
                }
            }
            Picker("Pitcher", selection: pitcherBinding) {
                ForEach(fieldingLineup, id: \.persistentModelID) { line in
                    Text(line.player?.name ?? "—").tag(line.player?.persistentModelID)
                }
            }
        } header: {
            Text("Credited to").foregroundStyle(.white)
        } footer: {
            Text("Moves this play's stats from one player's line to another's.")
                .foregroundStyle(.white.opacity(0.55))
        }
        .blitzCardRow()
    }

    private var batterBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { play.batter?.persistentModelID },
            set: { id in
                guard let player = battingLineup.compactMap(\.player)
                    .first(where: { $0.persistentModelID == id }) else { return }
                game.reassignBatter(play, to: player)
            }
        )
    }

    private var pitcherBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { play.pitcher?.persistentModelID },
            set: { id in
                guard let player = fieldingLineup.compactMap(\.player)
                    .first(where: { $0.persistentModelID == id }) else { return }
                game.reassignPitcher(play, to: player)
            }
        )
    }

    // MARK: - Earned / unearned

    private var earnedSection: some View {
        Section {
            Toggle("Runs were unearned", isOn: Binding(
                get: { play.unearnedRuns > 0 },
                set: { game.setRunsUnearned(play, unearned: $0) }
            ))
        } header: {
            Text("Earned Runs").foregroundStyle(.white)
        } footer: {
            Text("Unearned runs still count as runs allowed — they just stop counting against "
                 + "\(play.pitcher?.name ?? "the pitcher")'s ERA.")
                .foregroundStyle(.white.opacity(0.55))
        }
        .blitzCardRow()
    }
}
