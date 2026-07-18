//
//  SeasonModeView.swift
//  Blitzball Stat Tracker
//
//  The Season hub: start a new season, resume one in progress, view season stats, or import a
//  season file exported from another device.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SeasonModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var seasons: [Season]

    @State private var showingImporter = false
    // A decoded archive whose season already exists here — held while the user chooses Replace/Keep Both.
    @State private var pendingImport: PendingSeasonImport?
    @State private var importMessage: String?

    var body: some View {
        List {
            NavigationLink(value: SeasonRoute.newSeason) {
                Label("New Season", systemImage: "plus.circle")
            }
            .blitzCardRow()
            NavigationLink(value: SeasonRoute.resume) {
                Label("Resume Season", systemImage: "play.circle")
            }
            .blitzCardRow()
            NavigationLink {
                SeasonStatsView()
            } label: {
                Label("Season Stats", systemImage: "chart.bar")
            }
            .blitzCardRow()

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Season…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Bring in a season file exported from another device (Season Stats → Export → Season File).")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .blitzCardRow()
        }
        .blitzListStyle()
        .navigationTitle("Season Mode")
        .blitzballBackground(watermark: true)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(duplicateTitle, isPresented: pendingImportBinding, presenting: pendingImport) { pending in
            Button("Update to This Version") { resolve(pending, .replace) }
            Button("Keep Both Copies") { resolve(pending, .keepBoth) }
            Button("Cancel", role: .cancel) { }
        } message: { pending in
            Text("You already have \u{201C}\(seasonName(pending))\u{201D}. Update it with this file to match the sender — your copy is refreshed and everyone's stats stay in sync. Or keep both as separate seasons.")
        }
        .alert("Import Season", isPresented: importMessageBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let archive = try SeasonArchive.decoded(from: data)
                if let existing = SeasonArchive.matchingSeason(for: archive, in: seasons) {
                    pendingImport = PendingSeasonImport(archive: archive, existing: existing)
                } else {
                    let result = archive.apply(resolution: .keepBoth, existingSeason: nil, context: modelContext)
                    importMessage = summary(result, name: archive.season.name, verb: "Imported")
                }
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func resolve(_ pending: PendingSeasonImport, _ resolution: SeasonImportResolution) {
        let result = pending.archive.apply(
            resolution: resolution,
            existingSeason: resolution == .replace ? pending.existing : nil,
            context: modelContext
        )
        pendingImport = nil
        let verb = resolution == .replace ? "Updated" : "Added a copy of"
        importMessage = summary(result, name: pending.archive.season.name, verb: verb)
    }

    private func summary(_ result: (season: Season, players: Int, games: Int), name: String, verb: String) -> String {
        let label = name.isEmpty ? "the season" : "\u{201C}\(name)\u{201D}"
        return "\(verb) \(label) — \(result.games) game\(result.games == 1 ? "" : "s"), "
            + "\(result.players) player\(result.players == 1 ? "" : "s")."
    }

    private func seasonName(_ pending: PendingSeasonImport) -> String {
        pending.archive.season.name.isEmpty ? "Untitled Season" : pending.archive.season.name
    }

    private var duplicateTitle: String { "You Already Have This Season" }

    private var pendingImportBinding: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    }
    private var importMessageBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }
}

/// A decoded season archive whose season already exists here, held while the user picks how to resolve.
private struct PendingSeasonImport: Identifiable {
    let id = UUID()
    let archive: SeasonArchive
    let existing: Season
}
