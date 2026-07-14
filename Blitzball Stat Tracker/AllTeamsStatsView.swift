//
//  AllTeamsStatsView.swift
//  Blitzball Stat Tracker
//
//  A horizontally scrollable table of every team's aggregated stats. Each value is computed
//  live from the team's roster via Team.battingTotals / Team.pitchingTotals.
//

import SwiftUI
import SwiftData

struct AllTeamsStatsView: View {
    @Query(sort: \Team.name) private var teams: [Team]
    @Query private var games: [Game]   // for deriving W-L

    // The stat columns, left to right (after the team-name column).
    private let headers = ["AVG", "W-L", "HR", "RBI", "Hits", "ERA", "Saves", "K", "QS"]

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView(
                    "No Teams Yet",
                    systemImage: "tablecells",
                    description: Text("Add teams and players to see combined stats here.")
                )
            } else {
                // Scrolls both ways so all columns fit on one page (deferred: a sticky team column).
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        // Header row.
                        GridRow {
                            Text("Team").bold()
                            ForEach(headers, id: \.self) { header in
                                Text(header).bold()
                            }
                        }
                        Divider().gridCellColumns(headers.count + 1)

                        // One row per team, reading the aggregated values.
                        ForEach(teams) { team in
                            let batting = team.battingTotals
                            let pitching = team.pitchingTotals
                            let record = team.record(from: games)
                            GridRow {
                                Text(team.name).bold()
                                Text(StatFormat.rate(batting.battingAverage))
                                Text("\(record.wins)-\(record.losses)")
                                Text("\(batting.homeRuns)")
                                Text("\(batting.rbi)")
                                Text("\(batting.hits)")
                                Text(StatFormat.ratio(pitching.earnedRunAverage))
                                Text("\(pitching.saves)")
                                Text("\(pitching.strikeouts)")
                                Text("\(pitching.qualityStarts)")
                            }
                            .monospacedDigit()
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("All Teams Stats")
        .navigationBarTitleDisplayMode(.inline)
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
