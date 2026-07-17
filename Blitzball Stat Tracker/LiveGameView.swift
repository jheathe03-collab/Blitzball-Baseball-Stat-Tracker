//
//  LiveGameView.swift
//  Blitzball Stat Tracker
//
//  The live game screen. Tap an outcome to record a plate appearance (updates batter, pitcher,
//  and ghost runners; runners crossing home auto-score). Undo reverts any play; the bases diamond
//  and line-score cells are tap-to-edit failsafes.
//

import SwiftUI
import SwiftData

struct LiveGameView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showSplash = true
    @State private var showEndConfirm = false
    @State private var showBatterPicker = false
    @State private var showPitcherPicker = false
    @State private var showSubstitution = false
    @State private var editingBase: BaseSelection?

    // In-memory Undo history: a snapshot is pushed before each play, capped to the last 100.
    @State private var undoStack: [GameSnapshot] = []
    // A blocked pitcher change (All-Team-Pitch), held to offer an injury override.
    @State private var pitcherChangeError: String?
    @State private var pendingPitcher: Player?
    // Ghost-off "Run" button: the runner being scored (drives the RBI picker) + the who-scored chooser.
    @State private var runToScore: RunToScore?
    @State private var showRunnerChooser = false
    @State private var showGameOver = false

    var body: some View {
        // Once the game is over, this same screen becomes the box score.
        if game.status == .final {
            GameSummaryView(game: game)
        } else {
            liveContent
        }
    }

    private var liveContent: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    Scoreboard(game: game)
                    LineScore(game: game, onAdjust: adjustInningRuns)
                    BasesDiamond(game: game) { index in
                        editingBase = BaseSelection(index: index)
                    }
                    // The manual "Run" button is only for ghost-runners-OFF games, where you push
                    // runners home by hand. With ghost runners ON, hits auto-advance and runs score
                    // automatically, so a manual button would be redundant (and risk double-counting).
                    if !game.settings.ghostRunners {
                        runButton
                    }
                    Divider()
                    batterSection
                    Divider()
                    pitcherSection
                    Divider()
                    controlsSection
                }
                .padding()
            }

            if showSplash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .navigationTitle("Live Game")
        .navigationBarTitleDisplayMode(.inline)
        .blitzDarkBackground()   // solid dark (no gradient) for readability during the game
        .navigationBarBackButtonHidden(true)   // no exit mid-game except End Game
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty)
            }
        }
        .onAppear(perform: startIfNeeded)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
        .sheet(isPresented: $showBatterPicker) {
            LinePicker(title: "Select Batter", lines: game.battingLineup,
                       subtitle: game.currentBatterLine.map { "Current Batter: \($0.player?.name ?? "—")" },
                       selectedPlayer: game.currentBatterLine?.player) { line in
                if let idx = game.battingLineup.firstIndex(where: { $0 === line }) {
                    game.currentBatterIndex = idx
                }
            }
        }
        .sheet(isPresented: $showPitcherPicker) {
            LinePicker(title: "Select Pitcher", lines: game.lineup(isHome: !game.battingIsHome),
                       subtitle: game.activePitcher.map { "Current Pitcher: \($0.name)" },
                       selectedPlayer: game.activePitcher) { line in
                if let player = line.player { attemptPitcherChange(player) }
            }
        }
        .sheet(isPresented: $showSubstitution) {
            SubstitutionView(game: game)
        }
        .alert("Can't Swap Pitcher", isPresented: pitcherChangeAlert, presenting: pitcherChangeError) { _ in
            Button("Override (injury)") {
                if let player = pendingPitcher { _ = game.changePitcher(to: player, override: true) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .sheet(item: $editingBase) { selection in
            BaseEditorSheet(
                baseName: baseName(selection.index),
                lineup: game.battingLineup
            ) { player in
                perform { game.setRunner(player, onBase: selection.index) }
            }
        }
        .alert("End Game?", isPresented: $showEndConfirm) {
            Button("End Game", role: .destructive) {
                game.status = .final   // the view switches to the Game Summary
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let unpitched = game.playersWhoHaventPitched()
            if unpitched.isEmpty {
                Text("This finishes the game. You can review it in the Game Summary.")
            } else {
                Text("These players haven't pitched yet: \(unpitched.map(\.name).joined(separator: ", ")). End the game anyway?")
            }
        }
        .confirmationDialog("Who scored?", isPresented: $showRunnerChooser, titleVisibility: .visible) {
            ForEach(runnersOnBase, id: \.index) { runner in
                Button("\(runner.player.name) — \(baseName(runner.index))") {
                    runToScore = RunToScore(base: runner.index)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(item: $runToScore) { run in
            RBIPicker(lineup: game.battingLineup, justBatted: game.previousBatterLine) { rbiLine in
                perform { game.scoreRunner(onBase: run.base, rbiTo: rbiLine) }
            }
        }
        .alert("Game Over", isPresented: $showGameOver) {
            Button("OK") { game.status = .final }
        } message: {
            Text(gameOverMessage)
        }
    }

    // MARK: - Score a run (ghost-off discretionary scoring)

    /// Runners currently on base, with their base index (0/1/2 = 1st/2nd/3rd).
    private var runnersOnBase: [(index: Int, player: Player)] {
        (0..<3).compactMap { i in game.runner(onBase: i).map { (i, $0) } }
    }

    private var runButton: some View {
        Button { startScoringRun() } label: {
            Label("Run", systemImage: "figure.run")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(runnersOnBase.isEmpty)
    }

    /// One runner → straight to the RBI step; multiple → ask who scored first.
    private func startScoringRun() {
        let runners = runnersOnBase
        if runners.count == 1 {
            runToScore = RunToScore(base: runners[0].index)
        } else if runners.count > 1 {
            showRunnerChooser = true
        }
    }

    private var gameOverMessage: String {
        let home = game.homeTeam?.name ?? "Home"
        let away = game.awayTeam?.name ?? "Away"
        let homeScore = game.homeScore
        let awayScore = game.awayScore
        if homeScore == awayScore {
            return "Final: \(away) \(awayScore), \(home) \(homeScore) — tie game."
        }
        let winner = homeScore > awayScore ? home : away
        return "\(winner) win! Final: \(away) \(awayScore), \(home) \(homeScore)."
    }

    // MARK: - Undo plumbing

    /// Snapshot the game, then run the mutating action — so Undo can revert it.
    private func perform(_ action: () -> Void) {
        undoStack.append(game.snapshot())
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        action()
        // Innings rule: if this play (or run) ended the game, surface the Game Over popup.
        if game.status == .inProgress && game.isComplete {
            showGameOver = true
        }
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        game.restore(from: snapshot)
    }

    private func attemptPitcherChange(_ player: Player) {
        if let error = game.changePitcher(to: player, override: false) {
            pendingPitcher = player
            pitcherChangeError = error
        }
    }

    private var pitcherChangeAlert: Binding<Bool> {
        Binding(get: { pitcherChangeError != nil },
                set: { if !$0 { pitcherChangeError = nil } })
    }

    private func adjustInningRuns(isHome: Bool, inning index: Int, delta: Int) {
        perform {
            game.ensureInningSlots()
            if isHome, index < game.homeInningRuns.count {
                game.homeInningRuns[index] = max(0, game.homeInningRuns[index] + delta)
            } else if !isHome, index < game.awayInningRuns.count {
                game.awayInningRuns[index] = max(0, game.awayInningRuns[index] + delta)
            }
        }
    }

    private func baseName(_ index: Int) -> String {
        ["1st Base", "2nd Base", "3rd Base"][index]
    }

    /// Outcome buttons to show. HBP is only offered when the HBP Walks rule is on (otherwise it
    /// has no effect, so we hide it).
    private var availableOutcomes: [PlateAppearanceOutcome] {
        PlateAppearanceOutcome.allCases.filter { $0 != .hitByPitch || game.settings.hbpWalks }
    }

    // MARK: - Batter

    private var batterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up To Bat").font(.headline)
                if let name = game.battingTeam?.name {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select Batter") { showBatterPicker = true }.font(.subheadline)
            }

            if let batter = game.currentBatterLine {
                Text(batter.player?.name ?? "—").font(.title3).bold()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(availableOutcomes, id: \.self) { outcome in
                        Button(outcome.label) { perform { game.record(outcome) } }
                            .buttonStyle(.borderedProminent)
                            .tint(outcome.isHit ? .green : .blue)
                    }
                }

                BatterCounters(line: batter)
            } else {
                Text("No batters — add players to this team's roster.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pitcher

    private var pitcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pitching").font(.headline)
                if let name = game.fieldingTeam?.name {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select Pitcher") { showPitcherPicker = true }.font(.subheadline)
            }

            if game.settings.allTeamPitch {
                Text("Pitching changes — \(game.homeTeam?.name ?? "Home"): \(game.homePitchingSwaps)/2 · \(game.awayTeam?.name ?? "Away"): \(game.awayPitchingSwaps)/2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pitcherLine = game.activePitcherLine {
                Text(pitcherLine.player?.name ?? "—").font(.title3).bold()
                PitcherCounters(line: pitcherLine)
            } else {
                Text("Tap 'Select Pitcher' to start tracking pitching.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 10) {
            Button { perform { game.advanceHalfInning() } } label: {
                Label("Go to \(nextHalfLabel)", systemImage: "arrow.turn.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { showSubstitution = true } label: {
                Label("Substitute Player", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            NavigationLink { EditGameView(game: game) } label: {
                Label("Edit Stats & Score", systemImage: "pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            NavigationLink { GameSummaryView(game: game) } label: {
                Label("Game Summary", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) { showEndConfirm = true } label: {
                Label("End Game", systemImage: "flag.checkered").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private var nextHalfLabel: String {
        game.isTopInning ? "Bot \(game.currentInning)" : "Top \(game.currentInning + 1)"
    }

    // MARK: - Start / resume

    private func startIfNeeded() {
        guard game.status == .setup else { return }

        // Build/refresh both lineups — this preserves any custom batting order set on Select Teams.
        game.syncLineup(isHome: true, using: modelContext)
        game.syncLineup(isHome: false, using: modelContext)
        game.syncDesignatedHitter(using: modelContext)

        game.currentInning = 1
        game.isTopInning = true
        game.outs = 0
        game.awayInningRuns = [0]
        game.homeInningRuns = [0]
        game.homeBatterIndex = 0
        game.awayBatterIndex = 0
        game.homePitchingSwaps = 0
        game.awayPitchingSwaps = 0
        game.homePitcherOuts = 0
        game.awayPitcherOuts = 0
        game.runnerFirst = nil
        game.runnerSecond = nil
        game.runnerThird = nil
        // Honor a starting pitcher chosen on Select Teams; otherwise default to the leadoff spot.
        if game.homePitcher == nil || !game.lineup(isHome: true).contains(where: { $0.player === game.homePitcher }) {
            game.homePitcher = game.lineup(isHome: true).first?.player
        }
        if game.awayPitcher == nil || !game.lineup(isHome: false).contains(where: { $0.player === game.awayPitcher }) {
            game.awayPitcher = game.lineup(isHome: false).first?.player
        }
        game.status = .inProgress
    }
}

// A tapped base, wrapped so it can drive a `.sheet(item:)`.
private struct BaseSelection: Identifiable {
    let id = UUID()
    let index: Int
}

// The runner being sent home via the "Run" button (drives the RBI picker sheet).
private struct RunToScore: Identifiable {
    let id = UUID()
    let base: Int
}

// Pick who gets the RBI for a manually-scored run — or "No RBI" (wild pitch / error).
private struct RBIPicker: View {
    let lineup: [GameStatLine]
    let justBatted: GameStatLine?
    let onSelect: (GameStatLine?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // The batter who just hit is usually the RBI — surface them first, one tap.
                if let justBatted, let name = justBatted.player?.name {
                    Section("Just batted (most likely)") {
                        Button {
                            onSelect(justBatted); dismiss()
                        } label: {
                            HStack {
                                Text(name).fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "figure.baseball").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Credit RBI to") {
                    ForEach(lineup, id: \.persistentModelID) { line in
                        Button(line.player?.name ?? "—") { onSelect(line); dismiss() }
                    }
                }
                Section {
                    Button("No RBI (wild pitch / error)") { onSelect(nil); dismiss() }
                }
            }
            .navigationTitle("RBI to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Scoreboard

private struct Scoreboard: View {
    @Bindable var game: Game

    var body: some View {
        HStack(alignment: .center) {
            teamColumn(role: "Home", logoName: game.homeTeam?.logoName,
                       name: game.homeTeam?.name ?? "Home", score: game.homeScore)
            Spacer()
            VStack(spacing: 4) {
                Text(game.halfInningLabel).font(.headline)
                Text("\(game.outs) out\(game.outs == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            teamColumn(role: "Away", logoName: game.awayTeam?.logoName,
                       name: game.awayTeam?.name ?? "Away", score: game.awayScore)
        }
    }

    private func teamColumn(role: String, logoName: String?, name: String, score: Int) -> some View {
        VStack(spacing: 2) {
            Text(role.uppercased())
                .font(.caption2).bold()
                .foregroundStyle(.secondary)
            TeamLogoView(logoName: logoName, size: 44)
            Text(name).font(.subheadline).bold().lineLimit(1)
            Text("\(score)").font(.largeTitle).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Line score (per-inning runs + R/H/E), with tap-to-edit run cells

private struct LineScore: View {
    @Bindable var game: Game
    let onAdjust: (_ isHome: Bool, _ inning: Int, _ delta: Int) -> Void

    private var inningCount: Int {
        max(game.currentInning, game.awayInningRuns.count, game.homeInningRuns.count, 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(1...inningCount, id: \.self) { Text("\($0)").bold() }
                    Text("R").bold(); Text("H").bold(); Text("E").bold()
                }
                row(isHome: false, name: game.awayTeam?.name ?? "Away",
                    runs: game.awayInningRuns, total: game.awayScore, hits: game.hits(isHome: false))
                row(isHome: true, name: game.homeTeam?.name ?? "Home",
                    runs: game.homeInningRuns, total: game.homeScore, hits: game.hits(isHome: true))
            }
            .font(.subheadline.monospacedDigit())
        }
    }

    private func row(isHome: Bool, name: String, runs: [Int], total: Int, hits: Int) -> some View {
        GridRow {
            Text(name).bold().lineLimit(1).gridColumnAlignment(.leading)
            ForEach(0..<inningCount, id: \.self) { i in
                if i < runs.count {
                    Menu {
                        Button("Add Run") { onAdjust(isHome, i, 1) }
                        Button("Remove Run") { onAdjust(isHome, i, -1) }
                    } label: {
                        Text("\(runs[i])")
                    }
                } else {
                    Text("")
                }
            }
            Text("\(total)").bold()
            Text("\(hits)")
            Text("0") // errors not tracked yet
        }
    }
}

// MARK: - Editable counter grids (raw counts only; AVG/ERA are never edited)

private struct BatterCounters: View {
    @Bindable var line: GameStatLine

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
            StatStepper(label: "Runs", value: $line.batting.runsScored)
            StatStepper(label: "RBI", value: $line.batting.rbi)
            StatStepper(label: "Hits", value: $line.batting.hits)
            StatStepper(label: "HR", value: $line.batting.homeRuns)
            StatStepper(label: "Walks", value: $line.batting.walks)
            StatStepper(label: "Strikeouts", value: $line.batting.strikeouts)
        }
    }
}

private struct PitcherCounters: View {
    @Bindable var line: GameStatLine

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
            StatStepper(label: "Runs", value: $line.pitching.runsAllowed)
            StatStepper(label: "ER", value: $line.pitching.earnedRuns)
            StatStepper(label: "Hits", value: $line.pitching.hitsAllowed)
            StatStepper(label: "HR", value: $line.pitching.homeRunsAllowed)
            StatStepper(label: "Walks", value: $line.pitching.walksAllowed)
            StatStepper(label: "Strikeouts", value: $line.pitching.strikeouts)
            // In-play outs (outs that aren't strikeouts). Editing keeps total outs = Outs + K.
            StatStepper(label: "Outs", value: Binding(
                get: { line.pitching.outsRecorded - line.pitching.strikeouts },
                set: { line.pitching.outsRecorded = line.pitching.strikeouts + max(0, $0) }
            ))
        }
    }
}

private struct StatStepper: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: 0...999) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(value)").font(.body.monospacedDigit()).bold()
            }
        }
    }
}

// MARK: - Pickers

/// Lists stat lines (players) to pick one.
private struct LinePicker: View {
    let title: String
    let lines: [GameStatLine]
    var subtitle: String? = nil
    var selectedPlayer: Player? = nil
    let onSelect: (GameStatLine) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                List(lines) { line in
                    Button {
                        onSelect(line)
                        dismiss()
                    } label: {
                        HStack {
                            Text(line.player?.name ?? "—")
                            Spacer()
                            if line.player === selectedPlayer {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(line.player === selectedPlayer)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Place or clear a ghost runner on a base.
private struct BaseEditorSheet: View {
    let baseName: String
    let lineup: [GameStatLine]
    let onSet: (Player?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        onSet(nil); dismiss()
                    } label: {
                        Label("Clear Base", systemImage: "xmark.circle")
                    }
                }
                Section("Place Runner") {
                    ForEach(lineup) { line in
                        Button(line.player?.name ?? "—") {
                            onSet(line.player); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(baseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
