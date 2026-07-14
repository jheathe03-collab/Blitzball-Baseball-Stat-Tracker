//
//  EditPlayerView.swift
//  Blitzball Stat Tracker
//
//  Edit an existing player's name and jersey number (the same fields you set when creating one).
//  Shown as a sheet from the player's card and from a swipe on the Players list.
//

import SwiftUI
import SwiftData

struct EditPlayerView: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss

    // Local copies so Cancel discards changes; we only write back on Save.
    @State private var name: String
    @State private var jerseyText: String

    init(player: Player) {
        self.player = player
        _name = State(initialValue: player.name)
        _jerseyText = State(initialValue: player.jerseyNumber.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Jersey number (optional)", text: $jerseyText)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        player.name = name.trimmingCharacters(in: .whitespaces)
        player.jerseyNumber = Int(jerseyText)   // nil if blank/invalid — clears the number
        dismiss()
    }
}
