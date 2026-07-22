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
    /// Tournament matches pass this so the finished box score can return to the bracket.
    var onExit: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showSplash = true
    @State private var showEndConfirm = false
    @State private var showBatterPicker = false
    @State private var showStealPicker = false
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
    // Set when the user picks "Edit Line Score" on the Game Over popup: suppresses the auto-popup
    // while they fix a scoring mistake. Re-arms automatically if an edit makes the game un-final.
    @State private var reviewingLineScore = false
    // Ghost-OFF hit resolution: the in-progress station-to-station plan, and the "did they score?"
    // prompt currently on screen (nil when none).
    @State private var resolution: HitResolution?
    @State private var currentScoringPrompt: ScoringPrompt?
    // Challenge flow (opt-in via settings.challenges): step 1 asks whose challenge; picking a team
    // stashes it here so step 2 can ask the result (successful/failed).
    @State private var showChallengeTeamPicker = false
    @State private var challengeTeamIsHome: Bool?

    var body: some View {
        // Once the game is over, this same screen becomes the box score.
        if game.status == .final {
            GameSummaryView(game: game, onBackToBracket: onExit)
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
        // Credit a stolen base to any batter in the lineup (undoable).
        .sheet(isPresented: $showStealPicker) {
            LinePicker(title: "Stolen Base — who?", lines: game.battingLineup,
                       subtitle: "Credit the stolen base to the baserunner.") { line in
                perform { line.batting.stolenBases += 1 }
            }
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
                currentRunner: game.runner(onBase: selection.index),
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
            Button("End Game") { game.status = .final }
            Button("Edit Line Score") { reviewingLineScore = true }
        } message: {
            Text(gameOverMessage + "\n\nEnd the game, or edit the line score if you need to make corrections.")
        }
        .alert("Runner Scored?", isPresented: scoringPromptBinding, presenting: currentScoringPrompt) { _ in
            Button("Yes, Scored") { answerHitPrompt(scored: true) }
            Button("No", role: .cancel) { answerHitPrompt(scored: false) }
        } message: { prompt in
            Text(prompt.message)
        }
        // Challenge flow (two-step: whose challenge → result). Extracted into its own modifier to
        // keep this view's modifier chain short enough for the Swift type-checker.
        .modifier(ChallengeDialogs(
            game: game,
            showTeamPicker: $showChallengeTeamPicker,
            teamIsHome: $challengeTeamIsHome,
            onRecord: recordChallenge
        ))
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

    // MARK: - Recording an outcome (ghost-OFF hits → station-to-station + "did they score?")

    /// Entry point for every outcome button. Ghost-runners-OFF hits (1B/2B/3B) run the interactive
    /// station-to-station resolver; everything else (ghost-ON, HR, walks, outs) records directly.
    private func recordOutcome(_ outcome: PlateAppearanceOutcome) {
        guard !game.settings.ghostRunners,
              let baseCount = hitBaseCount(outcome),
              let batter = game.currentBatterLine?.player
        else {
            perform { game.record(outcome) }
            return
        }
        // One undo snapshot covers the whole play (record + every runner placement/score).
        pushUndo()
        game.record(outcome, resolveBasesExternally: true)  // stats/outs/order only — no base moves
        startHitResolution(batter: batter, baseCount: baseCount, hitNoun: hitNoun(outcome))
    }

    /// 1/2/3 for a single/double/triple; nil for anything else (HR auto-scores, so it's excluded).
    private func hitBaseCount(_ outcome: PlateAppearanceOutcome) -> Int? {
        switch outcome {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        default:      return nil
        }
    }

    private func hitNoun(_ outcome: PlateAppearanceOutcome) -> String {
        switch outcome {
        case .single: return "single"
        case .double: return "double"
        case .triple: return "triple"
        default:      return "hit"
        }
    }

    /// Begin resolving a ghost-OFF hit: capture the runners (lead-first), clear the diamond, and
    /// start walking them home — advancing each by the hit's base count and asking about scorers.
    private func startHitResolution(batter: Player, baseCount: Int, hitNoun: String) {
        var runners: [(base: Int, player: Player)] = []
        var occupied: Set<Int> = []
        for i in [2, 1, 0] {   // 3rd, 2nd, 1st — lead runner first
            if let player = game.runner(onBase: i) { runners.append((i, player)); occupied.insert(i) }
        }
        for i in 0..<3 { game.setRunner(nil, onBase: i) }   // re-placed as each is resolved
        resolution = HitResolution(batter: batter, baseCount: baseCount, hitNoun: hitNoun,
                                   occupied: occupied, runners: runners)
        resolveHitStep()
    }

    /// Advance runners until we hit one who reaches home with a clear path (→ prompt) or we run out
    /// (→ place the batter and finish). `ahead` tracks the base held by the runner in front, so a
    /// runner who holds blocks those behind him from stacking or passing.
    private func resolveHitStep() {
        guard var res = resolution else { return }
        while res.index < res.runners.count {
            let (startBase, player) = res.runners[res.index]
            let desired = min(startBase + res.baseCount, 3)   // 3 == home
            if desired >= 3 && res.ahead >= 3 {
                // A true walk-in — a single with every base behind loaded — is forced home with no
                // choice, so score it silently. Doubles/triples (and un-loaded singles) are the
                // runner's decision, so we ask.
                let forcedWalkIn = res.baseCount == 1 && (0..<startBase).allSatisfy { res.occupied.contains($0) }
                if forcedWalkIn {
                    game.scorePendingRunner(player, rbiTo: game.previousBatterLine)
                    res.ahead = 3
                    res.index += 1
                    continue
                }
                // Clear path home, runner's choice → ask (paused until the alert is answered).
                resolution = res
                let name = player.name, noun = res.hitNoun
                DispatchQueue.main.async {   // let any prior alert fully dismiss before re-presenting
                    currentScoringPrompt = ScoringPrompt(player: player,
                                                         message: "Did \(name) score on the \(noun)?")
                }
                return
            }
            // A mover (or a would-be scorer blocked by someone holding ahead): advance as far as the
            // runner in front allows.
            let target = min(desired, res.ahead - 1)
            if target >= 0 { game.setRunner(player, onBase: target); res.ahead = target }
            res.index += 1
        }
        // Everyone placed → the batter takes his base behind them.
        let batterTarget = min(res.baseCount - 1, res.ahead - 1)
        if batterTarget >= 0 { game.setRunner(res.batter, onBase: batterTarget) }
        resolution = nil
        finishPlay()
    }

    private func answerHitPrompt(scored: Bool) {
        guard var res = resolution else { return }
        let player = res.runners[res.index].player
        if scored {
            game.scorePendingRunner(player, rbiTo: game.previousBatterLine)  // RBI → the hitter
            res.ahead = 3   // he's home; runners behind can still advance up to third
        } else {
            // He held short of home — third if open, otherwise one base back so nobody stacks.
            let target = min(2, res.ahead - 1)
            if target >= 0 { game.setRunner(player, onBase: target); res.ahead = target }
        }
        res.index += 1
        resolution = res
        currentScoringPrompt = nil
        resolveHitStep()
    }

    private var scoringPromptBinding: Binding<Bool> {
        Binding(get: { currentScoringPrompt != nil }, set: { if !$0 { currentScoringPrompt = nil } })
    }

    /// After a play fully resolves, surface the Game Over popup if the innings rule ended it.
    private func finishPlay() {
        guard game.status == .inProgress else { return }
        if game.isComplete {
            if !reviewingLineScore { showGameOver = true }
        } else {
            reviewingLineScore = false
        }
    }

    // MARK: - Undo plumbing

    private func pushUndo() {
        undoStack.append(game.snapshot())
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
    }

    /// Snapshot the game, then run the mutating action — so Undo can revert it.
    private func perform(_ action: () -> Void) {
        pushUndo()
        action()
        finishPlay()
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        game.restore(from: snapshot)
    }

    // MARK: - Challenges

    /// Apply the chosen result to the chosen team. Snapshot first so Undo reverts it (no finishPlay:
    /// a challenge changes no outs/score).
    private func recordChallenge(success: Bool) {
        guard let isHome = challengeTeamIsHome else { return }
        pushUndo()
        game.recordChallenge(isHome: isHome, success: success)
        challengeTeamIsHome = nil
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
                HStack {
                    Text(batter.player?.name ?? "—").font(.title3).bold()
                    Spacer()
                    // Steal credits a baserunner, so it opens a picker rather than acting on the
                    // current batter.
                    Button {
                        showStealPicker = true
                    } label: {
                        Label("Steal", systemImage: "figure.run")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    challengeButton
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(availableOutcomes, id: \.self) { outcome in
                        Button(outcome.label) { recordOutcome(outcome) }
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

    /// Challenge button — only when challenges are enabled; disabled once both teams are out.
    @ViewBuilder
    private var challengeButton: some View {
        if game.settings.challenges > 0 {
            Button {
                showChallengeTeamPicker = true
            } label: {
                Label("Challenge", systemImage: "flag.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!game.anyChallengesRemaining)
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
        // With Force Pitcher Rotation on, the first rotation entry starts on the mound for each side.
        game.syncStartingPitchersToRotation()
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

// The "did this runner score?" prompt currently on screen (ghost-OFF station-to-station flow).
private struct ScoringPrompt: Identifiable {
    let id = UUID()
    let player: Player
    let message: String
}

/// In-progress state for resolving a ghost-OFF hit one runner at a time. Runners are ordered
/// lead-first; `index` is how far we've resolved; `ahead` is the base index held by the runner in
/// front (3 = home/clear), which caps how far the next runner may advance.
private struct HitResolution {
    let batter: Player
    let baseCount: Int          // 1/2/3 for single/double/triple
    let hitNoun: String
    let occupied: Set<Int>      // pre-hit base indices, for the forced-walk-in test
    var runners: [(base: Int, player: Player)]
    var index: Int = 0
    var ahead: Int = 3
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
            teamColumn(role: "Home", isHome: true, team: game.homeTeam,
                       name: game.homeTeam?.name ?? "Home", score: game.homeScore)
            Spacer()
            VStack(spacing: 4) {
                Text(game.halfInningLabel).font(.headline)
                Text("\(game.outs) out\(game.outs == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                outsDots
            }
            Spacer()
            teamColumn(role: "Away", isHome: false, team: game.awayTeam,
                       name: game.awayTeam?.name ?? "Away", score: game.awayScore)
        }
    }

    /// One dot per out in the inning; filled (white) for outs recorded so far, white outlines for the rest.
    private var outsDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(game.settings.outsPerInning, 1), id: \.self) { index in
                Circle()
                    .fill(index < game.outs ? Color.white : Color.clear)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.top, 2)
    }

    private func teamColumn(role: String, isHome: Bool, team: Team?, name: String, score: Int) -> some View {
        VStack(spacing: 2) {
            Text(role.uppercased())
                .font(.caption2).bold()
                .foregroundStyle(.secondary)
            TeamLogoView(team: team, size: 44)
            Text(name).font(.subheadline).bold().lineLimit(1)
            Text("\(score)").font(.largeTitle).monospacedDigit()
            // Challenge tally (only when the setting is on): "used of max", plus upheld count.
            if game.settings.challenges > 0 {
                Text("Challenges: \(game.challengesUsed(isHome: isHome)) of \(game.settings.challenges)")
                    .font(.caption2).foregroundStyle(.secondary)
                if game.challengesWon(isHome: isHome) > 0 {
                    Text("\(game.challengesWon(isHome: isHome)) upheld")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Challenge dialogs

/// The two-step challenge flow (whose challenge → result), bundled as a modifier so LiveGameView's
/// long presentation chain stays under the Swift type-checker's complexity limit.
private struct ChallengeDialogs: ViewModifier {
    @Bindable var game: Game
    @Binding var showTeamPicker: Bool
    @Binding var teamIsHome: Bool?
    /// Called with the chosen result (true = successful/overturned).
    let onRecord: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            // Step 1: whose challenge? Only teams with challenges left are offered.
            .confirmationDialog("Whose challenge?", isPresented: $showTeamPicker, titleVisibility: .visible) {
                if game.challengesRemaining(isHome: true) > 0 {
                    Button(game.homeTeam?.name ?? "Home") { teamIsHome = true }
                }
                if game.challengesRemaining(isHome: false) > 0 {
                    Button(game.awayTeam?.name ?? "Away") { teamIsHome = false }
                }
                Button("Cancel", role: .cancel) { }
            }
            // Step 2: result. Successful is retained; failed spends one.
            .confirmationDialog("Challenge result?", isPresented: resultBinding, titleVisibility: .visible) {
                Button("Successful — call overturned") { onRecord(true) }
                Button("Failed — call stood") { onRecord(false) }
                Button("Cancel", role: .cancel) { teamIsHome = nil }
            } message: {
                Text(message)
            }
    }

    /// Step 2 is presented whenever a team has been chosen.
    private var resultBinding: Binding<Bool> {
        Binding(get: { teamIsHome != nil }, set: { if !$0 { teamIsHome = nil } })
    }

    private var message: String {
        guard let isHome = teamIsHome else { return "" }
        let name = (isHome ? game.homeTeam?.name : game.awayTeam?.name) ?? (isHome ? "Home" : "Away")
        return "Recording a challenge for \(name)."
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
            // Clamp Strikeouts to be ≥ strikeoutsLooking (Kʟ is a subset of K by definition).
            // Without the clamp, decrementing below Kʟ silently corrupts data: aggregations start
            // reporting Kʟ > K, which is impossible, and any consumer that computes "swinging Ks
            // = strikeouts - strikeoutsLooking" produces a negative number.
            StatStepper(label: "Strikeouts", value: Binding(
                get: { line.batting.strikeouts },
                set: { line.batting.strikeouts = max($0, line.batting.strikeoutsLooking) }
            ))
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
            // Clamp Strikeouts to be ≥ strikeoutsLooking (same invariant as the batter side).
            StatStepper(label: "Strikeouts", value: Binding(
                get: { line.pitching.strikeouts },
                set: { line.pitching.strikeouts = max($0, line.pitching.strikeoutsLooking) }
            ))
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
    let currentRunner: Player?
    let lineup: [GameStatLine]
    let onSet: (Player?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Who's here right now — the first thing you see. Occupied bases also get a
                // "Clear Base" action; an empty base just says so.
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: currentRunner == nil ? "circle.dashed" : "figure.stand")
                            .font(.title2)
                            .foregroundStyle(currentRunner == nil ? .white.opacity(0.4) : Color.accentColor)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentRunner == nil ? "Base Empty" : "On \(baseName)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(currentRunner?.name ?? "No runner here")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    if currentRunner != nil {
                        Button(role: .destructive) {
                            onSet(nil); dismiss()
                        } label: {
                            Label("Clear Base", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Currently on Base").foregroundStyle(.white)
                }

                Section {
                    ForEach(lineup) { line in
                        let isHere = line.player === currentRunner
                        Button {
                            onSet(line.player); dismiss()
                        } label: {
                            HStack {
                                Text(line.player?.name ?? "—")
                                Spacer()
                                if isHere {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(isHere)   // already on this base — nothing to change
                    }
                } header: {
                    Text(currentRunner == nil ? "Place Runner" : "Replace Runner")
                        .foregroundStyle(.white)
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
