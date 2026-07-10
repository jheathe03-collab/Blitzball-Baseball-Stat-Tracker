//
//  AddTeamView.swift
//  Blitzball Stat Tracker
//
//  A small sheet for creating a new team. Same shape as AddPlayerView.
//

import SwiftUI
import SwiftData

struct AddTeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Team name", text: $name)
            }
            .navigationTitle("New Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addTeam() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addTeam() {
        let team = Team(name: name.trimmingCharacters(in: .whitespaces))
        modelContext.insert(team)
        dismiss()
    }
}

#Preview {
    AddTeamView()
        .modelContainer(for: [Player.self, Team.self], inMemory: true)
}
