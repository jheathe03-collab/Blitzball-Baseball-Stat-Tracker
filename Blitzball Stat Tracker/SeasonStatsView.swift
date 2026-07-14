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
                    Label("No Seasons Yet", systemImage: "chart.bar")
                } description: {
                    Text("Start a season and play some games to see its stats here.")
                }
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
                }
            }
        }
        .navigationTitle("Season Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One season's stats

struct SeasonStatsDetailView: View {
    let season: Season

    var body: some View {
        List {
            standingsSection
            battingSection
            pitchingSection
        }
        .navigationTitle(season.name.isEmpty ? "Season" : season.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Standings

    @ViewBuilder
    private var standingsSection: some View {
        Section("Standings") {
            if standings.isEmpty {
                Text("No teams set for this season yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(standings, id: \.team.persistentModelID) { entry in
                    HStack {
                        Text(entry.team.name)
                        Spacer()
                        Text("\(entry.record.wins)-\(entry.record.losses)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
            Section("Batting") {
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
            Section("Pitching") {
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
