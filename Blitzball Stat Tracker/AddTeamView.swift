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
    // Existing teams, so we can reject a duplicate team name.
    @Query private var allTeams: [Team]

    @State private var name = ""
    @State private var logoName: String?
    @State private var showingLogoPicker = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// True when another team already has this name (case-insensitive).
    private var nameTaken: Bool {
        !trimmedName.isEmpty && allTeams.contains {
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $name,
                          prompt: Text("Team name").foregroundStyle(.white.opacity(0.5)))
                    .blitzCardRow()

                Button {
                    showingLogoPicker = true
                } label: {
                    HStack {
                        TeamLogoView(logoName: logoName, size: 32)
                        Text(logoName.map(TeamLogo.displayName) ?? "Choose Logo")
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .blitzCardRow()

                if nameTaken {
                    Text("A team named \u{201C}\(trimmedName)\u{201D} already exists. Pick a different name.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .blitzCardRow()
                }
            }
            .navigationTitle("New Team")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .sheet(isPresented: $showingLogoPicker) {
                TeamLogoPicker(logoName: $logoName)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addTeam() }
                        .disabled(trimmedName.isEmpty || nameTaken)
                }
            }
        }
    }

    private func addTeam() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        let team = Team(name: trimmedName, logoName: logoName)
        modelContext.insert(team)
        dismiss()
    }
}

#Preview {
    AddTeamView()
        .modelContainer(for: [Player.self, Team.self], inMemory: true)
}
