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
    // Inherited-runner charges from the play just resolved, awaiting confirmation.
    @State private var inheritedCharges: [InheritedCharge] = []
    // The plate appearance being resolved, captured before it's applied and logged in finishPlay.
    @State private var pendingPlay: PlayDraft?
    // Which tab of the live screen is showing.
    @State private var liveTab: LiveTab = .scoring
    // Undone actions, so they can be re-applied. Cleared the moment a new play is recorded.
    @State private var redoStack: [GameSnapshot] = []
    // Placeholder pitch count — tappable, wraps at the rule limit, cleared each plate
    // appearance. Nothing here feeds the stat lines yet.
    @State private var balls = 0
    @State private var strikes = 0
    // Pushed from the game menu (previously stacked buttons under the pad).
    @State private var showEditStats = false
    @State private var showSummary = false
    // Challenge flow (opt-in via settings.challenges): step 1 asks whose challenge; picking a team
    // stashes it here so step 2 can ask the result (successful/failed).
    @State private var showChallengeTeamPicker = false
    @State private var challengeTeamIsHome: Bool?
    // A batted-ball button was tapped and is choosing its contact type (a quick sheet).
    @State private var battedCapture: BattedCapture?
    // Contact type chosen; now waiting for the user to tap WHERE on the live field. While set, the
    // field shows the position pucks and the pad is replaced by a prompt + Cancel.
    @State private var locationCapture: LocationCapture?
    // A fielder's choice mid-resolution: the fielder is chosen, now asking which runner was played
    // on (only when more than one) and then whether they were safe or out.
    @State private var fcCapture: FieldersChoiceCapture?
    @State private var fcPlayedOnBase: Int?

    var body: some View {
        // Once the game is over, this same screen becomes the box score.
        if game.status == .final {
            GameSummaryView(game: game, onBackToBracket: onExit)
        } else {
            liveContent
        }
    }

    // MARK: - Scoring screen (DetailsPro design)

    /// Light scoreboard card up top, the field in the middle flanked by both teams' logos, and the
    /// controls below on the dark background — Undo/Redo, the Steal/Error/Run/Menu row, then the
    /// outcome cards. Laid out to match the DetailsPro mockup exactly.
    private var scoringTab: some View {
        VStack(spacing: 0) {
            headerCard
            fieldArea
            controlArea
        }
    }

    /// A visible divider for the light scoreboard card — the default one is too faint on silver.
    private var headerDivider: some View {
        Rectangle().fill(.black.opacity(0.28)).frame(height: 1)
    }

    private var tabTitle: String {
        switch liveTab {
        case .scoring: return "Live Game"
        case .plays:   return "Play Summary"
        case .stats:   return "Stats"
        case .home:    return game.homeTeam?.name ?? "Home"
        case .away:    return game.awayTeam?.name ?? "Away"
        }
    }

    // MARK: - Header (light scoreboard card)

    /// The whole header renders in light mode so its semantic-colored text — including the reused
    /// LineScore — comes out dark on the silver card, matching the design.
    private var headerCard: some View {
        VStack(spacing: 5) {
            countCluster
            headerDivider
            scoreboardGrid
            headerDivider
            LineScore(game: game, onAdjust: adjustInningRuns, centered: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            // Brushed-metal silver: a light top, a soft dip, and a light base.
            LinearGradient(stops: [
                .init(color: Color(white: 0.90), location: 0.0),
                .init(color: Color(white: 0.78), location: 0.5),
                .init(color: Color(white: 0.86), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .light)
    }

    /// "TOP 1ST — 0 OUTS" on the left, the tappable ball/strike count on the right.
    private var countCluster: some View {
        HStack {
            Text("\(game.halfInningLabel.uppercased()) — \(game.outs) OUT\(game.outs == 1 ? "" : "S")")
                .font(.callout.weight(.heavy))
            Spacer()
            countChip(value: strikes, letter: "S") {
                strikes = strikes + 1 >= game.settings.maxStrikes ? 0 : strikes + 1
            }
            countChip(value: balls, letter: "B") {
                balls = balls + 1 >= game.settings.maxBalls ? 0 : balls + 1
            }
        }
        .foregroundStyle(.black)
    }

    /// A tap bumps the count; it wraps at the rule's limit and clears each plate appearance.
    /// Display only for now — nothing here feeds the stat lines yet.
    private func countChip(value: Int, letter: String, bump: @escaping () -> Void) -> some View {
        Button(action: bump) {
            HStack(spacing: 1) {
                Text("\(value)").font(.subheadline.weight(.heavy)).monospacedDigit()
                Text(letter).font(.caption2.weight(.heavy)).baselineOffset(1)
            }
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }

    /// Team01 (gold) · score | score · Team02, with At Bat / Pitching underneath and Edit links
    /// under the scores — the boxed scoreboard from the design.
    private var scoreboardGrid: some View {
        HStack(alignment: .center, spacing: 6) {
            teamNameCell(isHome: false)
            TeamLogoView(team: game.awayTeam, size: 34)
            scoreCell(game.awayScore) { showBatterPicker = true }
            Rectangle().fill(.black.opacity(0.28)).frame(width: 1, height: 40)
            scoreCell(game.homeScore) { showPitcherPicker = true }
            TeamLogoView(team: game.homeTeam, size: 34)
            teamNameCell(isHome: true)
        }
    }

    private func scoreCell(_ score: Int, edit: @escaping () -> Void) -> some View {
        VStack(spacing: 1) {
            Text("\(score)").font(.subheadline.weight(.bold)).monospacedDigit()
            editLink(edit)
        }
        .foregroundStyle(.black)
    }

    private func editLink(_ action: @escaping () -> Void) -> some View {
        Button("Edit", action: action)
            .font(.caption.weight(.bold))
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
    }

    /// One side of the scoreboard: team name (gold when batting), then At Bat / Pitching + who.
    private func teamNameCell(isHome: Bool) -> some View {
        let team = isHome ? game.homeTeam : game.awayTeam
        let isBatting = game.battingIsHome == isHome
        let who = isBatting ? game.currentBatterLine?.player : game.activePitcher
        let align: HorizontalAlignment = isHome ? .trailing : .leading
        return VStack(alignment: align, spacing: 0) {
            Text(team?.name ?? (isHome ? "Home" : "Away"))
                .font(.callout.weight(isBatting ? .semibold : .medium))
                .foregroundStyle(isBatting ? battingNameColor : .black)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(isBatting ? "AT BAT" : "PITCHING")
                .font(.caption2.weight(.bold)).foregroundStyle(.black.opacity(0.6))
            Text(who?.shortName ?? "—")
                .font(.footnote.weight(.bold)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: isHome ? .trailing : .leading)
    }

    /// The batting team's name color. A deep goldenrod rather than bright yellow, so it stays
    /// legible on the light silver card.
    private var battingNameColor: Color { Color(red: 0.62, green: 0.44, blue: 0.0) }

    // MARK: - Field

    @ViewBuilder
    private var fieldArea: some View {
        if let capture = locationCapture {
            // Location step: the same field, now with tappable position pucks instead of runners.
            FieldPositionPicker { position in
                let capturedType = capture.type
                let outcome = capture.outcome
                locationCapture = nil
                recordOutcome(outcome, battedBallType: capturedType, fieldPosition: position)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            BaseballField(game: game) { index in
                editingBase = BaseSelection(index: index)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlArea: some View {
        if let capture = locationCapture {
            locationPromptBar(capture)
        } else {
            scoringControls
        }
    }

    private var scoringControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                circleButton("arrow.uturn.left", enabled: !undoStack.isEmpty) { undo() }
                circleButton("arrow.uturn.right", enabled: !redoStack.isEmpty) { redo() }
                Spacer()
            }
            HStack(spacing: 10) {
                actionPill("Steal", tint: .yellow, textColor: .black,
                           enabled: !runnersOnBase.isEmpty) { showStealPicker = true }
                Spacer()
                actionPill("Run", tint: .green, textColor: .black,
                           enabled: !runnersOnBase.isEmpty) { startScoringRun() }
                menuPill
            }
            HStack(spacing: 8) {
                ForEach(cardRowOne, id: \.self) { padCard($0) }
            }
            HStack(spacing: 8) {
                ForEach(cardRowTwo, id: \.self) { padCard($0) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.06))
    }

    /// Shown in place of the pad while picking where a batted ball went: a prompt describing the
    /// play plus a Cancel that backs all the way out (records nothing).
    private func locationPromptBar(_ capture: LocationCapture) -> some View {
        VStack(spacing: 10) {
            Text(locationPrompt(for: capture))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                locationCapture = nil
            } label: {
                Text("Cancel").font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color(white: 0.24), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.06))
    }

    /// The instruction shown over the field during the location step. Contact-typed plays ask where
    /// the ball went; the error / fielder's-choice paths (no contact type) ask for the fielder.
    private func locationPrompt(for capture: LocationCapture) -> String {
        if let type = capture.type {
            let noun = type.summaryNoun
            let lead = capture.outcome == .out ? "Out on a \(noun)" : "\(capture.outcome.playLabel) — \(noun)"
            return "\(lead). Tap where it went."
        }
        if capture.outcome.chargesError {
            return "\(capture.outcome.playLabel). Tap the fielder who made the error."
        }
        return "\(capture.outcome.playLabel). Tap the fielder who made the play."
    }

    private var cardRowOne: [PlateAppearanceOutcome] {
        [.walk, .single, .double, .triple, .homeRun]
    }
    private var cardRowTwo: [PlateAppearanceOutcome] {
        var row: [PlateAppearanceOutcome] = [.strikeout, .strikeoutLooking, .out]
        if game.settings.hbpWalks { row.append(.hitByPitch) }
        return row
    }

    /// SF Symbol for each outcome, matching the DetailsPro mockup.
    private func symbol(for outcome: PlateAppearanceOutcome) -> String {
        switch outcome {
        case .walk:                         return "baseball.fill"
        case .single, .double, .triple:     return "figure.baseball"
        case .homeRun:                      return "baseball.circle"
        case .strikeout, .strikeoutLooking: return "baseball.circle.fill"
        case .out:                          return "baseball.circle"
        case .hitByPitch:                   return "bandage.fill"
        default:                            return "baseball"
        }
    }

    /// An outcome card: icon over label. Hits + walk are dark; strikeouts + outs are blue.
    private func padCard(_ outcome: PlateAppearanceOutcome) -> some View {
        let isOutcomeBlue = outcome.isOut
        return Button {
            // Batted balls (hits + in-play outs) first capture contact type and location; walks,
            // strikeouts, and HBP have no batted ball, so they record straight through.
            if needsBattedCapture(outcome) {
                battedCapture = BattedCapture(outcome: outcome)
            } else {
                recordOutcome(outcome)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol(for: outcome)).font(.title3)
                Text(outcome.label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 60)
            .background(isOutcomeBlue ? Color.blue : Color(white: 0.20),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(white: 0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func actionPill(_ title: String, tint: Color, textColor: Color,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.bold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// The gray "Menu" pill — the game menu (half-inning, sub, edit, end game).
    private var menuPill: some View {
        Menu {
            gameMenuItems
        } label: {
            Text("Menu").font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(white: 0.28), in: Capsule())
        }
    }

    /// The two tabs plus the launch splash. Split out from `liveContent` so the long modifier chain
    /// below is type-checked separately — combining them exceeded the compiler's expression budget.
    private var tabbedContent: some View {
        ZStack {
            TabView(selection: $liveTab) {
                scoringTab
                    .tabItem { Label("Scoring", systemImage: "baseball") }
                    .tag(LiveTab.scoring)

                PlaySummaryView(game: game)
                    .tabItem { Label("Plays", systemImage: "chart.bar.horizontal.page") }
                    .tag(LiveTab.plays)

                GameTeamView(game: game, isHome: true)
                    .tabItem { Label("Home", systemImage: "hat.cap.fill") }
                    .tag(LiveTab.home)

                GameTeamView(game: game, isHome: false)
                    .tabItem { Label("Away", systemImage: "figure.baseball") }
                    .tag(LiveTab.away)

                LiveStatsView(game: game)
                    .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                    .tag(LiveTab.stats)
            }

            if showSplash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
    }

    private var liveContent: some View {
        tabbedContent
            .navigationTitle(tabTitle)
        .navigationBarTitleDisplayMode(.inline)
        .blitzDarkBackground()   // solid dark (no gradient) for readability during the game
        .navigationBarBackButtonHidden(true)   // no exit mid-game except End Game
        // The scoring screen is a full-bleed custom layout with its own header, so hide the system
        // bar there. The other tabs keep it for their titles. Undo/Redo live on the scoring screen.
        .toolbar(liveTab == .scoring ? .hidden : .visible, for: .navigationBar)
        .navigationDestination(isPresented: $showEditStats) { EditGameView(game: game) }
        .navigationDestination(isPresented: $showSummary) { GameSummaryView(game: game) }
        .onAppear(perform: startIfNeeded)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
        .modifier(LineupPickerSheets(
            game: game,
            showBatterPicker: $showBatterPicker,
            showPitcherPicker: $showPitcherPicker,
            showSubstitution: $showSubstitution,
            showStealPicker: $showStealPicker,
            pitcherChangeAlert: pitcherChangeAlert,
            pitcherChangeError: pitcherChangeError,
            onPitcherChosen: attemptPitcherChange,
            onOverridePitcher: {
                if let player = pendingPitcher { _ = game.changePitcher(to: player, override: true) }
            },
            onSteal: recordSteal
        ))
        .sheet(item: $battedCapture) { capture in
            ContactTypeSheet(sourceOutcome: capture.outcome,
                             allowsSacFly: allowsSacFly,
                             allowsFieldersChoice: !runnersOnBase.isEmpty) { finalOutcome, type in
                // Sheet closes; the location step happens inline on the field below.
                locationCapture = LocationCapture(outcome: finalOutcome, type: type)
            }
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
        .modifier(GameEndAlerts(
            game: game,
            showEndConfirm: $showEndConfirm,
            showGameOver: $showGameOver,
            reviewingLineScore: $reviewingLineScore,
            gameOverMessage: gameOverMessage
        ))
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
                scoreManualRun(base: run.base, rbiLine: rbiLine)
            }
        }
        .alert(scoringAlertTitle, isPresented: scoringPromptBinding, presenting: currentScoringPrompt) { prompt in
            Button(prompt.targetBase >= 3 ? "Yes, Scored" : "Yes") { answerHitPrompt(advanced: true) }
            Button("No", role: .cancel) { answerHitPrompt(advanced: false) }
        } message: { prompt in
            Text(prompt.message)
        }
        // A run went to a pitcher who's no longer on the mound — confirm it, or override.
        .alert("Inherited Runner Scored", isPresented: inheritedChargeBinding) {
            Button("Keep", role: .cancel) { inheritedCharges = [] }
            Button("Charge to \(game.activePitcher?.name ?? "Current Pitcher")") {
                for charge in inheritedCharges { game.reassignInheritedCharge(charge) }
                inheritedCharges = []
            }
        } message: {
            Text(inheritedChargeMessage)
        }
        // Challenge flow (two-step: whose challenge → result). Extracted into its own modifier to
        // keep this view's modifier chain short enough for the Swift type-checker.
        .modifier(ChallengeDialogs(
            game: game,
            showTeamPicker: $showChallengeTeamPicker,
            teamIsHome: $challengeTeamIsHome,
            onRecord: recordChallenge
        ))
        // Fielder's choice: which runner was played on (when several), then safe or out.
        .modifier(FieldersChoiceDialogs(
            capture: fcCapture,
            playedOnBase: $fcPlayedOnBase,
            baseName: baseName,
            onChoose: { fcPlayedOnBase = $0 },
            onResolve: { out in
                if let capture = fcCapture {
                    resolveFieldersChoice(outcome: capture.outcome, fieldPosition: capture.position,
                                          playedOnBase: fcResolvedRunner?.base, out: out)
                }
            },
            onCancel: { fcCapture = nil; fcPlayedOnBase = nil }
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

    // MARK: - Fielder's choice (which runner → safe or out)

    /// Begin resolving a fielder's choice: stash the fielder and the runners, then let the dialogs
    /// take over — a single runner goes straight to "safe or out?"; several first ask "which runner?".
    private func startFieldersChoice(outcome: PlateAppearanceOutcome, fieldPosition: FieldPosition?) {
        let runners = runnersOnBase.map { FCRunner(base: $0.index, player: $0.player) }
        // No runner to play on (shouldn't happen — the row is hidden) → treat as a plain reach.
        guard !runners.isEmpty else {
            resolveFieldersChoice(outcome: outcome, fieldPosition: fieldPosition, playedOnBase: nil, out: false)
            return
        }
        fcPlayedOnBase = runners.count == 1 ? runners[0].base : nil
        fcCapture = FieldersChoiceCapture(outcome: outcome, position: fieldPosition, runners: runners)
    }

    /// Apply the resolved fielder's choice and log it. `perform` snapshots for Undo and drains the
    /// draft in `finishPlay`.
    private func resolveFieldersChoice(outcome: PlateAppearanceOutcome, fieldPosition: FieldPosition?,
                                       playedOnBase: Int?, out: Bool) {
        balls = 0; strikes = 0
        pendingPlay = PlayDraft(outcome: outcome,
                                fieldPosition: fieldPosition,
                                batter: game.currentBatterLine?.player,
                                pitcher: game.activePitcher,
                                inning: game.currentInning,
                                isTop: game.isTopInning,
                                outs: game.outs,
                                runsBefore: game.homeScore + game.awayScore)
        perform { game.recordFieldersChoice(outcome, playedOnBase: playedOnBase, runnerOut: out) }
        fcCapture = nil
        fcPlayedOnBase = nil
    }

    /// The runner the fielder's choice was made on — set directly for a lone runner, or chosen.
    private var fcResolvedRunner: FCRunner? {
        guard let capture = fcCapture else { return nil }
        return capture.runners.first { $0.base == fcPlayedOnBase }
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
    private func recordOutcome(_ outcome: PlateAppearanceOutcome,
                               battedBallType: BattedBallType? = nil,
                               fieldPosition: FieldPosition? = nil) {
        // A fielder's choice needs the "which runner / safe or out?" prompts before anything is
        // applied, so it takes its own path (the fielder location has already been chosen).
        if outcome.isFieldersChoice {
            startFieldersChoice(outcome: outcome, fieldPosition: fieldPosition)
            return
        }
        // Capture who's up and where we are BEFORE applying the play — `game.record` advances the
        // batter and may roll the half-inning, so reading this afterwards describes the next play.
        let draft = PlayDraft(outcome: outcome,
                              battedBallType: battedBallType,
                              fieldPosition: fieldPosition,
                              batter: game.currentBatterLine?.player,
                              pitcher: game.activePitcher,
                              inning: game.currentInning,
                              isTop: game.isTopInning,
                              outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore)

        guard !game.settings.ghostRunners,
              let baseCount = hitBaseCount(outcome),
              let batter = game.currentBatterLine?.player
        else {
            balls = 0; strikes = 0   // the plate appearance is over
            pendingPlay = draft
            perform { game.record(outcome) }
            return
        }
        balls = 0; strikes = 0   // the plate appearance is over
        // One undo snapshot covers the whole play (record + every runner placement/score).
        pushUndo()
        game.lastPlayInheritedCharges = []   // this path resolves across prompts, bypassing `perform`
        pendingPlay = draft
        game.record(outcome, resolveBasesExternally: true)  // stats/outs/order only — no base moves
        startHitResolution(batter: batter, baseCount: baseCount, hitNoun: hitNoun(outcome))
    }

    /// Which buttons open the contact-type + location capture before recording: the plain hits, the
    /// home run, and an in-play out. Walks, HBP, and strikeouts have no batted ball. (Error and
    /// fielder's choice are reached from inside the contact sheet, not from a pad button.)
    private func needsBattedCapture(_ outcome: PlateAppearanceOutcome) -> Bool {
        switch outcome {
        case .single, .double, .triple, .homeRun, .out: return true
        default: return false
        }
    }

    /// Whether a sacrifice fly can be recorded right now: fewer than the inning's final out (so the
    /// run counts) and a runner on third to tag and score. Gates the Sac Fly row in the contact sheet.
    private var allowsSacFly: Bool {
        game.outs < game.settings.outsPerInning - 1 && game.runner(onBase: 2) != nil
    }

    /// How far the batter got, for the station-to-station resolver: 1/2/3 for anything that puts him
    /// on base off the bat — plain hits and the reached-on-error / fielder's-choice variants alike,
    /// since runners advance the same way either way. Walks and HBP are excluded (they force runners
    /// rather than letting them run), and a home run auto-scores everyone.
    private func hitBaseCount(_ outcome: PlateAppearanceOutcome) -> Int? {
        switch outcome {
        case .walk, .hitByPitch, .homeRun:
            return nil
        default:
            guard let bases = outcome.basesReached, bases <= 3 else { return nil }
            return bases
        }
    }

    /// The noun used in the runner prompts ("Did Sam score on the single?"). Error and
    /// fielder's-choice plays aren't hits, so they read as "play".
    private func hitNoun(_ outcome: PlateAppearanceOutcome) -> String {
        switch outcome {
        case .single: return "single"
        case .double: return "double"
        case .triple: return "triple"
        default:      return outcome.isHit ? "hit" : "play"
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
            // Forced = every base behind this runner (back toward the batter) is occupied, so they
            // have no choice but to advance. A non-forced advance is the runner's decision → we ask.
            let forced = (0..<startBase).allSatisfy { res.occupied.contains($0) }

            if desired >= 3 && res.ahead >= 3 {
                // A true walk-in — a single with every base behind loaded — is forced home with no
                // choice, so score it silently. Otherwise it's the runner's call, so we ask.
                if res.baseCount == 1 && forced {
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
                                                         message: "Did \(name) score on the \(noun)?",
                                                         targetBase: 3)
                }
                return
            }

            // A non-home advance, as far as the runner in front allows.
            let target = min(desired, res.ahead - 1)
            // Not forced, but a base is there for the taking (e.g. a runner on 2nd going to third on
            // a single with first base open) → it's discretionary, so ask instead of auto-advancing.
            if !forced && target > startBase {
                resolution = res
                let name = player.name, base = baseLabel(target)
                DispatchQueue.main.async {   // let any prior alert fully dismiss before re-presenting
                    currentScoringPrompt = ScoringPrompt(player: player,
                                                         message: "Did \(name) take \(base)?",
                                                         targetBase: target)
                }
                return
            }

            // Forced (or nowhere further to go) → advance automatically.
            if target >= 0 { game.setRunner(player, onBase: target); res.ahead = target }
            res.index += 1
        }
        // Everyone placed → the batter takes his base behind them.
        let batterTarget = min(res.baseCount - 1, res.ahead - 1)
        if batterTarget >= 0 { game.setRunner(res.batter, onBase: batterTarget) }
        resolution = nil
        finishPlay()
    }

    private func answerHitPrompt(advanced: Bool) {
        guard var res = resolution, let prompt = currentScoringPrompt else { return }
        let (startBase, player) = res.runners[res.index]
        let isScore = prompt.targetBase >= 3

        if advanced {
            if isScore {
                game.scorePendingRunner(player, rbiTo: game.previousBatterLine)  // RBI → the hitter
                res.ahead = 3   // he's home; runners behind can still advance up to third
            } else {
                game.setRunner(player, onBase: prompt.targetBase)
                res.ahead = prompt.targetBase
            }
        } else if isScore {
            // Held short of home — third if open, otherwise one base back so nobody stacks.
            let target = min(2, res.ahead - 1)
            if target >= 0 { game.setRunner(player, onBase: target); res.ahead = target }
        } else {
            // Declined the extra base — holds where he started (you can nudge him further by hand).
            game.setRunner(player, onBase: startBase)
            res.ahead = startBase
        }

        res.index += 1
        resolution = res
        currentScoringPrompt = nil
        resolveHitStep()
    }

    private var scoringPromptBinding: Binding<Bool> {
        Binding(get: { currentScoringPrompt != nil }, set: { if !$0 { currentScoringPrompt = nil } })
    }

    /// The alert title adapts to the kind of decision: scoring at home vs. taking an extra base.
    private var scoringAlertTitle: String {
        (currentScoringPrompt?.targetBase ?? 3) >= 3 ? "Runner Scored?" : "Runner Advanced?"
    }

    /// Spoken name for a base index, for the discretionary-advance prompt ("Did … take third?").
    private func baseLabel(_ base: Int) -> String {
        switch base {
        case 0:  return "first"
        case 1:  return "second"
        case 2:  return "third"
        default: return "home"
        }
    }

    /// After a play fully resolves, confirm any inherited-runner charges and surface the Game Over
    /// popup if the innings rule ended it.
    private func finishPlay() {
        // `finishPlay` is reached from BOTH `perform` and the terminal step of the ghost-OFF
        // resolver, so draining the draft here logs each play exactly once — multi-prompt hits
        // included. Plays with no draft (base edits, half-inning advances) log at their own sites.
        if let draft = pendingPlay {
            pendingPlay = nil
            let drovein = max(0, (game.homeScore + game.awayScore) - draft.runsBefore)
            game.logPlay(.plateAppearance,
                         outcome: draft.outcome,
                         battedBallType: draft.battedBallType,
                         fieldPosition: draft.fieldPosition,
                         batter: draft.batter,
                         pitcher: draft.pitcher,
                         runsScored: drovein,
                         inning: draft.inning,
                         isTop: draft.isTop,
                         outs: draft.outs,
                         context: modelContext)
        }
        if !game.lastPlayInheritedCharges.isEmpty {
            inheritedCharges = game.lastPlayInheritedCharges
            game.lastPlayInheritedCharges = []
        }
        guard game.status == .inProgress else { return }
        if game.isComplete {
            if !reviewingLineScore { showGameOver = true }
        } else {
            reviewingLineScore = false
        }
    }

    /// Message for the inherited-runner confirmation — who scored and who got billed.
    private var inheritedChargeMessage: String {
        let lines = inheritedCharges
            .map { "\($0.runner) — charged to \($0.chargedTo)" }
            .joined(separator: "\n")
        let plural = inheritedCharges.count == 1 ? "" : "s"
        return "\(lines)\n\nThey were already on base when the current pitcher came in, so the "
            + "run\(plural) went to the pitcher who put them there."
    }

    private var inheritedChargeBinding: Binding<Bool> {
        Binding(get: { !inheritedCharges.isEmpty }, set: { if !$0 { inheritedCharges = [] } })
    }

    // MARK: - Undo plumbing

    private func pushUndo() {
        undoStack.append(game.snapshot())
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        // Doing something new invalidates the redo trail — you can't redo down a branch you left.
        redoStack.removeAll()
    }

    /// Snapshot the game, then run the mutating action — so Undo can revert it.
    private func perform(_ action: () -> Void) {
        pushUndo()
        game.lastPlayInheritedCharges = []   // per-play scratch; finishPlay reads what this play adds
        action()
        finishPlay()
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        // Remember where we were so Redo can come back, then roll the game AND its play log back.
        redoStack.append(game.snapshot())
        game.restore(from: snapshot, context: modelContext)
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(game.snapshot())
        game.restore(from: snapshot, context: modelContext)
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
        let outgoing = game.activePitcher
        if let error = game.changePitcher(to: player, override: false) {
            pendingPitcher = player
            pitcherChangeError = error
        } else {
            logPitchingChange(to: player, from: outgoing)
        }
    }

    /// Note a completed pitching change in the log. Especially worth recording now that runs can be
    /// charged to a pitcher who has already left the mound (inherited runners).
    private func logPitchingChange(to player: Player, from outgoing: Player?) {
        guard player !== outgoing else { return }
        let detail = outgoing.map { "\(player.name) replaces \($0.name) pitching." }
            ?? "\(player.name) takes the mound."
        game.logPlay(.pitchingChange, pitcher: player, detail: detail, context: modelContext)
    }

    private var pitcherChangeAlert: Binding<Bool> {
        Binding(get: { pitcherChangeError != nil },
                set: { if !$0 { pitcherChangeError = nil } })
    }

    private func adjustInningRuns(isHome: Bool, inning index: Int, delta: Int) {
        var applied = 0
        perform {
            game.ensureInningSlots()
            if isHome, index < game.homeInningRuns.count {
                let before = game.homeInningRuns[index]
                game.homeInningRuns[index] = max(0, before + delta)
                applied = game.homeInningRuns[index] - before
            } else if !isHome, index < game.awayInningRuns.count {
                let before = game.awayInningRuns[index]
                game.awayInningRuns[index] = max(0, before + delta)
                applied = game.awayInningRuns[index] - before
            }
        }
        guard applied != 0 else { return }   // clamped at zero — nothing actually changed
        let team = (isHome ? game.homeTeam?.name : game.awayTeam?.name) ?? (isHome ? "Home" : "Away")
        let verb = applied > 0 ? "added to" : "removed from"
        game.logPlay(.lineScoreEdit,
                     detail: "\(abs(applied)) run \(verb) \(team) in inning \(index + 1).",
                     context: modelContext)
    }

    private func baseName(_ index: Int) -> String {
        ["1st Base", "2nd Base", "3rd Base"][index]
    }

    /// Credit a stolen base and note it in the log.
    private func recordSteal(_ line: GameStatLine) {
        perform { line.batting.stolenBases += 1 }
        let who = line.player?.name ?? "Runner"
        game.logPlay(.steal, batter: line.player, pitcher: game.activePitcher,
                     detail: "\(who) steals a base.", context: modelContext)
    }

    /// Send a runner home by hand (ghost-runners-OFF) and note it in the log.
    private func scoreManualRun(base: Int, rbiLine: GameStatLine?) {
        let runner = game.runner(onBase: base)
        perform { game.scoreRunner(onBase: base, rbiTo: rbiLine) }
        let who = runner?.name ?? "Runner"
        var detail = "\(who) scores from \(baseName(base))."
        if let credited = rbiLine?.player?.name { detail += " RBI: \(credited)." }
        game.logPlay(.manualRun, batter: runner, pitcher: game.activePitcher,
                     detail: detail, runsScored: 1, context: modelContext)
    }

    /// Move to the next half-inning and mark the boundary in the log, so the summary reads in
    /// innings the way a scorebook does.
    private func advanceHalfInning() {
        perform { game.advanceHalfInning() }
        let team = game.battingTeam?.name ?? (game.battingIsHome ? "Home" : "Away")
        game.logPlay(.inningChange, detail: "\(game.halfInningLabel) — \(team)", context: modelContext)
    }

    /// Outcome buttons to show. HBP is only offered when the HBP Walks rule is on (otherwise it
    /// has no effect, so we hide it).
    private var availableOutcomes: [PlateAppearanceOutcome] {
        PlateAppearanceOutcome.primaryCases.filter { $0 != .hitByPitch || game.settings.hbpWalks }
    }

    /// The game-menu items behind the "Menu" pill — what used to be a stack of buttons.
    @ViewBuilder
    private var gameMenuItems: some View {
        Button { advanceHalfInning() } label: {
            Label("Go to \(nextHalfLabel)", systemImage: "arrow.turn.down.right")
        }
        Button { showSubstitution = true } label: {
            Label("Substitute Player", systemImage: "arrow.left.arrow.right")
        }
        if game.settings.challenges > 0 {
            Button { showChallengeTeamPicker = true } label: {
                Label("Challenge", systemImage: "hand.raised")
            }
        }
        Divider()
        Button { showEditStats = true } label: {
            Label("Edit Stats & Score", systemImage: "pencil")
        }
        Button { showSummary = true } label: {
            Label("Game Summary", systemImage: "list.bullet.rectangle")
        }
        Divider()
        Button(role: .destructive) { showEndConfirm = true } label: {
            Label("End Game", systemImage: "flag.checkered")
        }
    }

    // MARK: - Batter


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


    // MARK: - Controls


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

        // Seed the log so it always opens with a first line, then the opening half-inning.
        let matchup = "\(game.awayTeam?.name ?? "Away") at \(game.homeTeam?.name ?? "Home")"
        game.logPlay(.gameStart, detail: matchup, context: modelContext)
        let leadOff = game.battingTeam?.name ?? "Away"
        game.logPlay(.inningChange, detail: "\(game.halfInningLabel) — \(leadOff)", context: modelContext)
    }
}

// The two halves of the live screen.
enum LiveTab: Hashable {
    case scoring, plays, stats, home, away
}

/// A plate appearance captured at the moment the button was tapped, held until the play finishes
/// resolving (a ghost-OFF hit can span several prompts) and then written to the log.
struct PlayDraft {
    let outcome: PlateAppearanceOutcome
    /// How the ball was hit and where it went — populated by the type/location capture for batted
    /// balls (hits and in-play outs), nil for walks, strikeouts, and HBP.
    var battedBallType: BattedBallType? = nil
    var fieldPosition: FieldPosition? = nil
    let batter: Player?
    let pitcher: Player?
    let inning: Int
    let isTop: Bool
    let outs: Int
    /// The score before the play, so `finishPlay` can tell how many runs it drove in — a home run
    /// with runners aboard scores several, and the resolver scores them across separate prompts.
    let runsBefore: Int
}

// A tapped base, wrapped so it can drive a `.sheet(item:)`.
private struct BaseSelection: Identifiable {
    let id = UUID()
    let index: Int
}

// A batted-ball button awaiting its contact type, wrapped to drive a `.sheet(item:)`.
private struct BattedCapture: Identifiable {
    let id = UUID()
    let outcome: PlateAppearanceOutcome
}

// A batted ball whose result is chosen, now awaiting an on-field location tap. `type` is nil for the
// error / fielder's-choice paths, where the location names the fielder rather than a contact type.
private struct LocationCapture: Identifiable {
    let id = UUID()
    let outcome: PlateAppearanceOutcome
    let type: BattedBallType?
}

// One runner the defense could play on during a fielder's choice.
private struct FCRunner: Identifiable {
    var id: Int { base }
    let base: Int          // 0/1/2 = 1st/2nd/3rd
    let player: Player
}

// A fielder's choice whose fielder is chosen, now resolving which runner was played on and whether
// they were safe or out.
private struct FieldersChoiceCapture: Identifiable {
    let id = UUID()
    let outcome: PlateAppearanceOutcome
    let position: FieldPosition?
    let runners: [FCRunner]
}

// The runner being sent home via the "Run" button (drives the RBI picker sheet).
private struct RunToScore: Identifiable {
    let id = UUID()
    let base: Int
}

// A baserunning decision prompt currently on screen (ghost-OFF station-to-station flow): either
// "did this runner score?" (targetBase 3) or "did this runner take an extra, non-forced base?".
private struct ScoringPrompt: Identifiable {
    let id = UUID()
    let player: Player
    let message: String
    let targetBase: Int   // 3 = home (a run); otherwise the base index they'd advance to
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

// MARK: - Lineup picker sheets

/// The four "pick somebody from the lineup" sheets — batter, pitcher, substitution, stolen base —
/// plus the alert shown when a pitcher swap is rejected.
///
/// Same reason as `ChallengeDialogs` below: `liveContent` had grown to fifteen chained
/// sheets/alerts, and the Swift type-checker solves a modifier chain as ONE expression, so its cost
/// grows far faster than the number of modifiers. Splitting a self-contained run of them behind a
/// single `.modifier(...)` gives the compiler several small problems instead of one huge one.
/// Purely a compile-time change — the presentations behave exactly as they did inline.
private struct LineupPickerSheets: ViewModifier {
    @Bindable var game: Game
    @Binding var showBatterPicker: Bool
    @Binding var showPitcherPicker: Bool
    @Binding var showSubstitution: Bool
    @Binding var showStealPicker: Bool
    let pitcherChangeAlert: Binding<Bool>
    let pitcherChangeError: String?
    let onPitcherChosen: (Player) -> Void
    let onOverridePitcher: () -> Void
    let onSteal: (GameStatLine) -> Void

    func body(content: Content) -> some View {
        content
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
                    if let player = line.player { onPitcherChosen(player) }
                }
            }
            .sheet(isPresented: $showSubstitution) {
                SubstitutionView(game: game)
            }
            // Credit a stolen base to any batter in the lineup (undoable).
            .sheet(isPresented: $showStealPicker) {
                LinePicker(title: "Stolen Base — who?", lines: game.battingLineup,
                           subtitle: "Credit the stolen base to the baserunner.") { line in
                    onSteal(line)
                }
            }
            .alert("Can't Swap Pitcher", isPresented: pitcherChangeAlert, presenting: pitcherChangeError) { _ in
                Button("Override (injury)") { onOverridePitcher() }
                Button("Cancel", role: .cancel) { }
            } message: { message in
                Text(message)
            }
    }
}

// MARK: - Game-end alerts

/// The two ways a game finishes: the manual "End Game?" confirmation, and the automatic "Game Over"
/// prompt when the engine detects the game is decided. Extracted for the same type-checker reason as
/// `LineupPickerSheets` above.
private struct GameEndAlerts: ViewModifier {
    @Bindable var game: Game
    @Binding var showEndConfirm: Bool
    @Binding var showGameOver: Bool
    @Binding var reviewingLineScore: Bool
    let gameOverMessage: String

    func body(content: Content) -> some View {
        content
            .alert("End Game?", isPresented: $showEndConfirm) {
                Button("End Game", role: .destructive) {
                    game.status = .final   // the view switches to the Game Summary
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                endConfirmMessage
            }
            .alert("Game Over", isPresented: $showGameOver) {
                Button("End Game") { game.status = .final }
                Button("Edit Line Score") { reviewingLineScore = true }
            } message: {
                Text(gameOverMessage + "\n\nEnd the game, or edit the line score if you need to make corrections.")
            }
    }

    /// "Everyone must pitch" is a warning, not a block — you can always end the game anyway.
    @ViewBuilder
    private var endConfirmMessage: some View {
        let unpitched = game.playersWhoHaventPitched()
        if unpitched.isEmpty {
            Text("This finishes the game. You can review it in the Game Summary.")
        } else {
            Text("These players haven't pitched yet: \(unpitched.map(\.name).joined(separator: ", ")). End the game anyway?")
        }
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

// MARK: - Fielder's-choice dialogs

/// The fielder's-choice resolution: an optional "which runner was played on?" step (only when more
/// than one is on base), then "safe or out?". Bundled as a modifier to keep LiveGameView's long
/// presentation chain under the Swift type-checker's limit, like the other dialog modifiers.
private struct FieldersChoiceDialogs: ViewModifier {
    let capture: FieldersChoiceCapture?
    @Binding var playedOnBase: Int?
    let baseName: (Int) -> String
    let onChoose: (Int) -> Void
    let onResolve: (Bool) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Which runner was played on?", isPresented: chooserShown,
                                titleVisibility: .visible) {
                if let capture {
                    ForEach(capture.runners) { runner in
                        Button("\(runner.player.name) — \(baseName(runner.base))") { onChoose(runner.base) }
                    }
                }
                Button("Cancel", role: .cancel) { onCancel() }
            }
            .confirmationDialog(safeOutTitle, isPresented: safeOutShown, titleVisibility: .visible) {
                Button("Safe") { onResolve(false) }
                Button("Out", role: .destructive) { onResolve(true) }
                Button("Cancel", role: .cancel) { onCancel() }
            } message: {
                Text("Was the runner safe, or retired on the play?")
            }
    }

    /// Step 1 appears only with more than one runner and before one is chosen. Dismissing it without
    /// a choice cancels the whole play.
    private var chooserShown: Binding<Bool> {
        Binding(get: { (capture?.runners.count ?? 0) > 1 && playedOnBase == nil },
                set: { if !$0 && playedOnBase == nil { onCancel() } })
    }

    /// Step 2 appears once the runner is known (immediately for a lone runner).
    private var safeOutShown: Binding<Bool> {
        Binding(get: { capture != nil && playedOnBase != nil },
                set: { if !$0 { onCancel() } })
    }

    private var safeOutTitle: String {
        guard let runner = capture?.runners.first(where: { $0.base == playedOnBase }) else {
            return "Safe or Out?"
        }
        return "\(runner.player.name) — Safe or Out?"
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
