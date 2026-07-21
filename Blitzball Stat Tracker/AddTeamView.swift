//
//  AddTeamView.swift
//  Blitzball Stat Tracker
//
//  A sheet for creating a new team — name, logo, and (optionally) its starting roster. Building the
//  roster here means you can spin up a team and its players in one go (handy mid-bracket setup);
//  nothing is created until you tap Add, so Cancel leaves no orphans.
//

import SwiftUI
import SwiftData

struct AddTeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTeams: [Team]
    @Query(sort: \Player.name) private var allPlayers: [Player]

    @State private var name = ""
    @State private var logoName: String?
    @State private var logoImageData: Data?
    @State private var showingLogoPicker = false

    // Roster being assembled locally (not inserted until Add).
    @State private var roster: [RosterEntry] = []
    @State private var showingCreatePlayer = false
    @State private var showingAddExisting = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var logoLabel: String {
        if logoImageData != nil { return "Custom Photo" }
        return logoName.map(TeamLogo.displayName) ?? "Choose Logo"
    }

    private var nameTaken: Bool {
        !trimmedName.isEmpty && allTeams.contains {
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    /// Names already spoken for (existing players + everyone on the in-progress roster), lowercased —
    /// so a newly-created roster player can't duplicate a name.
    private var takenPlayerNames: Set<String> {
        Set(allPlayers.map { $0.name.lowercased() }).union(roster.map { $0.name.lowercased() })
    }

    /// Existing players not already on the roster.
    private var availableExisting: [Player] {
        allPlayers.filter { player in
            !roster.contains { $0.existing === player }
                && !roster.contains { $0.name.lowercased() == player.name.lowercased() }
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
                        TeamLogoView(logoName: logoName, imageData: logoImageData, size: 32)
                        Text(logoLabel).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .blitzCardRow()

                if nameTaken {
                    Text("A team named \u{201C}\(trimmedName)\u{201D} already exists. Pick a different name.")
                        .font(.footnote).foregroundStyle(.red)
                        .blitzCardRow()
                }

                rosterSection
            }
            .navigationTitle("New Team")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .sheet(isPresented: $showingLogoPicker) {
                TeamLogoPicker(logoName: $logoName, logoImageData: $logoImageData)
            }
            .sheet(isPresented: $showingCreatePlayer) {
                RosterCreatePlayerSheet(takenNames: takenPlayerNames) { newName, jersey, stance in
                    roster.append(RosterEntry(name: newName, jersey: jersey, stance: stance, existing: nil))
                }
            }
            .sheet(isPresented: $showingAddExisting) {
                RosterExistingPlayerSheet(players: availableExisting) { player in
                    roster.append(RosterEntry(name: player.name, jersey: player.jerseyNumber, stance: player.battingStance, existing: player))
                }
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

    private var rosterSection: some View {
        Section {
            ForEach(roster) { entry in
                HStack {
                    Text(entry.name).foregroundStyle(.white)
                    if entry.existing != nil {
                        Text("existing").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    if let stance = entry.stance {
                        Text(stance).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                    if let jersey = entry.jersey {
                        Text("#\(jersey)").foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .onDelete { roster.remove(atOffsets: $0) }

            Button { showingCreatePlayer = true } label: {
                Label("Create a New Player", systemImage: "plus.circle")
            }
            Button { showingAddExisting = true } label: {
                Label("Add an Existing Player", systemImage: "person.badge.plus")
            }
            .disabled(availableExisting.isEmpty)
        } header: {
            Text("Players (optional)").foregroundStyle(.white)
        } footer: {
            Text("Add players now, or later from the team's page.")
                .foregroundStyle(.white.opacity(0.55))
        }
        .blitzCardRow()
    }

    private func addTeam() {
        guard !trimmedName.isEmpty, !nameTaken else { return }
        let team = Team(name: trimmedName, logoName: logoName, logoImageData: logoImageData)
        modelContext.insert(team)
        for entry in roster {
            if let existing = entry.existing {
                team.players.append(existing)
            } else {
                let player = Player(name: entry.name, jerseyNumber: entry.jersey, battingStance: entry.stance)
                modelContext.insert(player)
                team.players.append(player)
            }
        }
        dismiss()
    }
}

/// One line of the in-progress roster: either a brand-new player or a reference to an existing one.
private struct RosterEntry: Identifiable {
    let id = UUID()
    var name: String
    var jersey: Int?
    var stance: String?
    var existing: Player?
}

// MARK: - Create a new player for the roster

private struct RosterCreatePlayerSheet: View {
    let takenNames: Set<String>            // lowercased
    let onCreate: (String, Int?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var jerseyText = ""
    @State private var battingStance = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, jersey }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool { !trimmed.isEmpty && takenNames.contains(trimmed.lowercased()) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $name,
                          prompt: Text("Name").foregroundStyle(.white.opacity(0.5)))
                    .focused($focusedField, equals: .name)
                    .blitzCardRow()
                TextField("", text: $jerseyText,
                          prompt: Text("Jersey number (optional)").foregroundStyle(.white.opacity(0.5)))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .jersey)
                    .blitzCardRow()
                BattingStanceField(stance: $battingStance)
                    .blitzCardRow()
                if nameTaken {
                    Text("A player named \u{201C}\(trimmed)\u{201D} already exists. Pick a different name.")
                        .font(.footnote).foregroundStyle(.red)
                        .blitzCardRow()
                }
            }
            .navigationTitle("New Player")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .onChange(of: battingStance) { focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onCreate(trimmed, Int(jerseyText), battingStance.isEmpty ? nil : battingStance)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || nameTaken)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }
}

// MARK: - Add an existing player to the roster

private struct RosterExistingPlayerSheet: View {
    let players: [Player]
    let onPick: (Player) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if players.isEmpty {
                    ContentUnavailableView(
                        "No Players to Add",
                        systemImage: "figure.baseball",
                        description: Text("Everyone's already on this team, or you haven't made any players yet.")
                    )
                    .foregroundStyle(.white)
                } else {
                    List(players) { player in
                        Button { onPick(player); dismiss() } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.white)
                                Spacer()
                                if let jersey = player.jerseyNumber {
                                    Text("#\(jersey)").foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .blitzCardRow()
                    }
                    .blitzListStyle()
                }
            }
            .navigationTitle("Add Existing Player")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

#Preview {
    AddTeamView()
        .modelContainer(for: [Player.self, Team.self], inMemory: true)
}
