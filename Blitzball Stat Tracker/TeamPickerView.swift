//
//  TeamPickerView.swift
//  Blitzball Stat Tracker
//
//  A sheet for choosing a team. Two modes:
//   • single-select (default) — tap a team → `onSelect` → dismiss (Home/Away slots, etc.)
//   • multi-select — tap to toggle several teams, then Add → `onSelectMultiple` (tournament participants)
//  Either way, swipe right on a team to edit it, and + to make a new one.
//

import SwiftUI
import SwiftData

struct TeamPickerView: View {
    /// A team to leave out (e.g. the one already chosen for the other slot).
    let excluding: Team?
    /// Additional teams to leave out (e.g. tournament participants already added).
    var excludingTeams: [Team] = []
    /// When true, the picker lets you select multiple teams and confirm with Add.
    var allowsMultiple: Bool = false
    /// Called with all selected teams (in the order tapped) when `allowsMultiple`.
    var onSelectMultiple: ([Team]) -> Void = { _ in }
    /// Called with the single chosen team (single-select mode).
    var onSelect: (Team) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showingAddTeam = false
    @State private var editingTeam: Team?
    // Selection order preserved so multi-add seeds teams in the order you tapped them.
    @State private var selectedOrder: [PersistentIdentifier] = []

    private var selectableTeams: [Team] {
        teams.filter { team in team !== excluding && !excludingTeams.contains { $0 === team } }
    }
    private var selectedTeams: [Team] {
        selectedOrder.compactMap { id in selectableTeams.first { $0.persistentModelID == id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectableTeams.isEmpty {
                    ContentUnavailableView {
                        Label("No Teams to Pick", systemImage: "person.3")
                    } description: {
                        Text("Create a team to add here.")
                    } actions: {
                        Button("Create Team") { showingAddTeam = true }
                    }
                } else {
                    List(selectableTeams) { team in
                        teamRow(team)
                            .buttonStyle(.plain)
                            .blitzCardRow()
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { editingTeam = team } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .blitzListStyle()
                }
            }
            .navigationTitle(allowsMultiple ? "Select Teams" : "Select Team")
            .blitzballBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddTeam = true } label: {
                        Label("New Team", systemImage: "plus")
                    }
                }
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selectedOrder.isEmpty ? "Add" : "Add (\(selectedOrder.count))") {
                            onSelectMultiple(selectedTeams)
                            dismiss()
                        }
                        .disabled(selectedOrder.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingAddTeam) {
                AddTeamView()
            }
            .navigationDestination(item: $editingTeam) { team in
                TeamDetailView(team: team)
            }
        }
    }

    @ViewBuilder
    private func teamRow(_ team: Team) -> some View {
        if allowsMultiple {
            let isSelected = selectedOrder.contains(team.persistentModelID)
            Button { toggle(team) } label: {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.4))
                    Text(team.name).foregroundStyle(.white)
                    Spacer()
                    playerCount(team)
                }
            }
        } else {
            Button {
                onSelect(team)
                dismiss()
            } label: {
                HStack {
                    Text(team.name).foregroundStyle(.white)
                    Spacer()
                    playerCount(team)
                }
            }
        }
    }

    private func playerCount(_ team: Team) -> some View {
        Text("\(team.players.count) player\(team.players.count == 1 ? "" : "s")")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
    }

    private func toggle(_ team: Team) {
        let id = team.persistentModelID
        if let index = selectedOrder.firstIndex(of: id) {
            selectedOrder.remove(at: index)
        } else {
            selectedOrder.append(id)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Team.self, Player.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Team(name: "Sluggers"))
    container.mainContext.insert(Team(name: "Mashers"))

    return TeamPickerView(excluding: nil) { _ in }
        .modelContainer(container)
}
