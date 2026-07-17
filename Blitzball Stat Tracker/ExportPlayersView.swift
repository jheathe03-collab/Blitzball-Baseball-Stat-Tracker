//
//  ExportPlayersView.swift
//  Blitzball Stat Tracker
//
//  Multi-player export: pick any number of players and share their stats as ONE JSON file each
//  (the same per-player `PlayerArchive` format the Players importer already reads). Everything is
//  shared at once through the standard iOS share sheet (AirDrop / Save to Files / Messages).
//

import SwiftUI
import SwiftData

struct ExportPlayersView: View {
    let players: [Player]
    @Environment(\.dismiss) private var dismiss

    // Selected players, tracked by their stable SwiftData id.
    @State private var selected: Set<PersistentIdentifier> = []
    // Non-nil once files are written — drives the share sheet.
    @State private var shareBundle: ShareBundle?
    @State private var exportError: String?

    /// Only players with finished-game history can be exported (an empty archive is pointless).
    private var eligible: [Player] { players.filter { !$0.finalStatLines.isEmpty } }
    private var selectedCount: Int { selected.count }

    var body: some View {
        NavigationStack {
            Group {
                if eligible.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Export",
                        systemImage: "square.and.arrow.up",
                        description: Text("No players have finished-game stats yet.")
                    )
                    .foregroundStyle(.white)
                } else {
                    playerList
                }
            }
            .navigationTitle("Export Players")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "Deselect All" : "Select All") { toggleAll() }
                        .disabled(eligible.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        exportSelected()
                    } label: {
                        Label(
                            selectedCount == 0 ? "Export" : "Export \(selectedCount) Player\(selectedCount == 1 ? "" : "s")",
                            systemImage: "square.and.arrow.up"
                        )
                        .fontWeight(.semibold)
                    }
                    .disabled(selectedCount == 0)
                }
            }
            .sheet(item: $shareBundle) { bundle in
                // When the share sheet closes, dismiss the picker too — the task is done.
                ShareSheet(items: bundle.urls)
                    .onDisappear { dismiss() }
            }
            .alert("Export Failed", isPresented: exportErrorBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var playerList: some View {
        List {
            Section {
                ForEach(eligible) { player in
                    Button { toggle(player) } label: { row(player) }
                        .buttonStyle(.plain)
                }
                .blitzCardRow()
            } footer: {
                Text("Each selected player is exported as their own file. Share them together via AirDrop, Save to Files, or Messages.")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .blitzListStyle()
    }

    private func row(_ player: Player) -> some View {
        let isOn = selected.contains(player.persistentModelID)
        let games = player.finalStatLines.count
        return HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.accentColor : .white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(games) game\(games == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if let number = player.jerseyNumber {
                Text("#\(number)").foregroundStyle(.white.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Selection

    private var allSelected: Bool {
        !eligible.isEmpty && eligible.allSatisfy { selected.contains($0.persistentModelID) }
    }

    private func toggle(_ player: Player) {
        let id = player.persistentModelID
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toggleAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(eligible.map(\.persistentModelID))
        }
    }

    // MARK: - Export

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    /// Write one JSON file per selected player into a temp folder, then present the share sheet.
    private func exportSelected() {
        do {
            var urls: [URL] = []
            var usedNames: Set<String> = []
            for player in eligible where selected.contains(player.persistentModelID) {
                let data = try PlayerArchive(exporting: player).encoded()
                let name = uniqueFilename(for: player, used: &usedNames)
                let url = URL.temporaryDirectory.appending(path: name)
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            guard !urls.isEmpty else { return }
            shareBundle = ShareBundle(urls: urls)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// e.g. "Mike-stats-2026-07-16.json", de-duplicated if two players sanitize to the same name.
    private func uniqueFilename(for player: Player, used: inout Set<String>) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = player.name.components(separatedBy: illegal).joined()
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "player" : cleaned
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: .now)

        var candidate = "\(base)-stats-\(date).json"
        var counter = 2
        while used.contains(candidate) {
            candidate = "\(base)-stats-\(date)-\(counter).json"
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }
}

/// A set of files to share together (Identifiable so it can drive `.sheet(item:)`).
private struct ShareBundle: Identifiable {
    let id = UUID()
    let urls: [URL]
}
