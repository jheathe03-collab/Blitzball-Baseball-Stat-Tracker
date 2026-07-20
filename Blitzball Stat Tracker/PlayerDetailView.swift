//
//  PlayerDetailView.swift
//  Blitzball Stat Tracker
//
//  Shows a single player's stat card. For now it's read-only; next we'll add stat entry.
//

import SwiftUI
import SwiftData
import UIKit

struct PlayerDetailView: View {
    // The player to display. `@Bindable` lets us both read this SwiftData object and (later)
    // edit it with two-way bindings — we'll lean on that when we add stat entry.
    @Bindable var player: Player
    @State private var showingEdit = false
    // Stat filters (nil = "All"). Tournament games don't exist yet, so Tournament shows 0s for now.
    @State private var selectedMode: GameMode?
    @State private var selectedYear: Int?
    // A specific season (only meaningful when Mode = Season). nil = all seasons.
    @State private var selectedSeason: Season?
    // Export state: the generated file to share, and any error to surface.
    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    // For deleting the games that block deleting this player (the "Games" section below).
    @Environment(\.modelContext) private var modelContext
    @Query private var allGames: [Game]
    @State private var gameToDelete: Game?

    // NOTE: these three are computed properties for reuse by non-body code paths (`exportStats`,
    // toolbar predicates, etc.). Inside `body` we HOIST them into local `let`s once, because each
    // read redoes the full filter+reduce over every finished stat line — and each stat-line access
    // decodes a JSON blob. Reading `batting.hits` and `batting.doubles` back-to-back in body would
    // otherwise decode every blob twice.
    private var batting: BattingStats { player.battingStats(mode: selectedMode, year: selectedYear, season: selectedSeason) }
    private var pitching: PitchingStats { player.pitchingStats(mode: selectedMode, year: selectedYear, season: selectedSeason) }
    // How many finished games are in the current filter (shown as "G" in the totals).
    private var games: Int { player.statLines(mode: selectedMode, year: selectedYear, season: selectedSeason).count }

