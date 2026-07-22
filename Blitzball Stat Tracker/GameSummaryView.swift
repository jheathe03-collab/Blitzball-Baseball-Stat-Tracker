//
//  GameSummaryView.swift
//  Blitzball Stat Tracker
//
//  The box score for a game: per-team batting and pitching tables, read straight from each
//  player's GameStatLine. Rate columns (AVG/OPS/ERA) are computed and read-only.
//

import SwiftUI
import SwiftData

struct GameSummaryView: View {
    @Bindable var game: Game
    /// When set (tournament matches), the final-screen button returns to the bracket instead of the
    /// main menu, and winner advancement happens when the bracket reappears.
    var onBackToBracket: (() -> Void)? = nil
    /// true = home team shown, false = away.
    @State private var showingHome = true
    @Environment(Router.self) private var router

    /// The selected team's lines, in batting order (includes subs; excludes the neutral DH).
    private var lines: [GameStatLine] {
        game.statLines
            .filter { $0.isHome == showingHome && !$0.isDH }
            .sorted { $0.battingOrder < $1.battingOrder }
    }

    /// The shared Designated Hitter's line(s), shown separately (stats aren't a team's).
    private var dhLines: [GameStatLine] {
        game.statLines.filter { $0.isDH }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                finalScoreHeader

                // Inning-by-inning line for the whole game (both teams), read-only.
                Text("Line Score").font(.headline)
                LineScore(game: game)

                Picker("Team", selection: $showingHome) {
                    Text(game.homeTeam?.name ?? "Home").tag(true)
                    Text(game.awayTeam?.name ?? "Away").tag(false)
                }
                .pickerStyle(.segmented)

                Text("Batting Summary").font(.headline)
                BattingBox(lines: lines)

                Text("Pitching Summary").font(.headline)
                let pitchers = lines.filter { $0.pitching.outsRecorded > 0 }
                if pitchers.isEmpty {
                    Text("No pitching recorded for this team.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    PitchingBox(lines: pitchers)
                }

                // The neutral Designated Hitter — kept separate so its stats aren't a team's.
                if !dhLines.isEmpty {
                    Text("Designated Hitter").font(.headline)
                    BattingBox(lines: dhLines, showTotals: false)
                    let dhPitchers = dhLines.filter { $0.pitching.outsRecorded > 0 }
                    if !dhPitchers.isEmpty {
                        PitchingBox(lines: dhPitchers, showTotals: false)
                    }
                }

                // After a game ends, offer a one-tap return — to the bracket for a tournament match,
                // otherwise to the main menu.
                if game.status == .final {
                    if let onBackToBracket {
                        Button {
                            onBackToBracket()
                        } label: {
                            Label("Back to Bracket", systemImage: "chevron.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    } else {
                        Button {
                            router.returnToMainMenu()
                        } label: {
                            Label("Back to Main Menu", systemImage: "house.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Game Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A compact final line: each team's logo + name flanking the score.
    private var finalScoreHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            teamScore(team: game.homeTeam, score: game.homeScore, fallback: "Home")
            Text("–").font(.title2).foregroundStyle(.secondary)
            teamScore(team: game.awayTeam, score: game.awayScore, fallback: "Away")
        }
        .frame(maxWidth: .infinity)
    }

    private func teamScore(team: Team?, score: Int, fallback: String) -> some View {
        VStack(spacing: 6) {
            TeamLogoView(team: team, size: 48)
            Text(team?.name ?? fallback)
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(score)").font(.title.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Batting box score

private struct BattingBox: View {
    let lines: [GameStatLine]
    var showTotals: Bool = true

    private let headers = ["AB", "R", "H", "RBI", "BB", "K", "SB", "AVG", "OPS"]

    var body: some View {
        // Decode each line's batting blob ONCE per render, then use the cached values for BOTH
        // the per-row cells and the TEAM totals reduce. The previous shape decoded each blob
        // twice — once via `line.batting` in the ForEach and once via `$1.batting` in `totals`.
        let cached = lines.map { $0.batting }
        let totals = cached.reduce(BattingStats(), +)

        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Player").bold()
                    ForEach(headers, id: \.self) { Text($0).bold() }
                }
                Divider().gridCellColumns(headers.count + 1)

                ForEach(Array(lines.enumerated()), id: \.element.persistentModelID) { i, line in
                    row(name: line.player?.name ?? "—", b: cached[i], bold: false)
                }

                if showTotals && !lines.isEmpty {
                    Divider().gridCellColumns(headers.count + 1)
                    row(name: "TEAM", b: totals, bold: true)
                }
            }
            .font(.subheadline.monospacedDigit())
        }
    }

    private func row(name: String, b: BattingStats, bold: Bool) -> some View {
        GridRow {
            Text(name).bold(bold).lineLimit(1)
            Text("\(b.atBats)")
            Text("\(b.runsScored)")
            Text("\(b.hits)")
            Text("\(b.rbi)")
            Text("\(b.walks)")
            Text("\(b.strikeouts)")
            Text("\(b.stolenBases)")
            Text(StatFormat.rate(b.battingAverage))
            Text(StatFormat.rate(b.onBasePlusSlugging))
        }
        .fontWeight(bold ? .bold : .regular)
    }
}

// MARK: - Pitching box score

private struct PitchingBox: View {
    let lines: [GameStatLine]
    var showTotals: Bool = true

    private let headers = ["IP", "H", "R", "ER", "BB", "K", "Kʟ", "HR", "ERA"]

    var body: some View {
        // Same one-decode-per-line strategy as BattingBox — see the note there.
        let cached = lines.map { $0.pitching }
        let totals = cached.reduce(PitchingStats(), +)

        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Pitcher").bold()
                    ForEach(headers, id: \.self) { Text($0).bold() }
                }
                Divider().gridCellColumns(headers.count + 1)

                ForEach(Array(lines.enumerated()), id: \.element.persistentModelID) { i, line in
                    row(name: line.player?.name ?? "—", p: cached[i], bold: false)
                }

                if showTotals && !lines.isEmpty {
                    Divider().gridCellColumns(headers.count + 1)
                    row(name: "TEAM", p: totals, bold: true)
                }
            }
            .font(.subheadline.monospacedDigit())
        }
    }

    private func row(name: String, p: PitchingStats, bold: Bool) -> some View {
        GridRow {
            Text(name).bold(bold).lineLimit(1)
            Text(StatFormat.inningsPitched(outs: p.outsRecorded))
            Text("\(p.hitsAllowed)")
            Text("\(p.runsAllowed)")
            Text("\(p.earnedRuns)")
            Text("\(p.walksAllowed)")
            Text("\(p.strikeouts)")
            Text("\(p.strikeoutsLooking)")
            Text("\(p.homeRunsAllowed)")
            Text(StatFormat.ratio(p.earnedRunAverage))
        }
        .fontWeight(bold ? .bold : .regular)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Game.self, Team.self, Player.self, GameStatLine.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let home = Team(name: "Sluggers")
    let away = Team(name: "Mashers")
    let game = Game(homeTeam: home, awayTeam: away)
    container.mainContext.insert(game)

    let mike = Player(name: "Mike")
    let sam = Player(name: "Sam")
    container.mainContext.insert(mike); container.mainContext.insert(sam)

    let l1 = GameStatLine(player: mike, isHome: true, battingOrder: 0,
        batting: BattingStats(atBats: 4, hits: 2, homeRuns: 1, rbi: 2, runsScored: 1),
        pitching: PitchingStats(outsRecorded: 16, earnedRuns: 3, runsAllowed: 3,
                                hitsAllowed: 6, homeRunsAllowed: 1, walksAllowed: 2, strikeouts: 7))
    let l2 = GameStatLine(player: sam, isHome: true, battingOrder: 1,
        batting: BattingStats(atBats: 3, hits: 1, walks: 1, strikeouts: 1))
    l1.game = game; l2.game = game
    container.mainContext.insert(l1); container.mainContext.insert(l2)

    return NavigationStack { GameSummaryView(game: game) }
        .modelContainer(container)
        .environment(Router())
}
