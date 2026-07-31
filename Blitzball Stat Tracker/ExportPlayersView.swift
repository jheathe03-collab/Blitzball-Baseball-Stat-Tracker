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
    @State private var confirmingPhotoExport = false
    // Non-nil while a background export task is in flight — drives the progress overlay and
    // disables the Export button so a second tap can't kick off a parallel encode.
    @State private var exportProgress: ExportProgress?

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
                        beginExport()
                    } label: {
                        Label(
                            selectedCount == 0 ? "Export" : "Export \(selectedCount) Player\(selectedCount == 1 ? "" : "s")",
                            systemImage: "square.and.arrow.up"
                        )
                        .fontWeight(.semibold)
                    }
                    .disabled(selectedCount == 0 || exportProgress != nil)
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
            .confirmationDialog("Include player photos?", isPresented: $confirmingPhotoExport, titleVisibility: .visible) {
                Button("Include Photos") { exportSelected(includePhotos: true) }
                Button("Without Photos (smaller files)") { exportSelected(includePhotos: false) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Photos make the files larger to share.")
            }
            .overlay {
                if let progress = exportProgress {
                    // Full-screen dimmer + centred progress card. The dimmer covers every
                    // interactive control underneath, so a second tap on Export or Cancel
                    // during encode is physically blocked (belt to the `.disabled` suspenders).
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.3)
                            Text("Exporting \(progress.done) of \(progress.total)…")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }
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

    /// Ask about photos only when a selected player actually has one; otherwise export straight away.
    private func beginExport() {
        let anyPhotos = eligible.contains {
            selected.contains($0.persistentModelID) && $0.photoData != nil
        }
        if anyPhotos { confirmingPhotoExport = true }
        else { exportSelected(includePhotos: false) }
    }

    /// Write one JSON file per selected player, then present the share sheet.
    ///
    /// Split into two phases so we don't hang the UI on a full league (40 players × 40 KB photos
    /// = several MB of base64 encoding — synchronous on the main thread was a multi-second freeze
    /// with no spinner):
    ///
    ///   1. **Main actor** — build a `PlayerArchive` struct for each selected player. This has to
    ///      stay on main because it reads SwiftData `Player` properties. But it's fast (value
    ///      copies), so it doesn't block visibly.
    ///   2. **Background task** — encode each archive to JSON (this is where base64 lives) and
    ///      write to a temp file. After each file, hop back to main to bump the progress counter.
    ///
    /// The progress overlay in `body` drives off `exportProgress`; the Export button is disabled
    /// while it's non-nil so the task can't be double-fired.
    private func exportSelected(includePhotos: Bool) {
        // Phase 1: snapshot on main.
        var jobs: [ExportJob] = []
        var usedNames: Set<String> = []
        for player in eligible where selected.contains(player.persistentModelID) {
            let archive = PlayerArchive(exporting: player, includePhotos: includePhotos)
            let filename = uniqueFilename(for: player, used: &usedNames)
            jobs.append(ExportJob(archive: archive, filename: filename))
        }
        guard !jobs.isEmpty else { return }
        exportProgress = ExportProgress(done: 0, total: jobs.count)

        // Phase 2: encode + write on a background task. `jobs` is a value-type array of Sendable
        // structs, so it captures cleanly across the actor boundary.
        Task.detached(priority: .userInitiated) {
            var writtenURLs: [URL] = []
            for job in jobs {
                do {
                    let data = try job.archive.encoded()
                    let url = URL.temporaryDirectory.appending(path: job.filename)
                    try data.write(to: url, options: .atomic)
                    writtenURLs.append(url)
                    // Report progress after each file so the counter ticks up visibly.
                    let doneCount = writtenURLs.count
                    let total = jobs.count
                    await MainActor.run {
                        exportProgress = ExportProgress(done: doneCount, total: total)
                    }
                } catch {
                    let message = error.localizedDescription
                    await MainActor.run {
                        exportProgress = nil
                        exportError = message
                    }
                    return
                }
            }
            let finalURLs = writtenURLs
            await MainActor.run {
                exportProgress = nil
                shareBundle = ShareBundle(urls: finalURLs)
            }
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

/// One snapshot handed to the background encode+write task. Sendable so it can cross actors.
private struct ExportJob: Sendable {
    let archive: PlayerArchive
    let filename: String
}

/// Counter shown in the export progress overlay.
private struct ExportProgress {
    let done: Int
    let total: Int
}

// PlayerArchive is a value-type Codable struct — the fields are all Sendable already, but the
// Swift 6 concurrency checker won't INFER Sendable across module boundaries. Marking it here
// (unchecked because Data is technically not Sendable-safe by pure spec, but Foundation's Data is
// value-copied on write and we're only reading from the background task) lets us capture it
// cleanly in Task.detached.
extension PlayerArchive: @unchecked Sendable {}
