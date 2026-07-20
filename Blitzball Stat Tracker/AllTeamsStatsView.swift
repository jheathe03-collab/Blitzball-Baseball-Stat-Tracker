//
//  AllTeamsStatsView.swift
//  Blitzball Stat Tracker
//
//  MLB-style "Stat Leaders": a Player ⇄ Team toggle, then Batting and Pitching leader cards that
//  each rank the top 5 by a category. Every value is DERIVED live — teams from
//  Team.battingTotals / pitchingTotals (+ record for Wins), players from Player.careerBatting /
//  careerPitching — so nothing new is stored.
//

import SwiftUI
import SwiftData

struct AllTeamsStatsView: View {
    @Query(sort: \Team.name) private var teams: [Team]
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var games: [Game]   // for deriving team Wins

    @State private var mode: LeaderMode = .team
    @State private var exportFile: CSVExportFile?
    @State private var exportError: String?

    enum LeaderMode: String, CaseIterable, Identifiable {
        case team = "Team"
        case player = "Player"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView(
                    "No Teams Yet",
                    systemImage: "chart.bar",
                    description: Text("Add teams and players, then play a game to see stat leaders here.")
                )
                .foregroundStyle(.white)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("View", selection: $mode) {
                            ForEach(LeaderMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        Text("Batting Leaders").font(.headline)
                        ForEach(battingCards) { $0 }

                        Text("Pitching Leaders").font(.headline)
                        ForEach(pitchingCards) { $0 }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Stat Leaders")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportCSV) {
                    Label("Export Spreadsheet", systemImage: "square.and.arrow.up")
                }
                .disabled(teams.isEmpty)
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

    // MARK: - Leader data

    /// One thing being ranked — a team or a player — flattened to the values the cards need.
    private struct Entity {
        let name: String
        let team: Team?          // for the logo (a player's own team, when they have one)
        let batting: BattingStats
        let pitching: PitchingStats
        let wins: Int
    }

    private var entities: [Entity] {
        switch mode {
        case .team:
            return teams.map { t in
                Entity(name: t.name, team: t, batting: t.battingTotals,
                       pitching: t.pitchingTotals, wins: t.record(from: games).wins)
            }
        case .player:
            return players.map { p in
                Entity(name: p.name, team: p.teams.first, batting: p.careerBatting,
                       pitching: p.careerPitching, wins: 0)
            }
        }
    }

    private let intFormat: (Double) -> String = { String(Int($0)) }

    /// Build the top-5 rows for a category: filter to eligible entities, sort, take five, rank them.
    private func leaderRows(
        value: (Entity) -> Double,
        eligible: (Entity) -> Bool = { _ in true },
        ascending: Bool = false,
        format: (Double) -> String
    ) -> [LeaderRow] {
        let ranked = entities
            .filter(eligible)
            .sorted { ascending ? value($0) < value($1) : value($0) > value($1) }
            .prefix(5)
        return ranked.enumerated().map { index, e in
            LeaderRow(rank: index + 1, name: e.name, team: e.team, value: format(value(e)))
        }
    }

    private var battingCards: [LeaderCard] {
        [
            LeaderCard(title: "Batting Average",
                       rows: leaderRows(value: { $0.batting.battingAverage },
                                        eligible: { $0.batting.atBats > 0 },
                                        format: { StatFormat.rate($0) })),
            LeaderCard(title: "Home Runs",
                       rows: leaderRows(value: { Double($0.batting.homeRuns) }, format: intFormat)),
            LeaderCard(title: "RBI",
                       rows: leaderRows(value: { Double($0.batting.rbi) }, format: intFormat)),
            LeaderCard(title: "Hits",
                       rows: leaderRows(value: { Double($0.batting.hits) }, format: intFormat)),
            LeaderCard(title: "Stolen Bases",
                       rows: leaderRows(value: { Double($0.batting.stolenBases) }, format: intFormat)),
        ]
    }

    private var pitchingCards: [LeaderCard] {
        var cards: [LeaderCard] = []
        // Wins are a team record, not a player stat — only meaningful in Team mode.
        if mode == .team {
            cards.append(LeaderCard(title: "Wins",
                                    rows: leaderRows(value: { Double($0.wins) }, format: intFormat)))
        }
        cards.append(LeaderCard(title: "ERA",
                                rows: leaderRows(value: { $0.pitching.earnedRunAverage },
                                                 eligible: { $0.pitching.outsRecorded > 0 },
                                                 ascending: true,
                                                 format: { StatFormat.ratio($0) })))
        cards.append(LeaderCard(title: "Strikeouts",
                                rows: leaderRows(value: { Double($0.pitching.strikeouts) }, format: intFormat)))
        cards.append(LeaderCard(title: "Saves",
                                rows: leaderRows(value: { Double($0.pitching.saves) }, format: intFormat)))
        return cards
    }

    // MARK: - Export

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private func exportCSV() {
        do {
            let csv = StatsCSV.allTeamsCSV(teams: teams, games: games)
            exportFile = CSVExportFile(url: try StatsCSV.writeTempFile(csv, baseName: "All-Teams"))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Leader card + row

/// A ranked value in a leader card.
private struct LeaderRow: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let team: Team?
    let value: String
}

/// One category's top-5 list, boxed as a dark card (MLB-style leaders block).
private struct LeaderCard: View, Identifiable {
    let id = UUID()
    let title: String
    let rows: [LeaderRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Divider().overlay(Color.white.opacity(0.2))

            if rows.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text("\(row.rank)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 16, alignment: .leading)
                        if let team = row.team {
                            TeamLogoView(team: team, size: 22)
                        }
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text(row.value)
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill,
                    in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Team.self, Player.self, Game.self, GameStatLine.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let team = Team(name: "Sluggers")
    team.players.append(Player(name: "Slugger", jerseyNumber: 9))
    container.mainContext.insert(team)

    return NavigationStack {
        AllTeamsStatsView()
    }
    .modelContainer(container)
}
