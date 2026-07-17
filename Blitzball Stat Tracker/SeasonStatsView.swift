//
//  SeasonStatsView.swift
//  Blitzball Stat Tracker
//
//  Season Stats: pick a season, then see its standings (team W-L) and the season stats for every
//  player who played — all DERIVED from that season's finished games (via the game.season link),
//  so two seasons in the same calendar year stay separate. Tapping a player opens their full
//  career card.
//

import SwiftUI
import SwiftData

// MARK: - Pick a season

struct SeasonStatsView: View {
    @Query(sort: \Season.createdAt, order: .reverse) private var seasons: [Season]

    // Only started seasons (skip abandoned setup drafts).
    private var visible: [Season] {
        seasons.filter { $0.status != .setup }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Seasons Yet", systemImage: "chart.bar.horizontal.page")
                } description: {
                    Text("Start a season and play some games to see its stats here.")
                }
                .foregroundStyle(.white)
            } else {
                List(visible) { season in
                    NavigationLink {
                        SeasonStatsDetailView(season: season)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(season.name.isEmpty ? "Untitled Season" : season.name)
                                .font(.headline)
                            Text("\(season.gamesPlayed)/\(season.gamesPerSeason) games played")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .blitzCardRow()
                }
                .blitzListStyle()
            }
        }
        .navigationTitle("Season Stats")
        .blitzballBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One season's stats

struct SeasonStatsDetailView: View {
    let season: Season

    @State private var exportFile: CSVExportFile?
    @State private var exportError: String?

    var body: some View {
        List {
            standingsSection
            battingSection
            pitchingSection
        }
        .navigationTitle(season.name.isEmpty ? "Season" : season.name)
        .blitzballBackground()
        .blitzListStyle()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportCSV) {
                    Label("Export Spreadsheet", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private func exportCSV() {
        do {
            let csv = StatsCSV.seasonCSV(season)
            let base = season.name.isEmpty ? "Season" : season.name
            exportFile = CSVExportFile(url: try StatsCSV.writeTempFile(csv, baseName: base))
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: Standings

    @ViewBuilder
    private var standingsSection: some View {
        Section(header: Text("Standings").foregroundStyle(.white)) {
            if standings.isEmpty {
                Text("No teams set for this season yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(standings, id: \.team.persistentModelID) { entry in
                    HStack {
                        TeamLogoView(logoName: entry.team.logoName, size: 24)
                        Text(entry.team.name)
                        Spacer()
                        Text("\(entry.record.wins)-\(entry.record.losses)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .blitzCardRow()
    }

    // Teams ranked by wins (then fewest losses). W-L counts only this season's finished games.
    private var standings: [(team: Team, record: (wins: Int, losses: Int))] {
        seasonTeams
            .map { (team: $0, record: $0.record(from: season.games)) }
            .sorted { a, b in
                a.record.wins != b.record.wins
                    ? a.record.wins > b.record.wins
                    : a.record.losses < b.record.losses
            }
    }

    // MARK: Batting

    @ViewBuilder
    private var battingSection: some View {
        if !battingLeaders.isEmpty {
            Section(header: Text("Batting").foregroundStyle(.white)) {
                ForEach(battingLeaders, id: \.player.persistentModelID) { entry in
                    NavigationLink {
                        PlayerDetailView(player: entry.player)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.player.name).font(.headline)
                            Text("AVG \(StatFormat.rate(entry.stats.battingAverage)) · H \(entry.stats.hits) · HR \(entry.stats.homeRuns) · RBI \(entry.stats.rbi)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .blitzCardRow()
        }
    }

    // Everyone who batted this season, best OPS first.
    private var battingLeaders: [(player: Player, stats: BattingStats)] {
        seasonPlayers
            .map { (player: $0, stats: $0.battingStats(inSeason: season)) }
            .filter { $0.stats.plateAppearances > 0 }
            .sorted { $0.stats.onBasePlusSlugging > $1.stats.onBasePlusSlugging }
    }

    // MARK: Pitching

    @ViewBuilder
    private var pitchingSection: some View {
        if !pitchingLeaders.isEmpty {
            Section(header: Text("Pitching").foregroundStyle(.white)) {
                ForEach(pitchingLeaders, id: \.player.persistentModelID) { entry in
                    NavigationLink {
                        PlayerDetailView(player: entry.player)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.player.name).font(.headline)
                            Text("IP \(inningsPitched(entry.stats)) · ERA \(StatFormat.ratio(entry.stats.earnedRunAverage)) · K \(entry.stats.strikeouts) · BB \(entry.stats.walksAllowed)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .blitzCardRow()
        }
    }

    // Everyone who pitched this season, lowest ERA first.
    private var pitchingLeaders: [(player: Player, stats: PitchingStats)] {
        seasonPlayers
            .map { (player: $0, stats: $0.pitchingStats(inSeason: season)) }
            .filter { $0.stats.outsRecorded > 0 }
            .sorted { $0.stats.earnedRunAverage < $1.stats.earnedRunAverage }
    }

    private func inningsPitched(_ stats: PitchingStats) -> String {
        "\(stats.outsRecorded / 3).\(stats.outsRecorded % 3)"
    }

    // MARK: Participants

    // Distinct teams appearing in the season's schedule.
    private var seasonTeams: [Team] {
        var seen = Set<PersistentIdentifier>()
        var result: [Team] = []
        for game in season.weeks {
            for team in [game.homeTeam, game.awayTeam].compactMap({ $0 })
            where seen.insert(team.persistentModelID).inserted {
                result.append(team)
            }
        }
        return result
    }

    // Distinct players who have a stat line in any of the season's games.
    private var seasonPlayers: [Player] {
        var seen = Set<PersistentIdentifier>()
        var result: [Player] = []
        for game in season.games {
            for line in game.statLines {
                if let player = line.player, seen.insert(player.persistentModelID).inserted {
                    result.append(player)
                }
            }
        }
        return result
    }
}