    /// Every game this player is part of (a stat line, or as pitcher/runner/DH) — i.e. exactly the
    /// games that block deleting the player. Newest first.
    ///
    /// We hide SEASON-owned setup weeks: they belong to the season schedule (managed from Resume
    /// Season), the swipe-to-delete is disabled for them anyway (see below), and showing them just
    /// clutters the card. But we DO keep non-season setup games (Exhibition drafts the user
    /// abandoned) — those are swipeable, and hiding them would create a dead-end where deletion is
    /// blocked but the user has no visible game to remove.
    private var playerGames: [Game] {
        allGames.filter { game in
            if game.status == .setup && game.season != nil { return false }
            return game.homePitcher === player || game.awayPitcher === player
                || game.runnerFirst === player || game.runnerSecond === player
                || game.runnerThird === player || game.designatedHitter === player
                || game.statLines.contains { $0.player === player }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // Extracted from `body` to keep each view small enough for the Swift type-checker.
    @ViewBuilder
    private var gamesSection: some View {
        if !playerGames.isEmpty {
            Section {
                ForEach(playerGames, id: \.persistentModelID) { game in
                    gameRow(game)
                        .swipeActions(edge: .trailing) {
                            if game.season == nil {
                                Button(role: .destructive) { gameToDelete = game } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                Text("Games").foregroundStyle(.white)
            } footer: {
                Text("Swipe a game to delete it (this frees the player to be deleted). Season games are removed by deleting the season in Resume Season.")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .blitzCardRow()
        }
    }

    // Extracted from `body` to keep each view small enough for the Swift type-checker.
    @ViewBuilder
    private var filterSection: some View {
        Section(header: Text("Filter").foregroundStyle(.white)) {
            Picker("Mode", selection: $selectedMode) {
                Text("All").tag(GameMode?.none)
                // Tournament isn't shipping in the initial release, so it's hidden here even
                // though the GameMode case still exists (used internally, e.g. GameOptionsView).
                ForEach(GameMode.allCases.filter { $0 != .tournament }, id: \.self) { mode in
                    Text(mode.displayName).tag(GameMode?.some(mode))
                }
            }
            // Sub-filter: when viewing Season stats, narrow to one specific season.
            if selectedMode == .season && !player.statSeasons.isEmpty {
                Picker("Season", selection: $selectedSeason) {
                    Text("All Seasons").tag(Season?.none)
                    ForEach(player.statSeasons, id: \.persistentModelID) { season in
                        Text(season.name.isEmpty ? "Untitled Season" : season.name)
                            .tag(Season?.some(season))
                    }
                }
            }
            Picker("Year", selection: $selectedYear) {
                Text("All").tag(Int?.none)
                ForEach(player.statYears, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
        }
        // Leaving Season mode clears the season sub-filter so it can't silently apply.
        .onChange(of: selectedMode) {
            if selectedMode != .season { selectedSeason = nil }
        }
        .blitzCardRow()
        .tint(.white)   // white picker values/chevrons on the dark card
    }

    var body: some View {
        // Compute each aggregate ONCE per render (see the note on the properties above). Reading
        // `batting`/`pitching` inline inside every StatCell would re-filter finalStatLines and
        // re-decode every stat blob for each cell — 14 batting cells alone = 14× the work.
        let batting = self.batting
        let pitching = self.pitching
        let games = self.games
        // IP in "innings.outs" form (16 outs → "5.1") — inlined here so it uses the local
        // `pitching`, not a computed property that would re-invoke the aggregation.
        let ipText = "\(pitching.outsRecorded / 3).\(pitching.outsRecorded % 3)"

        return List {
            filterSection

            Section(header: Text("Batting").foregroundStyle(.white)) {
                StatCell(label: "AVG", value: StatFormat.rate(batting.battingAverage))
                StatCell(label: "OBP", value: StatFormat.rate(batting.onBasePercentage))
                StatCell(label: "SLG", value: StatFormat.rate(batting.sluggingPercentage))
                StatCell(label: "OPS", value: StatFormat.rate(batting.onBasePlusSlugging))
                StatCell(label: "BB%", value: StatFormat.percent(batting.walkRate))
                StatCell(label: "K%", value: StatFormat.percent(batting.strikeoutRate))
            }
            .blitzCardRow()

            // Raw counting stats (the box-score numbers) for the current filter.
            Section(header: Text("Batting Totals").foregroundStyle(.white)) {
                StatCell(label: "G", value: "\(games)")
                StatCell(label: "PA", value: "\(batting.plateAppearances)")
                StatCell(label: "AB", value: "\(batting.atBats)")
                StatCell(label: "H", value: "\(batting.hits)")
                StatCell(label: "1B", value: "\(batting.singles)")
                StatCell(label: "2B", value: "\(batting.doubles)")
                StatCell(label: "3B", value: "\(batting.triples)")
                StatCell(label: "HR", value: "\(batting.homeRuns)")
                StatCell(label: "RBI", value: "\(batting.rbi)")
                StatCell(label: "R", value: "\(batting.runsScored)")
                StatCell(label: "BB", value: "\(batting.walks)")
                StatCell(label: "K", value: "\(batting.strikeouts)")
                StatCell(label: "Kʟ", value: "\(batting.strikeoutsLooking)")
                StatCell(label: "HBP", value: "\(batting.hitByPitch)")
                StatCell(label: "SB", value: "\(batting.stolenBases)")
            }
            .blitzCardRow()

            Section(header: Text("Pitching").foregroundStyle(.white)) {
                StatCell(label: "ERA", value: StatFormat.ratio(pitching.earnedRunAverage))
                StatCell(label: "WHIP", value: StatFormat.ratio(pitching.walksAndHitsPerInning))
                StatCell(label: "K/BB", value: StatFormat.ratio(pitching.strikeoutToWalkRatio))
                StatCell(label: "BAA", value: StatFormat.rate(pitching.battingAverageAgainst))
            }

            // Raw pitching counting stats for the current filter.
            Section(header: Text("Pitching Totals").foregroundStyle(.white)) {
                StatCell(label: "IP", value: ipText)
                StatCell(label: "H", value: "\(pitching.hitsAllowed)")
                StatCell(label: "R", value: "\(pitching.runsAllowed)")
                StatCell(label: "ER", value: "\(pitching.earnedRuns)")
                StatCell(label: "HR", value: "\(pitching.homeRunsAllowed)")
                StatCell(label: "BB", value: "\(pitching.walksAllowed)")
                StatCell(label: "K", value: "\(pitching.strikeouts)")
                StatCell(label: "SV", value: "\(pitching.saves)")
                StatCell(label: "QS", value: "\(pitching.qualityStarts)")
            }
            .blitzCardRow()

            // Every game this player is in — swipe to delete (frees the player to be deleted).
            gamesSection
        }
        .blitzListStyle()
        .navigationTitle(player.name)
        .blitzballBackground()
        .blitzNavBar()
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingEdit = true } label: {
                        Label("Edit Player", systemImage: "pencil")
                    }
                    Button(action: exportStats) {
                        Label("Export Stats…", systemImage: "square.and.arrow.up")
                    }
                    // Nothing to export until the player has finished-game history.
                    .disabled(player.finalStatLines.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditPlayerView(player: player)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Delete Game?", isPresented: gameDeleteBinding, presenting: gameToDelete) { game in
            Button("Delete Game", role: .destructive) {
                modelContext.delete(game)
                gameToDelete = nil
            }
            Button("Cancel", role: .cancel) { gameToDelete = nil }
        } message: { _ in
            Text("This permanently deletes this game and everyone's stats from it. This can't be undone.")
        }
    }

    // MARK: - Export

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    /// Build the player's archive JSON, write it to a temp file, and present the share sheet.
    private func exportStats() {
        do {
            let data = try PlayerArchive(exporting: player).encoded()
            let url = URL.temporaryDirectory.appending(path: exportFilename)
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// e.g. "Mike-stats-2026-07-14.json" (name sanitized for the filesystem).
    private var exportFilename: String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = player.name.components(separatedBy: illegal).joined()
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "player" : cleaned
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(base)-stats-\(formatter.string(from: .now)).json"
    }

    // MARK: - Games

    private var gameDeleteBinding: Binding<Bool> {
        Binding(get: { gameToDelete != nil }, set: { if !$0 { gameToDelete = nil } })
    }

    private func gameRow(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(game.homeTeam?.name ?? "Home") \(game.homeScore)–\(game.awayScore) \(game.awayTeam?.name ?? "Away")")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(gameSubtitle(game))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func gameSubtitle(_ game: Game) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let date = df.string(from: game.createdAt)
        let kind: String
        switch game.mode {
        case .exhibition: kind = "Exhibition"
        case .season:     kind = (game.season?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Season"
        case .tournament: kind = "Tournament"
        }
        let status = game.status == .final ? "" : (game.status == .setup ? " · Setup" : " · In progress")
        return "\(kind) · \(date)\(status)"
    }
}

/// A shareable file wrapper (Identifiable so it can drive `.sheet(item:)`).
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Bridges UIKit's share sheet (AirDrop / Save to Files / Messages) into SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A single labeled stat: the abbreviation on the left, the value on the right.
private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(.body.monospacedDigit()) // digits line up neatly column-to-column
                .bold()
        }
    }
}

#Preview {
    // Career stats are derived from finished games, so seed one so the preview isn't all zeros.
    let container = try! ModelContainer(
        for: Player.self, Team.self, Game.self, GameStatLine.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let player = Player(name: "Preview Player", jerseyNumber: 7)
    container.mainContext.insert(player)
    let game = Game(status: .final)
    container.mainContext.insert(game)
    let line = GameStatLine(
        player: player, isHome: true, battingOrder: 0,
        batting: BattingStats(plateAppearances: 100, atBats: 90, hits: 30,
                              doubles: 6, triples: 1, homeRuns: 4, walks: 8, strikeouts: 18),
        pitching: PitchingStats(outsRecorded: 90, earnedRuns: 12, runsAllowed: 12,
                                hitsAllowed: 28, walksAllowed: 9, strikeouts: 34, atBatsAgainst: 115)
    )
    line.game = game
    container.mainContext.insert(line)

    return NavigationStack {
        PlayerDetailView(player: player)
    }
    .modelContainer(container)
}
