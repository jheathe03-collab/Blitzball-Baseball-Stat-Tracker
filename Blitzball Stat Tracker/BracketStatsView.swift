//
//  BracketStatsView.swift
//  Blitzball Stat Tracker
//
//  Tournament performance: pick a bracket, then see the champion + how far each team got, and the
//  batting/pitching leaders for that tournament. Mirrors Season Stats. Also exports the bracket file.
//

import SwiftUI
import SwiftData

struct BracketStatsView: View {
    @Query(sort: \Tournament.createdAt, order: .reverse) private var tournaments: [Tournament]

    // Only started/finished brackets (skip empty setup drafts).
    private var visible: [Tournament] { tournaments.filter { $0.status != .setup } }

    var body: some View {
        Group {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Bracket Stats Yet", systemImage: "chart.bar")
                } description: {
                    Text("Start and play a bracket to see its stats here.")
                }
                .foregroundStyle(.white)
            } else {
                List(visible) { tournament in
                    NavigationLink {
                        BracketStatsDetailView(tournament: tournament)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tournament.displayName).font(.headline)
                            Text(subtitle(tournament)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .blitzCardRow()
                }
                .blitzListStyle()
            }
        }
        .navigationTitle("Bracket Stats")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
    }

    private func subtitle(_ t: Tournament) -> String {
        let count = t.seedOrder.count
        return "\(count) team\(count == 1 ? "" : "s") · \(t.status == .final ? "Complete" : "In progress")"
    }
}

// MARK: - One tournament's stats

struct BracketStatsDetailView: View {
    let tournament: Tournament
    @Query(sort: \Team.name) private var allTeams: [Team]
    @State private var exportFile: CSVExportFile?
    @State private var exportError: String?

    private var teams: [Team] { tournament.seededTeams(in: allTeams) }
    private var players: [Player] { tournament.participantPlayers() }

    var body: some View {
        List {
            resultsSection
            battingSection
            pitchingSection
        }
        .navigationTitle(tournament.displayName)
        .blitzballBackground()
        .blitzListStyle()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportBracketFile) {
                    Label("Export Bracket File", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
        .alert("Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { }
        } message: { Text(exportError ?? "") }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        Section(header: Text("Results").foregroundStyle(.white)) {
            let ranked = teams.sorted { tournament.finishRank(for: $0) > tournament.finishRank(for: $1) }
            ForEach(ranked, id: \.persistentModelID) { team in
                HStack {
                    if tournament.champion() === team {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                    } else {
                        TeamLogoView(logoName: team.logoName, size: 24)
                    }
                    Text(team.name)
                    Spacer()
                    Text(tournament.resultLabel(for: team))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .blitzCardRow()
    }

    // MARK: Batting

    @ViewBuilder
    private var battingSection: some View {
        let leaders = players
            .map { (player: $0, stats: $0.battingStats(inTournament: tournament)) }
            .filter { $0.stats.plateAppearances > 0 }
            .sorted { $0.stats.onBasePlusSlugging > $1.stats.onBasePlusSlugging }
        if !leaders.isEmpty {
            Section(header: Text("Batting").foregroundStyle(.white)) {
                ForEach(leaders, id: \.player.persistentModelID) { entry in
                    NavigationLink { PlayerDetailView(player: entry.player) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.player.name).font(.headline)
                            Text("AVG \(StatFormat.rate(entry.stats.battingAverage)) · H \(entry.stats.hits) · HR \(entry.stats.homeRuns) · RBI \(entry.stats.rbi)")
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .blitzCardRow()
        }
    }

    // MARK: Pitching

    @ViewBuilder
    private var pitchingSection: some View {
        let leaders = players
            .map { (player: $0, stats: $0.pitchingStats(inTournament: tournament)) }
            .filter { $0.stats.outsRecorded > 0 }
            .sorted { $0.stats.earnedRunAverage < $1.stats.earnedRunAverage }
        if !leaders.isEmpty {
            Section(header: Text("Pitching").foregroundStyle(.white)) {
                ForEach(leaders, id: \.player.persistentModelID) { entry in
                    NavigationLink { PlayerDetailView(player: entry.player) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.player.name).font(.headline)
                            Text("IP \(entry.stats.outsRecorded / 3).\(entry.stats.outsRecorded % 3) · ERA \(StatFormat.ratio(entry.stats.earnedRunAverage)) · K \(entry.stats.strikeouts)")
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .blitzCardRow()
        }
    }

    // MARK: Export

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private func exportBracketFile() {
        do {
            let base = tournament.name.isEmpty ? "Bracket" : tournament.name
            let url = try TournamentArchive(exporting: tournament).writeTempFile(baseName: base)
            exportFile = CSVExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
