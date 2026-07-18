//
//  EditTeamView.swift
//  Blitzball Stat Tracker
//
//  Rename an existing team. Mirrors EditPlayerView; the logo is edited separately from the team's
//  detail header. Blocks a name that collides with a DIFFERENT team (case-insensitive).
//

import SwiftUI
import SwiftData

struct EditTeamView: View {
    @Bindable var team: Team
    @Environment(\.dismiss) private var dismiss
    @Query private var allTeams: [Team]

    @State private var name: String

    init(team: Team) {
        self.team = team
        _name = State(initialValue: team.name)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// True when a *different* team already has this name (case-insensitive).
    private var nameTaken: Bool {
        !trimmedName.isEmpty && allTeams.contains {
            $0 !== team
            && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $name,
                          prompt: Text("Team name").foregroundStyle(.white.opacity(0.5)))
                    .blitzCardRow()

                if nameTaken {
                    Text("A team named \u{201C}\(trimmedName)\u{201D} already exists. Pick a different name.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .blitzCardRow()
                }
            }
            .navigationTitle("Edit Team")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty || nameTaken)
                }
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        team.name = trimmedName
        dismiss()
    }
}
