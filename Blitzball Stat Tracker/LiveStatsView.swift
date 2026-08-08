//
//  LiveStatsView.swift
//  Blitzball Stat Tracker
//
//  The live game's Stats tab: this game's batting and pitching so far, per team.
//
//  Moved off the scoring screen so that screen fits without scrolling. Reuses the same
//  `BattingBox` / `PitchingBox` tables as the finished-game box score, so the numbers are laid out
//  identically live and after the fact.
//
//  Intentionally basic for now — this screen is slated for its own redesign.
//

import SwiftUI
import SwiftData

struct LiveStatsView: View {
    @Bindable var game: Game
    @State private var side: StatSide = .batting
    /// true = home team shown.
    @State private var showingHome = true

    private enum StatSide: Hashable { case batting, pitching }

    private var lines: [GameStatLine] {
        game.statLines
            .filter { $0.isHome == showingHome && !$0.isDH }
            .sorted { $0.battingOrder < $1.battingOrder }
    }
    private var dhLines: [GameStatLine] { game.statLines.filter(\.isDH) }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Team", selection: $showingHome) {
                Text(game.homeTeam?.name ?? "Home").tag(true)
                Text(game.awayTeam?.name ?? "Away").tag(false)
            }
            .pickerStyle(.segmented)

            Picker("Stat", selection: $side) {
                Text("Batting").tag(StatSide.batting)
                Text("Pitching").tag(StatSide.pitching)
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch side {
                    case .batting:
                        BattingBox(lines: lines)
                        if !dhLines.isEmpty {
                            Text("Designated Hitter").font(.headline).foregroundStyle(.white)
                            BattingBox(lines: dhLines, showTotals: false)
                        }
                        // An always-open key to the columns, right under the numbers.
                        Divider().overlay(.white.opacity(0.2))
                        StatGlossary(title: "Batting Glossary", entries: Self.battingGlossary)
                    case .pitching:
                        // Show anyone who's taken the mound — not just pitchers with an out. Before the
                        // first out a starter has still faced batters (0.0 IP), and the current pitcher
                        // should appear from the very first pitch, so include the active arm too.
                        let active = showingHome ? game.homePitcher : game.awayPitcher
                        let pitchers = lines.filter {
                            $0.pitching.outsRecorded > 0 || $0.pitching.battersFaced > 0 || $0.player === active
                        }
                        if pitchers.isEmpty {
                            Text("No pitching recorded for this team yet.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        } else {
                            PitchingBox(lines: pitchers)
                        }
                        Divider().overlay(.white.opacity(0.2))
                        StatGlossary(title: "Pitching Glossary", entries: Self.pitchingGlossary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Glossaries
    //
    // Plain-English keys to the box-score abbreviations. Kept as data (matching the column order in
    // BattingBox / PitchingBox) so the legend and the table can never drift apart.

    static let battingGlossary: [(abbr: String, name: String)] = [
        ("PA",  "Plate Appearances"),
        ("AB",  "At-Bats"),
        ("R",   "Runs Scored"),
        ("H",   "Hits"),
        ("1B",  "Singles"),
        ("2B",  "Doubles"),
        ("3B",  "Triples"),
        ("HR",  "Home Runs"),
        ("RBI", "Runs Batted In"),
        ("BB",  "Walks"),
        ("K",   "Strikeouts (SO)"),
        ("Kʟ",  "Strikeouts Looking"),
        ("HBP", "Hit By Pitch"),
        ("ROE", "Reached on Error"),
        ("FC",  "Fielder's Choice"),
        ("SB",  "Stolen Bases"),
        ("CS",  "Caught Stealing"),
        ("PIK", "Picked Off"),
        ("AVG", "Batting Average"),
        ("OBP", "On-Base Percentage"),
        ("SLG", "Slugging Percentage"),
        ("OPS", "On-Base Plus Slugging"),
    ]

    static let pitchingGlossary: [(abbr: String, name: String)] = [
        ("IP",   "Innings Pitched"),
        ("BF",   "Batters Faced"),
        ("H",    "Hits Allowed"),
        ("R",    "Runs Allowed"),
        ("ER",   "Earned Runs"),
        ("BB",   "Walks Allowed"),
        ("K",    "Strikeouts (SO)"),
        ("Kʟ",   "Strikeouts Looking"),
        ("HR",   "Home Runs Allowed"),
        ("WP",   "Wild Pitches"),
        ("SB",   "Stolen Bases Allowed"),
        ("CS",   "Runners Caught Stealing"),
        ("PIK",  "Runners Picked Off"),
        ("ERA",  "Earned Run Average"),
        ("#P",   "Total Pitches, incl. HBP (Record Balls and Strikes on)"),
        ("TB",   "Total Balls (Record Balls and Strikes on)"),
        ("TS",   "Total Strikes (Record Balls and Strikes on)"),
        ("WHIP", "Walks + Hits per Inning Pitched"),
        ("BAA",  "Opponent Batting Average"),
    ]
}

/// A compact two-column legend for stat abbreviations — always visible (no tap to expand), so it
/// reads like an index printed under a box score.
private struct StatGlossary: View {
    let title: String
    let entries: [(abbr: String, name: String)]

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .leading),
        GridItem(.flexible(), spacing: 12, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline).foregroundStyle(.white)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(entries, id: \.abbr) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.abbr)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, alignment: .leading)
                        Text(entry.name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
