//
//  PlayersView.swift
//  Blitzball Stat Tracker
//
//  The Players feature: add players and see their stats. (Formerly ContentView.)
//  This screen is PUSHED onto the Main Menu's navigation stack, so it does NOT create
//  its own NavigationStack — it uses the one the menu provides.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @State private var showingAddPlayer = false
    // The player swiped for deletion, held while we confirm.
    @State private var playerPendingDeletion: Player?
    // The player being edited (drives the edit sheet).
    @State private var playerToEdit: Player?
    // Import state: the file picker, a name-collision awaiting a choice, and a result message.
    @State private var showingImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importMessage: String?

    var body: some View {
        // No NavigationStack here anymore — the Main Menu owns it. We just describe the
        // content plus its title and toolbar, and they attach to the parent stack.
        Group {
            if players.isEmpty {
                ContentUnavailableView(
                    "No Players Yet",
                    systemImage: "figure.baseball",
                    description: Text("Tap + to add your first player.")
                )
            } else {
                List {
                    ForEach(players) { player in
                        NavigationLink(destination: PlayerDetailView(player: player)) {
                            PlayerRow(player: player)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { playerToEdit = player }
                                .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            playerPendingDeletion = players[index]
                        }
                    }
                }
            }
        }
        .navigationTitle("Players")
        .toolbar {
            // Edit + Add live on the trailing side so they don't collide with the
            // system back button (which sits on the leading side after a push).
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                Menu {
                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label("Add Player", systemImage: "plus")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Player…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            AddPlayerView()
        }
        .sheet(item: $playerToEdit) { player in
            EditPlayerView(player: player)
        }
        .alert("Delete Player?", isPresented: deletePlayerAlert, presenting: playerPendingDeletion) { player in
            Button("Delete \(player.name)", role: .destructive) {
                modelContext.delete(player)
            }
            Button("Cancel", role: .cancel) { }
        } message: { player in
            Text("Are you sure you want to delete \(player.name)? This removes them from any team and can't be undone.")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(duplicateTitle, isPresented: pendingImportBinding, presenting: pendingImport) { pending in
            Button("Merge") { resolve(pending, .merge) }
            Button("Replace", role: .destructive) { resolve(pending, .replace) }
            Button("Create New") { resolve(pending, .createNew) }
            Button("Cancel", role: .cancel) { }
        } message: { pending in
            Text(duplicateMessage(for: pending))
        }
        .alert("Import", isPresented: importMessageBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var deletePlayerAlert: Binding<Bool> {
        Binding(get: { playerPendingDeletion != nil },
                set: { if !$0 { playerPendingDeletion = nil } })
    }

    // MARK: - Import

    private var pendingImportBinding: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    }
    private var importMessageBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    private var duplicateTitle: String {
        "\u{201C}\(pendingImport?.archive.player.name ?? "Player")\u{201D} already exists"
    }
    private func duplicateMessage(for pending: PendingImport) -> String {
        let games = pending.existing.finalStatLines.count
        let jersey = pending.existing.jerseyNumber.map { "#\($0)" } ?? "no number"
        return "You already have \(pending.existing.name) (\(jersey), \(games) game\(games == 1 ? "" : "s")). "
            + "Merge adds the imported games, Replace swaps only previously-imported stats, Create New keeps them separate."
    }

    /// Read + decode the picked file, then either import directly or ask how to resolve a name clash.
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let archive = try PlayerArchive.decoded(from: data)
                if let existing = players.first(where: { $0.name == archive.player.name }) {
                    pendingImport = PendingImport(archive: archive, existing: existing)
                } else {
                    archive.apply(resolution: .createNew, existing: nil, context: modelContext)
                    importMessage = importedSummary(archive)
                }
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func resolve(_ pending: PendingImport, _ resolution: ImportResolution) {
        pending.archive.apply(resolution: resolution, existing: pending.existing, context: modelContext)
        pendingImport = nil
        importMessage = importedSummary(pending.archive)
    }

    private func importedSummary(_ archive: PlayerArchive) -> String {
        let n = archive.statLines.count
        return "Imported \(archive.player.name) — \(n) game\(n == 1 ? "" : "s") of stats."
    }
}

/// A decoded archive whose player name collides with an existing player — held while the user
/// chooses Merge / Replace / Create New.
private struct PendingImport: Identifiable {
    let id = UUID()
    let archive: PlayerArchive
    let existing: Player
}

/// One row in the players list.
private struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack {
            Text(player.name)
                .font(.headline)
            Spacer()
            if let number = player.jerseyNumber {
                Text("#\(number)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    // Previewed inside a NavigationStack to mimic being pushed from the menu.
    NavigationStack {
        PlayersView()
    }
    .modelContainer(for: Player.self, inMemory: true)
}
