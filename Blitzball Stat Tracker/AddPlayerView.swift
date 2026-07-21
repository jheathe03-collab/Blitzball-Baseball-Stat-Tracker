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
    // Everyone already on file, so we can reject a duplicate name.
    @Query private var allPlayers: [Player]

    // View-local memory for what the user is typing. Text fields always deal in Strings,
    // so even the jersey number starts life as text and we convert it when saving.
    @State private var name = ""
    @State private var jerseyText = ""
    @State private var battingStance = ""
    
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// True when another player already has this name (case-insensitive). Two players with the
    /// same name would make their stats impossible to tell apart.
    private var nameTaken: Bool {
        !trimmedName.isEmpty && allPlayers.contains {
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // `$name` is a two-way binding: the field displays `name` AND writes back
                // into it as the user types.
                TextField("", text: $name,
                          prompt: Text("Name").foregroundStyle(.white.opacity(0.5)))
                    .blitzCardRow()

                TextField("", text: $jerseyText,
                          prompt: Text("Jersey number (optional)").foregroundStyle(.white.opacity(0.5)))
                    .keyboardType(.numberPad) // show the number keypad
                    .blitzCardRow()
                
                BattingStanceField(stance: $battingStance)
                    .blitzCardRow()

                if nameTaken {
                    Text("A player named \u{201C}\(trimmedName)\u{201D} already exists. Pick a different name.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .blitzCardRow()
                }
            }
            .navigationTitle("New Player")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                // Cancel just closes the sheet without saving.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Save creates the player, then closes.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addPlayer() }
                        // Disabled until a non-empty, non-duplicate name is entered.
                        .disabled(trimmedName.isEmpty || nameTaken)
                }
            }
        }
    }

    private func addPlayer() {
        guard !trimmedName.isEmpty, !nameTaken else { return }   // guard against a duplicate slipping through

        // `Int(jerseyText)` returns nil if the text isn't a valid number — exactly the
        // optional we want for `jerseyNumber`.
        let player = Player(
            name: trimmedName,
            jerseyNumber: Int(jerseyText),
            battingStance: battingStance.isEmpty ? nil : battingStance
        )

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
