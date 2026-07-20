//
//  TournamentModeView.swift
//  Blitzball Stat Tracker
//
//  The Tournament hub: set up a new bracket or resume one in progress. (Bracket Stats and Import
//  Bracket arrive in later stages.)
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TournamentModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tournaments: [Tournament]
    @State private var draft: Tournament?
    @State private var showParticipants = false
    @State private var showingImporter = false
    @State private var pendingImport: PendingTournamentImport?
    @State private var importMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    startNewBracket()
                } label: {
                    Label("Setup Bracket", systemImage: "plus.circle")
                }
                .blitzCardRow()

                NavigationLink {
                    ResumeTournamentView()
                } label: {
                    Label("Resume Bracket", systemImage: "play.circle")
                }
                .blitzCardRow()

                NavigationLink {
                    BracketStatsView()
                } label: {
                    Label("Bracket Stats", systemImage: "chart.bar")
                }
                .blitzCardRow()
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Bracket…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Bring in a bracket file exported from another device (Bracket Stats → Export Bracket File).")
                    .foregroundStyle(.white.opacity(0.99))
            }
            .blitzCardRow()
        }
        .blitzListStyle()
        .navigationTitle("Tournament")
        .blitzballBackground(watermark: true)
        .navigationDestination(isPresented: $showParticipants) {
            if let draft {
                TournamentParticipantsView(tournament: draft)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog("You Already Have This Bracket", isPresented: pendingImportBinding, presenting: pendingImport) { pending in
            Button("Update to This Version") { resolve(pending, .replace) }
            Button("Keep Both Copies") { resolve(pending, .keepBoth) }
            Button("Cancel", role: .cancel) { }
        } message: { pending in
            Text("You already have \u{201C}\(pending.name)\u{201D}. Update it with this file, or keep both as separate brackets.")
        }
        .alert("Import Bracket", isPresented: importMessageBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func startNewBracket() {
        let tournament = Tournament(status: .setup)
        modelContext.insert(tournament)
        draft = tournament
        showParticipants = true
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
                let archive = try TournamentArchive.decoded(from: data)
                if let existing = TournamentArchive.matchingTournament(for: archive, in: tournaments) {
                    pendingImport = PendingTournamentImport(archive: archive, existing: existing)
                } else {
                    let r = archive.apply(resolution: .keepBoth, existing: nil, context: modelContext)
                    importMessage = summary(r, name: archive.tournament.name, verb: "Imported")
                }
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func resolve(_ pending: PendingTournamentImport, _ resolution: SeasonImportResolution) {
        let r = pending.archive.apply(resolution: resolution,
                                      existing: resolution == .replace ? pending.existing : nil,
                                      context: modelContext)
        pendingImport = nil
        let verb = resolution == .replace ? "Updated" : "Added a copy of"
        importMessage = summary(r, name: pending.archive.tournament.name, verb: verb)
    }

    private func summary(_ r: (tournament: Tournament, players: Int, matches: Int), name: String, verb: String) -> String {
        let label = name.isEmpty ? "the bracket" : "\u{201C}\(name)\u{201D}"
        return "\(verb) \(label) — \(r.matches) match\(r.matches == 1 ? "" : "es"), "
            + "\(r.players) player\(r.players == 1 ? "" : "s")."
    }

    private var pendingImportBinding: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    }
    private var importMessageBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }
}

private struct PendingTournamentImport: Identifiable {
    let id = UUID()
    let archive: TournamentArchive
    let existing: Tournament
    var name: String { archive.tournament.name.isEmpty ? "Untitled Bracket" : archive.tournament.name }
}

// MARK: - Resume

struct ResumeTournamentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tournament.createdAt, order: .reverse) private var tournaments: [Tournament]
    @State private var pendingDeletion: Tournament?

    var body: some View {
        Group {
            if tournaments.isEmpty {
                ContentUnavailableView(
                    "No Brackets Yet",
                    systemImage: "trophy",
                    description: Text("Set up a bracket to see it here.")
                )
                .foregroundStyle(.white)
            } else {
                List {
                    ForEach(tournaments) { tournament in
                        NavigationLink {
                            destination(for: tournament)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tournament.displayName).font(.headline)
                                Text(subtitle(tournament))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .blitzCardRow()
                    }
                    .onDelete { offsets in
                        if let index = offsets.first { pendingDeletion = tournaments[index] }
                    }
                }
                .blitzListStyle()
            }
        }
        .navigationTitle("Resume Bracket")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .alert("Delete Bracket?", isPresented: deleteBinding, presenting: pendingDeletion) { tournament in
            Button("Delete", role: .destructive) {
                modelContext.delete(tournament)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { tournament in
            Text("Delete \u{201C}\(tournament.displayName)\u{201D}? This can't be undone.")
        }
    }

    @ViewBuilder
    private func destination(for tournament: Tournament) -> some View {
        if tournament.status == .setup {
            TournamentParticipantsView(tournament: tournament)
        } else {
            TournamentBracketDisplayView(tournament: tournament)
        }
    }

    private func subtitle(_ tournament: Tournament) -> String {
        let count = tournament.seedOrder.count
        let teams = "\(count) team\(count == 1 ? "" : "s")"
        let status: String
        switch tournament.status {
        case .setup:      status = "Setup"
        case .inProgress: status = "In progress"
        case .final:      status = "Complete"
        }
        return "\(teams) · \(status)"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}
