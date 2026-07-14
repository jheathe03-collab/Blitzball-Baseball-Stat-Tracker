//
//  DesignatedHitterPicker.swift
//  Blitzball Stat Tracker
//
//  Choose the neutral Designated Hitter for a game (any player, or create a new one).
//

import SwiftUI
import SwiftData

struct DesignatedHitterPicker: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Player.name) private var allPlayers: [Player]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingNew = true } label: {
                        Label("Create New Player", systemImage: "plus")
                    }
                }
                Section("Players") {
                    ForEach(allPlayers) { player in
                        Button {
                            choose(player)
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.primary)
                                Spacer()
                                if game.designatedHitter === player {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Designated Hitter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("New Player", isPresented: $showingNew) {
                TextField("Name", text: $newName)
                Button("Create") { createNew() }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }

    private func choose(_ player: Player) {
        game.designatedHitter = player
        game.syncDesignatedHitter(using: modelContext)
        dismiss()
    }

    private func createNew() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        let player = Player(name: name)
        modelContext.insert(player)
        choose(player)
    }
}
