//
//  AddPlayerView.swift
//  Blitzball Stat Tracker
//
//  A small form, shown as a pop-up sheet, for adding a new player.
//

import SwiftUI
import SwiftData

struct AddPlayerView: View {
    // Optional team to auto-add the new player to. When the Players page opens this sheet it
    // passes nothing (nil); when a Team page opens it, it passes that team.
    var team: Team? = nil

    // How this sheet writes to the database, and how it closes itself.
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // View-local memory for what the user is typing. Text fields always deal in Strings,
    // so even the jersey number starts life as text and we convert it when saving.
    @State private var name = ""
    @State private var jerseyText = ""

    var body: some View {
        NavigationStack {
            Form {
                // `$name` is a two-way binding: the field displays `name` AND writes back
                // into it as the user types.
                TextField("Name", text: $name)

                TextField("Jersey number (optional)", text: $jerseyText)
                    .keyboardType(.numberPad) // show the number keypad
            }
            .navigationTitle("New Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel just closes the sheet without saving.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Save creates the player, then closes.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addPlayer() }
                        // Disabled until a name is entered (ignoring pure whitespace).
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addPlayer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // `Int(jerseyText)` returns nil if the text isn't a valid number — exactly the
        // optional we want for `jerseyNumber`.
        let player = Player(name: trimmedName, jerseyNumber: Int(jerseyText))

        // Insert into the database. The @Query in PlayersView notices and the new player
        // appears in the list instantly.
        modelContext.insert(player)

        // If we were opened from a team, put the new player on that team too.
        team?.players.append(player)

        dismiss()
    }
}

#Preview {
    AddPlayerView()
        .modelContainer(for: Player.self, inMemory: true)
}
