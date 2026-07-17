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
    // Everyone on file, to reject a name that collides with a DIFFERENT player.
    @Query private var allPlayers: [Player]

    // Local copies so Cancel discards changes; we only write back on Save.
    @State private var name: String
    @State private var jerseyText: String

    init(player: Player) {
        self.player = player
        _name = State(initialValue: player.name)
        _jerseyText = State(initialValue: player.jerseyNumber.map(String.init) ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// True when a *different* player already has this name (case-insensitive).
    private var nameTaken: Bool {
        !trimmedName.isEmpty && allPlayers.contains {
            $0 !== player
            && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $name,
                          prompt: Text("Name").foregroundStyle(.white.opacity(0.5)))
                    .blitzCardRow()
                TextField("", text: $jerseyText,
                          prompt: Text("Jersey number (optional)").foregroundStyle(.white.opacity(0.5)))
                    .keyboardType(.numberPad)
                    .blitzCardRow()

                if nameTaken {
                    Text("A player named \u{201C}\(trimmedName)\u{201D} already exists. Pick a different name.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .blitzCardRow()
                }
            }
            .navigationTitle("Edit Player")
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
        player.name = trimmedName
        player.jerseyNumber = Int(jerseyText)   // nil if blank/invalid — clears the number
        dismiss()
    }
}
