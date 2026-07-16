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
    @State private var logoName: String?
    @State private var showingLogoPicker = false

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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addTeam() {
        let team = Team(name: name.trimmingCharacters(in: .whitespaces), logoName: logoName)
        modelContext.insert(team)
        dismiss()
    }
}

#Preview {
    AddTeamView()
        .modelContainer(for: [Player.self, Team.self], inMemory: true)
}
