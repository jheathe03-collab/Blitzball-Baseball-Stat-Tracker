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
    // Lets "Finish Game Later" pop all the way back to the main menu (exhibition/season).
    @Environment(Router.self) private var router

    @State private var showSplash = true
    @State private var showEndConfirm = false
    @State private var showBatterPicker = false
    @State private var showPitcherPicker = false
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
    /// Runners currently trotting the bases (a scoring runner, the batter reaching base, everyone on a
    /// home run). Stepped one leg at a time so they round the bases; see `driveTravelers`.
    @State private var travelers: [RunningRunner] = []
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
    // Pitch-by-pitch tracking (Record Balls and Strikes): the Pitch menu, its Dropped-3rd sub-menu, and
    // — with Record Pitch Type on — a pitch-type prompt shown after a count pitch is chosen.
    @State private var showPitchMenu = false
    @State private var showDroppedThird = false
    // The action a pitch-sheet row picked, run in the sheet's onDismiss so any follow-up (a batted-ball
    // capture, the pitch-type prompt) presents cleanly after the sheet is gone rather than racing it.
    @State private var pitchSheetAction: (() -> Void)?
    @State private var pendingPitchType: PitchCall?
    // Pushed from the game menu (previously stacked buttons under the pad).
    @State private var showEditStats = false
    @State private var showSummary = false
    @State private var showGameOptions = false
    @State private var showChallenges = false
    // Challenge flow (opt-in via settings.challenges): step 1 asks whose challenge; picking a team
    // stashes it here so step 2 can ask the result (successful/failed).
    @State private var showChallengeTeamPicker = false
    @State private var challengeTeamIsHome: Bool?
    // A batted-ball button was tapped and is choosing its contact type (a quick sheet).
    @State private var battedCapture: BattedCapture?
    // Contact type chosen; now waiting for the user to tap WHERE on the live field. While set, the
    // field shows the position pucks and the pad is replaced by a prompt + Cancel.
    @State private var locationCapture: LocationCapture?
    // A batted OUT whose fielder is chosen, now asking the specific out kind (fly out, line out foul…).
    @State private var pendingOutType: PendingOutType?
    // A fielder's choice mid-resolution: the fielder is chosen; on-field Safe/Out buttons on each
    // runner then resolve which runner was played on and whether they were safe or out in one tap.
    @State private var fcCapture: FieldersChoiceCapture?
    // A runner was dragged to a base and is being resolved: on-field Safe/Out, then a reason menu.
    // `stealIsSafe` is nil until Safe/Out is tapped (drives which reason menu shows).
    @State private var pendingSteal: PendingSteal?
    @State private var stealIsSafe: Bool?
    // A forced double play (2+ runners) mid-resolution: after the trot, the lead runner holds at his new
    // base for a Safe/Out call (`forcedDPAwaitingCall`). If he's safe with two runners behind him (bases
    // loaded), the lead scores and a second stage (`forcedDPPickingOut`) asks which of the two trailing
    // runners is the second out.
    @State private var pendingForcedDP: ForcedDoublePlay?
    @State private var forcedDPAwaitingCall = false
    @State private var forcedDPPickingOut = false
    // An "out at first" ground ball mid-resolution: the batter is out at first and the runners advance
    // a base; if one is coming home from third, he holds at the plate for a Safe/Out call
    // (`outAtFirstAwaitingCall`).
    @State private var pendingOutAtFirst: OutAtFirstPlay?
    @State private var outAtFirstAwaitingCall = false
    // A triple play is mid-animation: the batter and two forced runners trot up a base and fade. Fully
    // deterministic (three outs, no runs, no prompts) — this flag just drives the banner and hides the
    // batter while it plays out.
    @State private var animatingTriplePlay = false
    // A staged animation (double-play run-then-out) is playing — the pad is blocked until it finishes.
    @State private var animatingPlay = false

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
        VStack(spacing: 4) {
            countCluster
            headerDivider
            scoreboardGrid
            headerDivider
            LineScore(game: game, onAdjust: adjustInningRuns, centered: true)
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
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

    /// "TOP 1ST — 0 OUTS" on the left, and — only when ball/strike tracking is on — the count on the right.
    private var countCluster: some View {
        HStack {
            Text("\(game.halfInningLabel.uppercased()) — \(game.outs) OUT\(game.outs == 1 ? "" : "S")")
                .font(.callout.weight(.heavy))
            Spacer()
            if game.settings.recordBallsAndStrikes {
                countChip(value: strikes, letter: "S") {
                    strikes = strikes + 1 >= game.settings.maxStrikes ? 0 : strikes + 1
                }
                countChip(value: balls, letter: "B") {
                    balls = balls + 1 >= game.settings.maxBalls ? 0 : balls + 1
                }
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
        // With ball/strike tracking on, the Pitch button drives the count — tapping it would fight the
        // auto walk/strikeout, so it's display-only then.
        .disabled(game.settings.recordBallsAndStrikes)
    }

    /// Team01 (gold) · score | score · Team02, with At Bat / Pitching underneath and Edit links
    /// under the scores — the boxed scoreboard from the design.
    private var scoreboardGrid: some View {
        HStack(alignment: .center, spacing: 6) {
            teamNameCell(isHome: false)
            TeamLogoView(team: game.awayTeam, size: 34)
            scoreCell(game.awayScore) { editTeam(isHome: false) }
            Rectangle().fill(.black.opacity(0.28)).frame(width: 1, height: 40)
            scoreCell(game.homeScore) { editTeam(isHome: true) }
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

    /// The Edit link under a team's score opens the picker for that team's CURRENT role: the team at
    /// bat edits its batter, the team in the field edits its pitcher. Roles swap every half-inning, so
    /// this is keyed off who's batting rather than home/away.
    private func editTeam(isHome: Bool) {
        if game.battingIsHome == isHome {
            showBatterPicker = true
        } else {
            showPitcherPicker = true
        }
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
            // Fixed role label (unlike the batting/fielding status below, which swaps each half-inning).
            Text(isHome ? "HOME" : "AWAY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black.opacity(0.45))
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
                completeLocationCapture(outcome: outcome, type: capturedType, position: position)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            BaseballField(
                game: game,
                onTapBase: { index in editingBase = BaseSelection(index: index) },
                onDragRunner: { fromBase, toBase in
                    pendingSteal = PendingSteal(fromBase: fromBase, toBase: toBase)
                    stealIsSafe = nil
                },
                resolvingBases: resolvingBases,
                onResolve: resolveRunner,
                travelers: travelers.map {
                    BaseballField.Traveler(id: $0.id, player: $0.player, leg: $0.leg)
                },
                hideBatter: pendingForcedDP != nil || pendingOutAtFirst != nil || animatingTriplePlay
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlArea: some View {
        if let capture = locationCapture {
            locationPromptBar(capture)
        } else if isResolvingRunners {
            resolutionPromptBar
        } else if animatingPlay {
            animatingBanner
        } else {
            scoringControls
        }
    }

    /// A non-interactive banner shown while a staged play animates, so the pad can't be tapped.
    private var animatingBanner: some View {
        Text(animatingTriplePlay ? "Triple play…" : (pendingOutAtFirst != nil ? "Out at first…" : "Double play…"))
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 20)
            .background(Color(white: 0.06))
    }

    /// Shown in place of the pad while Safe/Out buttons are up on the field. A prompt + Cancel that
    /// aborts the whole play (records nothing).
    private var resolutionPromptBar: some View {
        VStack(spacing: 10) {
            Text(resolutionPrompt)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                cancelResolution()
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

    private var resolutionPrompt: String {
        if outAtFirstAwaitingCall { return "Play at the plate — Safe or Out?" }
        if forcedDPPickingOut { return "Run scores — now Safe or Out on the runners at second and third." }
        if let callBase = forcedDPCallBase {
            return callBase >= 3 ? "Play at the plate — Safe or Out?" : "Play at third — Safe or Out?"
        }
        if fcCapture != nil { return "Tap Safe or Out on the runner the play was made on." }
        return "Safe or out? Tap on the runner."
    }

    private var scoringControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                circleButton("arrow.uturn.left", enabled: !undoStack.isEmpty) { undo() }
                circleButton("arrow.uturn.right", enabled: !redoStack.isEmpty) { redo() }
                Spacer()
            }
            HStack(spacing: 10) {
                Spacer()
                actionPill("Run", tint: .green, textColor: .black,
                           enabled: !runnersOnBase.isEmpty) { startScoringRun() }
                menuPill
            }
            HStack(spacing: 8) {
                ForEach(cardRowOne, id: \.self) { padCard($0) }
            }
            HStack(spacing: 8) {
                if game.settings.recordBallsAndStrikes {
                    // With pitch tracking on, the K/Kl/Out slots become the most-used pitch calls.
                    pitchShortcutCard("Swing & Miss", icon: "figure.baseball", call: .swingingStrike)
                    pitchShortcutCard("Called Strike", icon: "hand.raised.fill", call: .calledStrike)
                    pitchShortcutCard("Ball", icon: "baseball.fill", call: .ball)
                    if game.settings.hbpWalks { padCard(.hitByPitch) }
                    pitchCard
                } else {
                    ForEach(cardRowTwo, id: \.self) { padCard($0) }
                }
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
    /// What the Pitch menu's "Ball In Play" shortcut offers — the batted outcomes from the pad.
    private var ballInPlayOutcomes: [PlateAppearanceOutcome] {
        [.single, .double, .triple, .homeRun, .out]
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
    /// Begin recording an outcome the way the pad does: batted balls (hits + in-play outs) first
    /// capture contact type and location; walks/strikeouts/HBP record straight through. Shared by the
    /// pad cards and the Pitch menu's "Ball In Play" shortcut.
    private func selectOutcome(_ outcome: PlateAppearanceOutcome) {
        if needsBattedCapture(outcome) {
            battedCapture = BattedCapture(outcome: outcome)
        } else {
            recordOutcome(outcome)
        }
    }

    private func padCard(_ outcome: PlateAppearanceOutcome) -> some View {
        // Outs are blue; HBP rides along so the whole second row (K/Kl/Out/HBP) reads as one blue set.
        let isOutcomeBlue = outcome.isOut || outcome == .hitByPitch
        return Button {
            selectOutcome(outcome)
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

    /// A blue pad shortcut for a common pitch call (Record Balls and Strikes on) — same size as the
    /// other pad cards. Routes through `pitchAction`, so it asks the pitch type when that's on too.
    private func pitchShortcutCard(_ label: String, icon: String, call: PitchCall) -> some View {
        Button { pitchAction(call)() } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.title3)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 60)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// The red "Pitch" pad button — opens the pitch sheet. Same card look as the other pad cards.
    private var pitchCard: some View {
        Button { showPitchMenu = true } label: {
            VStack(spacing: 3) {
                Image(systemName: "baseball.fill").font(.title3)
                Text("Pitch").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 62, height: 60)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// The pitch menu as a grouped bottom sheet (matching the Contact sheet): Ball In Play sits in its
    /// own divided section, the pitch calls in another. Row taps stash their action and dismiss; the
    /// sheet's onDismiss runs it, so any follow-up (contact capture, pitch-type prompt) presents cleanly.
    private var pitchMenuSheet: some View {
        NavigationStack {
            List {
                Section {
                    // A single row that drills into the 1B/2B/3B/HR/Out options, so the sheet stays short.
                    NavigationLink {
                        ballInPlaySubPage
                    } label: {
                        Label("Ball In Play", systemImage: "figure.baseball")
                    }
                }
                // Swing & Miss / Called Strike / Ball live on the pad now; the sheet keeps the rest.
                Section("Pitch") {
                    pitchSheetRow("Foul Ball") { choosePitch(pitchAction(.foul)) }
                    pitchSheetRow("Intentional Walk") { choosePitch { recordOutcome(.walk) } }
                    if inTwoStrikeZone {
                        pitchSheetRow("Foul Tip Out") { choosePitch { recordOutcome(.strikeout) } }
                        pitchSheetRow("Dropped 3rd Strike") { choosePitch { showDroppedThird = true } }
                    }
                    pitchSheetRow("Batter Out (Other)") { choosePitch { recordOutcome(.out) } }
                }
            }
            .navigationTitle("Pitch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPitchMenu = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The Ball In Play sub-page — the batted outcomes, reached from the pitch sheet's "Ball In Play"
    /// row. Picking one dismisses the whole sheet and runs the pad's normal capture flow.
    private var ballInPlaySubPage: some View {
        List {
            ForEach(ballInPlayOutcomes, id: \.self) { outcome in
                pitchSheetRow(outcome.label) { choosePitch { selectOutcome(outcome) } }
            }
        }
        .navigationTitle("Ball In Play")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A pitch-sheet row: label + disclosure chevron, matching the Contact sheet's rows.
    private func pitchSheetRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
    }

    /// What a count pitch does: ask its type first (Record Pitch Type on) or apply straight away.
    private func pitchAction(_ call: PitchCall) -> () -> Void {
        game.settings.recordPitchType ? { pendingPitchType = call } : { applyPitch(call, type: nil) }
    }

    /// Stash a chosen pitch action and dismiss the sheet; `runPitchSheetAction` runs it once we're gone.
    private func choosePitch(_ action: @escaping () -> Void) {
        pitchSheetAction = action
        showPitchMenu = false
    }

    private func runPitchSheetAction() {
        let action = pitchSheetAction
        pitchSheetAction = nil
        action?()
    }

    // MARK: - Pitch tracking (Record Balls and Strikes)

    /// The count is deep enough for the extra menu options (foul tip out, dropped third): two strikes,
    /// or one short of the allowed max when that's fewer.
    private var inTwoStrikeZone: Bool {
        strikes >= min(2, game.settings.maxStrikes - 1)
    }

    private var pitchTypeBinding: Binding<Bool> {
        Binding(get: { pendingPitchType != nil }, set: { if !$0 { pendingPitchType = nil } })
    }

    /// Apply a count pitch: bump the count (a foul advances only up to the brink), log it with its type
    /// when we have one, then record the terminal outcome once the count fills.
    private func applyPitch(_ call: PitchCall, type: PitchType?) {
        switch call {
        case .calledStrike, .swingingStrike: strikes += 1
        case .ball:                          balls += 1
        case .foul:                          if strikes < game.settings.maxStrikes - 1 { strikes += 1 }
        }
        if let type {
            game.logPlay(.pitch, detail: "\(type.label) — \(call.logLabel) (\(balls)-\(strikes))",
                         context: modelContext)
        }
        switch call {
        case .calledStrike:   if strikes >= game.settings.maxStrikes {
            recordOutcome(.strikeoutLooking, strikeoutPitch: type?.label)
        }
        case .swingingStrike: if strikes >= game.settings.maxStrikes {
            recordOutcome(.strikeout, strikeoutPitch: type?.label)
        }
        case .ball:           if balls >= game.settings.maxBalls { recordOutcome(.walk) }
        case .foul:           break
        }
    }

    /// Dropped third strike where the batter reached first — a strikeout with no out, batter safe at
    /// first (forcing runners like a walk). Logged as a strikeout plus a note on how he reached.
    private func droppedThirdStrikeReached(wildPitch: Bool) {
        balls = 0; strikes = 0
        let batter = game.currentBatterLine?.player
        let inning = game.currentInning, isTop = game.isTopInning, outs = game.outs
        let runsBefore = game.homeScore + game.awayScore
        perform {
            game.recordDroppedThirdStrike(wildPitch: wildPitch)
            let runs = max(0, (game.homeScore + game.awayScore) - runsBefore)
            game.logPlay(.plateAppearance, outcome: .strikeout, batter: batter, pitcher: game.activePitcher,
                         runsScored: runs, inning: inning, isTop: isTop, outs: outs, context: modelContext)
            let note = "\(batter?.name ?? "Batter") reaches first on a "
                + "\(wildPitch ? "wild pitch" : "passed ball") (dropped third strike)."
            game.logPlay(.baserunning, batter: batter, pitcher: game.activePitcher,
                         detail: note, context: modelContext)
        }
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
        .sheet(isPresented: $showGameOptions) { CurrentGameOptionsView(settings: game.settings) }
        .sheet(isPresented: $showChallenges) { ChallengesView(game: game) }
        .onAppear(perform: startIfNeeded)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
        .modifier(LineupPickerSheets(
            game: game,
            showBatterPicker: $showBatterPicker,
            showPitcherPicker: $showPitcherPicker,
            pitcherChangeAlert: pitcherChangeAlert,
            pitcherChangeError: pitcherChangeError,
            onPitcherChosen: attemptPitcherChange,
            onOverridePitcher: {
                if let player = pendingPitcher { _ = game.changePitcher(to: player, override: true) }
            }
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
        // The pitch menu (Record Balls and Strikes) — a grouped bottom sheet. A picked row's action runs
        // in onDismiss so any follow-up presents cleanly once this sheet is gone.
        .sheet(isPresented: $showPitchMenu, onDismiss: runPitchSheetAction) { pitchMenuSheet }
        // Dropped 3rd Strike sub-choice — how the batter reached first.
        .confirmationDialog("Dropped 3rd Strike", isPresented: $showDroppedThird, titleVisibility: .visible) {
            Button("Reached Base — Wild Pitch") { droppedThirdStrikeReached(wildPitch: true) }
            Button("Reached Base — Passed Ball") { droppedThirdStrikeReached(wildPitch: false) }
            Button("Cancel", role: .cancel) { }
        }
        // Pitch-type prompt (Record Pitch Type) — shown after a count pitch is chosen from the menu.
        .confirmationDialog("Pitch Type", isPresented: pitchTypeBinding, titleVisibility: .visible) {
            ForEach(PitchType.allCases) { type in
                Button(type.label) {
                    if let call = pendingPitchType { pendingPitchType = nil; applyPitch(call, type: type) }
                }
            }
            Button("Cancel", role: .cancel) { pendingPitchType = nil }
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
        // Steal reason menu — shown after the on-field Safe/Out call (the Safe/Out itself is on the
        // field now, not a dialog).
        .modifier(StealReasonDialog(
            steal: pendingSteal,
            isSafe: stealIsSafe,
            baseLabel: stealBaseLabel,
            onSafeReason: resolveStealSafe,
            onOutReason: resolveStealOut,
            onCancel: { pendingSteal = nil; stealIsSafe = nil }
        ))
        // The specific out kind (fly out, line out foul…), after the fielder is chosen.
        .modifier(OutTypeDialog(
            pending: pendingOutType,
            onChoose: { out in
                guard let p = pendingOutType else { return }
                pendingOutType = nil
                if out == .doublePlay {
                    startDoublePlay(type: p.type, position: p.position)
                } else if out == .triplePlay {
                    startTriplePlay(type: p.type, position: p.position)
                } else if out == .outAtFirst || out == .buntOutAtFirst {
                    // A ground out at first and a bunt out at first both advance the runners a base (the
                    // sac bunt), resolving any runner coming home Safe/Out.
                    startOutAtFirst(type: p.type, position: p.position, outType: out)
                } else {
                    recordOutcome(.out, battedBallType: p.type, fieldPosition: p.position, battedOutType: out)
                }
            },
            onCancel: { pendingOutType = nil }
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

    // MARK: - On-field runner resolution (Safe/Out buttons)

    /// Bases whose runner currently shows Safe/Out buttons on the field — the steal being resolved,
    /// the double-play runners not yet cleared, or the fielder's-choice runners.
    private var resolvingBases: [Int] {
        if let steal = pendingSteal, stealIsSafe == nil { return [steal.fromBase] }
        if let fc = fcCapture { return fc.runners.map(\.base) }
        if let dp = pendingForcedDP {
            if let callBase = forcedDPCallBase { return [callBase] }   // stage 1: lead's base (3 = plate)
            if forcedDPPickingOut { return dp.runnersLeadFirst.dropFirst().map { $0.base + 1 } }  // stage 2
        }
        if outAtFirstAwaitingCall { return [3] }   // the runner coming home from third holds at the plate
        return []
    }

    private var isResolvingRunners: Bool { !resolvingBases.isEmpty }

    /// A Safe (`true`) / Out (`false`) button was tapped for the runner on `base`. Routes to whichever
    /// flow is resolving.
    private func resolveRunner(base: Int, safe: Bool) {
        if pendingOutAtFirst != nil, outAtFirstAwaitingCall {
            finalizeOutAtFirst(safe: safe)            // Safe → run scores; Out → runner out at home
        } else if let dp = pendingForcedDP, forcedDPAwaitingCall {
            resolveForcedDoublePlay(dp, safe: safe)   // Safe → lead safe (run if home); Out → lead out
        } else if let dp = pendingForcedDP, forcedDPPickingOut {
            pickForcedDoublePlayOut(dp, base: base, safe: safe)   // choose which trailing runner is out
        } else if pendingSteal != nil, stealIsSafe == nil {
            stealIsSafe = safe          // the reason menu takes over from here
        } else if let fc = fcCapture {
            resolveFieldersChoice(outcome: fc.outcome, fieldPosition: fc.position,
                                  playedOnBase: base, out: !safe)
        }
    }

    /// Abort whatever runner resolution is up — nothing is recorded. The forced double play never
    /// touched the game state, so clearing its travelers snaps the runners back to their bases.
    private func cancelResolution() {
        pendingSteal = nil; stealIsSafe = nil
        fcCapture = nil
        if pendingForcedDP != nil {
            pendingForcedDP = nil; forcedDPAwaitingCall = false; forcedDPPickingOut = false
            animatingPlay = false
            travelers.removeAll()
        }
        if pendingOutAtFirst != nil {
            pendingOutAtFirst = nil; outAtFirstAwaitingCall = false
            animatingPlay = false
            travelers.removeAll()
        }
    }

    // MARK: - Fielder's choice (tap Safe/Out on the runner played on)

    /// Begin resolving a fielder's choice: stash the fielder + runners, then the on-field Safe/Out
    /// buttons on each runner resolve it (tap the runner the play was made on).
    private func startFieldersChoice(outcome: PlateAppearanceOutcome, fieldPosition: FieldPosition?) {
        let runners = runnersOnBase.map { FCRunner(base: $0.index, player: $0.player) }
        // No runner to play on (shouldn't happen — the row is hidden) → treat as a plain reach.
        guard !runners.isEmpty else {
            resolveFieldersChoice(outcome: outcome, fieldPosition: fieldPosition, playedOnBase: nil, out: false)
            return
        }
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
    }

    // MARK: - Steal / baserunning (drag a runner to a base)

    /// Spoken target-base name for the Safe/Out + reason prompts.
    private func stealBaseLabel(_ index: Int) -> String {
        switch index {
        case 0:  return "1st base"
        case 1:  return "2nd base"
        case 2:  return "3rd base"
        default: return "home"
        }
    }

    private func resolveStealSafe(_ reason: SafeAdvanceReason) {
        applySteal(kind: reason == .stolenBase ? .steal : .baserunning) { steal in
            game.recordSafeAdvance(fromBase: steal.fromBase, toBase: steal.toBase, reason: reason)
        }
    }

    private func resolveStealOut(_ reason: OutReason) {
        applySteal(kind: reason == .caughtStealing ? .caughtStealing : .baserunning) { steal in
            game.recordBaserunningOut(fromBase: steal.fromBase, toBase: steal.toBase, reason: reason)
        }
    }

    /// Snapshot for Undo, apply the engine move, then log it (with any run it scored).
    private func applySteal(kind: PlayEventKind, _ apply: (PendingSteal) -> String) {
        guard let steal = pendingSteal else { return }
        let runner = game.runner(onBase: steal.fromBase)
        let runsBefore = game.homeScore + game.awayScore
        var detail = ""
        perform { detail = apply(steal) }
        let runs = max(0, (game.homeScore + game.awayScore) - runsBefore)
        if !detail.isEmpty {
            game.logPlay(kind, batter: runner, pitcher: game.activePitcher,
                         detail: detail, runsScored: runs, context: modelContext)
        }
        pendingSteal = nil
        stealIsSafe = nil
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

    /// After the fielder is tapped: a plain in-play OUT gets its specific kind (ground/line/fly/pop),
    /// asking only when there's a choice (a ground ball has a single option, so it's auto-applied).
    /// Everything else records straight through.
    private func completeLocationCapture(outcome: PlateAppearanceOutcome,
                                         type: BattedBallType?, position: FieldPosition) {
        if outcome == .out, let type {
            var options = type.outTypeOptions
            // A ground ball with a runner on can instead be an "out at first" that advances the runners.
            if type == .groundBall && !runnersOnBase.isEmpty { options.append(.outAtFirst) }
            if canDoublePlay { options.append(.doublePlay) }
            if canTriplePlay { options.append(.triplePlay) }
            if options.count <= 1 {
                recordOutcome(.out, battedBallType: type, fieldPosition: position,
                              battedOutType: options.first)
            } else {
                pendingOutType = PendingOutType(type: type, position: position, options: options)
            }
            return
        }
        recordOutcome(outcome, battedBallType: type, fieldPosition: position)
    }

    /// A double play is possible: a runner is on base to double off, and there's room for two outs.
    private var canDoublePlay: Bool {
        !runnersOnBase.isEmpty && game.outs <= game.settings.outsPerInning - 2
    }

    /// A triple play is possible: no outs yet, room for three, and runners on first AND second (the two
    /// force points behind the batter) — which covers first-and-second and bases loaded, but not
    /// first-and-third, where the lead runner isn't forced.
    private var canTriplePlay: Bool {
        game.outs == 0 && game.outs <= game.settings.outsPerInning - 3
            && game.runner(onBase: 0) != nil && game.runner(onBase: 1) != nil
    }

    /// Turn the chosen Double Play into an on-field result. Two or more runners run the animated forced
    /// double play (everyone up a base, the lead runner gets the Safe/Out call); a lone runner doubles
    /// off automatically.
    private func startDoublePlay(type: BattedBallType, position: FieldPosition) {
        let runners = runnersOnBase
        if runners.count >= 2 {
            startForcedDoublePlay(type: type, position: position)
        } else if let only = runners.first {
            applyDoublePlay(type: type, position: position, secondOutBase: only.index)
        }
    }

    /// The animated triple play — fully deterministic, no prompts. The batter and both forced runners
    /// (from first and second, plus the runner from third when the bases are loaded) each trot up a base
    /// and fade: three outs, no runs (every out is a force, so no run counts), bases empty. Banked under
    /// one Undo once the trot finishes.
    private func startTriplePlay(type: BattedBallType, position: FieldPosition) {
        guard let batterLine = game.currentBatterLine, let batter = batterLine.player else { return }
        balls = 0; strikes = 0
        animatingTriplePlay = true
        animatingPlay = true                    // block the pad while the trot plays out
        let draft = PlayDraft(outcome: .out, battedBallType: type, fieldPosition: position,
                              battedOutType: .triplePlay, batter: batter, pitcher: game.activePitcher,
                              inning: game.currentInning, isTop: game.isTopInning, outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore)
        // The runners stay in the game state; these travelers are the visual play until it's banked. The
        // batter fades at first; every runner slides up one base and fades — all out. The current batter
        // is hidden (`hideBatter`) so the faded batter doesn't reappear under him.
        var trot: [RunningRunner] = [
            RunningRunner(id: batter.persistentModelID, player: batter,
                          leg: -1, stopAt: 0, arrival: .fadeOnly)          // to first, out
        ]
        for base in 0..<3 {
            if let r = game.runner(onBase: base) {
                trot.append(RunningRunner(id: r.persistentModelID, player: r,
                                          leg: base, stopAt: base + 1, arrival: .fadeOnly))
            }
        }
        travelers = trot
        beginTravel {
            animatingPlay = false
            animatingTriplePlay = false
            pendingPlay = draft
            perform {
                game.finishTriplePlay(batterLine: batterLine)
                travelers.removeAll()
            }
        }
    }

    /// The animated forced double play, for any set of two-plus runners. The batter runs to first and
    /// fades the instant he arrives (out #1); every runner slides up one base and holds; the LEAD runner
    /// (closest to home) waits at his new base for a Safe/Out call. OUT → the lead is the second out
    /// there (no run, even from third); SAFE → the lead is safe (his run counts if he came home) and the
    /// runner right behind him is the second out instead. Nothing hits the game state until the call, so
    /// it's a single Undo. See `resolveForcedDoublePlay`.
    private func startForcedDoublePlay(type: BattedBallType, position: FieldPosition) {
        let runners = runnersOnBase.sorted { $0.index > $1.index }   // lead (highest base) first
        guard runners.count >= 2, let batterLine = game.currentBatterLine,
              let batter = batterLine.player else { return }
        balls = 0; strikes = 0
        animatingPlay = true                    // block the pad while the play develops
        let draft = PlayDraft(outcome: .out, battedBallType: type, fieldPosition: position,
                              battedOutType: .doublePlay, batter: batter, pitcher: game.activePitcher,
                              inning: game.currentInning, isTop: game.isTopInning, outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore)
        pendingForcedDP = ForcedDoublePlay(batterLine: batterLine,
                                           runnersLeadFirst: runners.map { (base: $0.index, player: $0.player) },
                                           draft: draft)
        // The runners stay in the game state; these travelers are the visual play until the call. The
        // batter fades the instant he reaches first (out #1); every runner slides up one base and holds.
        // The current batter is hidden (`hideBatter`) so the faded batter doesn't reappear under him.
        var trot: [RunningRunner] = [
            RunningRunner(id: batter.persistentModelID, player: batter,
                          leg: -1, stopAt: 0, arrival: .fadeOnly)          // to first, then out
        ]
        for r in runners {
            trot.append(RunningRunner(id: r.player.persistentModelID, player: r.player,
                                      leg: r.index, stopAt: r.index + 1, arrival: .hold))
        }
        travelers = trot
        beginTravel {
            animatingPlay = false
            forcedDPAwaitingCall = true          // the lead runner's Safe/Out buttons appear
        }
    }

    /// The base the lead runner is being called at (0/1/2 = a bag, 3 = the plate), or nil if no forced
    /// double play is waiting — drives the on-field buttons, the routing, and the prompt text.
    private var forcedDPCallBase: Int? {
        guard let dp = pendingForcedDP, forcedDPAwaitingCall,
              let lead = dp.runnersLeadFirst.first else { return nil }
        return lead.base + 1
    }

    /// Stage 1 — the Safe/Out call on the lead runner. OUT → he's the second out (no run if he was
    /// coming home), done. SAFE → he survives, scoring if he came home; with a single runner behind him
    /// that runner is automatically the second out, but with TWO behind (bases loaded) we fade the lead
    /// and ask which of the two trailing runners is out (`forcedDPPickingOut`).
    private func resolveForcedDoublePlay(_ dp: ForcedDoublePlay, safe: Bool) {
        guard safe else { finalizeForcedDoublePlay(dp, outIndex: 0); return }   // lead out
        let trailing = dp.runnersLeadFirst.count - 1
        if trailing <= 1 { finalizeForcedDoublePlay(dp, outIndex: 1); return }  // lone runner behind → auto
        // Two runners behind: the lead is safe (fade him — he's scored if he came home), then ask.
        forcedDPAwaitingCall = false
        forcedDPPickingOut = true
        let leadID = dp.runnersLeadFirst[0].player.persistentModelID
        travelers.removeAll { $0.id == leadID }
    }

    /// Stage 2 (bases loaded) — the user tapped Safe/Out on one of the two trailing runners; the other
    /// is the opposite. Out on a runner makes him the second out.
    private func pickForcedDoublePlayOut(_ dp: ForcedDoublePlay, base: Int, safe: Bool) {
        let trailing = Array(dp.runnersLeadFirst.enumerated().dropFirst())     // indices 1…
        guard let tapped = trailing.first(where: { $0.element.base + 1 == base }),
              let other = trailing.first(where: { $0.offset != tapped.offset }) else { return }
        finalizeForcedDoublePlay(dp, outIndex: safe ? other.offset : tapped.offset)
    }

    /// Bank the play under one Undo — batter out plus the runner at `outIndex`, everyone else up a base
    /// (scoring from third) — and clear the trot: survivors hand off to their base chips, the out fades.
    private func finalizeForcedDoublePlay(_ dp: ForcedDoublePlay, outIndex: Int) {
        forcedDPAwaitingCall = false
        forcedDPPickingOut = false
        pendingForcedDP = nil
        pendingPlay = dp.draft
        perform {
            game.finishForcedDoublePlay(batterLine: dp.batterLine,
                                        runnersLeadFirst: dp.runnersLeadFirst,
                                        outIndex: outIndex)
            travelers.removeAll()
        }
    }

    /// Apply a double play. A ground ball / bunt is a force, so it animates in two beats — the runner
    /// runs to the next bag and the batter to first, THEN both are out and fade off. A caught ball
    /// (line/fly/pop) is doubled off in place, so it records immediately.
    private func applyDoublePlay(type: BattedBallType, position: FieldPosition, secondOutBase: Int) {
        guard type == .groundBall || type == .bunt,
              let batterLine = game.currentBatterLine, let batter = batterLine.player,
              let runner = game.runner(onBase: secondOutBase)
        else {
            applyDoublePlayImmediate(type: type, position: position, secondOutBase: secondOutBase)
            return
        }
        balls = 0; strikes = 0
        pushUndo()                              // snapshot the pre-play state for Undo
        game.lastPlayInheritedCharges = []
        animatingPlay = true                    // blocks the pad while the beats play out

        let forcedBase = min(secondOutBase + 1, 2)
        let draft = PlayDraft(outcome: .out, battedBallType: type, fieldPosition: position,
                              battedOutType: .doublePlay, batter: batter, pitcher: game.activePitcher,
                              inning: game.currentInning, isTop: game.isTopInning, outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore)

        // Beat 1: the runners run — forced runner to the next bag, batter to first.
        withAnimation(.easeInOut(duration: 0.4)) {
            game.setRunner(nil, onBase: secondOutBase)
            game.setRunner(runner, onBase: forcedBase)
            game.setRunner(batter, onBase: 0)
        } completion: {
            // Beat 2: they're out — record it and fade them off.
            pendingPlay = draft
            withAnimation(.easeInOut(duration: 0.35)) {
                game.finishGroundBallDoublePlay(batterLine: batterLine, runnerBase: forcedBase, batterBase: 0)
            }
            finishPlay()
            animatingPlay = false
        }
    }

    /// Record a double play in place (caught-ball, doubled off) and log it — no run to animate.
    private func applyDoublePlayImmediate(type: BattedBallType, position: FieldPosition, secondOutBase: Int) {
        balls = 0; strikes = 0
        pendingPlay = PlayDraft(outcome: .out,
                                battedBallType: type,
                                fieldPosition: position,
                                battedOutType: .doublePlay,
                                batter: game.currentBatterLine?.player,
                                pitcher: game.activePitcher,
                                inning: game.currentInning,
                                isTop: game.isTopInning,
                                outs: game.outs,
                                runsBefore: game.homeScore + game.awayScore)
        perform { game.recordDoublePlay(secondOutBase: secondOutBase) }
    }

    // MARK: - Out at first (batter out at first, runners advance a base — the ground out / sac bunt)

    /// An out at first (a ground ball or a sacrifice bunt), with the runners moving up a base. The batter
    /// runs to first and fades (the out); every runner slides up one bag. If a runner is coming home from
    /// third he holds at the plate for a Safe/Out call (the run only counts if he's safe); otherwise the
    /// play records the moment the trot finishes. `outType` distinguishes the two for the log
    /// (`.outAtFirst` vs `.buntOutAtFirst`). Nothing hits the game state until it's finalized, so it's a
    /// single Undo — cancelling snaps the runners back.
    private func startOutAtFirst(type: BattedBallType, position: FieldPosition, outType: BattedOutType) {
        guard let batterLine = game.currentBatterLine, let batter = batterLine.player else { return }
        balls = 0; strikes = 0
        animatingPlay = true                    // block the pad while the trot plays out
        let draft = PlayDraft(outcome: .out, battedBallType: type, fieldPosition: position,
                              battedOutType: outType, batter: batter, pitcher: game.activePitcher,
                              inning: game.currentInning, isTop: game.isTopInning, outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore)
        pendingOutAtFirst = OutAtFirstPlay(batterLine: batterLine, draft: draft)

        // The runners stay in the game state; these travelers are the visual play until it's finalized.
        // The batter fades the instant he reaches first (the out); every runner slides up one base and
        // holds (the runner from third holds at the plate, awaiting his Safe/Out call).
        var trot: [RunningRunner] = [
            RunningRunner(id: batter.persistentModelID, player: batter,
                          leg: -1, stopAt: 0, arrival: .fadeOnly)          // to first, then out
        ]
        for base in 0..<3 {
            if let r = game.runner(onBase: base) {
                trot.append(RunningRunner(id: r.persistentModelID, player: r,
                                          leg: base, stopAt: base + 1, arrival: .hold))
            }
        }
        travelers = trot
        beginTravel {
            animatingPlay = false
            if game.runner(onBase: 2) != nil {
                outAtFirstAwaitingCall = true    // the runner from third holds at the plate for the call
            } else {
                finalizeOutAtFirst(safe: nil)    // no one coming home — just record it
            }
        }
    }

    /// Bank the out-at-first under one Undo — the batter out at first, the runners up a base, and the
    /// runner from third scored (`safe == true`), thrown out at home (`false`), or absent (`nil`) — then
    /// clear the trot so the survivors hand off to their base chips.
    private func finalizeOutAtFirst(safe: Bool?) {
        guard let play = pendingOutAtFirst else { return }
        outAtFirstAwaitingCall = false
        pendingOutAtFirst = nil
        pendingPlay = play.draft
        perform {
            game.finishOutAtFirst(batterLine: play.batterLine, runnerHomeSafe: safe)
            travelers.removeAll()
        }
    }

    /// Entry point for every outcome button. Hits (1B/2B/3B) run the station-to-station resolver so the
    /// runners trot the bases — interactively when ghost runners are off, and forced/prompt-free when
    /// they're on. HR has its own trot; walks/outs and the rest record directly.
    private func recordOutcome(_ outcome: PlateAppearanceOutcome,
                               battedBallType: BattedBallType? = nil,
                               fieldPosition: FieldPosition? = nil,
                               battedOutType: BattedOutType? = nil,
                               strikeoutPitch: String? = nil) {
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
                              battedOutType: battedOutType,
                              batter: game.currentBatterLine?.player,
                              pitcher: game.activePitcher,
                              inning: game.currentInning,
                              isTop: game.isTopInning,
                              outs: game.outs,
                              runsBefore: game.homeScore + game.awayScore,
                              strikeoutPitch: strikeoutPitch)

        // A home run sends everyone around the bases — its own trot, regardless of ghost-runner mode.
        if outcome == .homeRun {
            recordHomeRun(draft: draft)
            return
        }
        // A sacrifice fly trots the runner on third home to score.
        if outcome == .sacrificeFly {
            recordSacFly(draft: draft)
            return
        }

        // Hits (1B/2B/3B and their reach variants) run the traveler resolver in BOTH ghost modes, so the
        // runners trot the bases either way. Ghost-OFF asks about discretionary advances; ghost-ON forces
        // every advance and skips the prompts (see `resolveHitStep`). Everything else records directly.
        guard let baseCount = hitBaseCount(outcome),
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
        game.lastPlayInheritedCharges = []   // this path resolves outside `perform`
        pendingPlay = draft
        game.record(outcome, resolveBasesExternally: true)  // stats/outs/order only — no base moves
        startHitResolution(batter: batter, baseCount: baseCount, hitNoun: hitNoun(outcome))
    }

    /// A home run: the batter and everyone aboard circle the bases and score. We credit the runs and
    /// stats up front (one undo snapshot) and then run the trot as a purely visual layer — the chips
    /// are travelers, so the already-cleared bases don't fight the animation.
    private func recordHomeRun(draft: PlayDraft) {
        balls = 0; strikes = 0
        pushUndo()
        game.lastPlayInheritedCharges = []
        pendingPlay = draft
        guard let batter = game.currentBatterLine?.player else {
            game.record(.homeRun); finishPlay(); return
        }
        // Snapshot the trot BEFORE recording, since `record` clears the bases and advances the order.
        var trot: [RunningRunner] = []
        for base in 0..<3 {
            if let r = game.runner(onBase: base) {
                trot.append(RunningRunner(id: r.persistentModelID, player: r,
                                          leg: base, stopAt: 4, arrival: .fadeOnly))
            }
        }
        trot.append(RunningRunner(id: batter.persistentModelID, player: batter,
                                  leg: -1, stopAt: 4, arrival: .fadeOnly))
        travelers = trot            // take over the field first, so clearing the bases is invisible…
        game.record(.homeRun)       // …then bank the runs, RBIs, and stats
        beginTravel { finishPlay() }
    }

    /// A sacrifice fly: the batter is out and the runner on third tags and trots home to score. We bank
    /// the run/out up front, then run him home as a purely visual layer (like the home-run trot).
    private func recordSacFly(draft: PlayDraft) {
        balls = 0; strikes = 0
        pushUndo()
        game.lastPlayInheritedCharges = []
        pendingPlay = draft
        guard let scorer = game.runner(onBase: 2) else {   // no one on third — just record it
            game.record(.sacrificeFly); finishPlay(); return
        }
        // The runner from third takes over as a traveler (so clearing him from the bag is invisible),
        // then the run and the out bank, then he trots home and fades as he scores.
        travelers = [RunningRunner(id: scorer.persistentModelID, player: scorer,
                                   leg: 2, stopAt: 4, arrival: .fadeOnly)]
        game.record(.sacrificeFly)
        beginTravel { finishPlay() }
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
        // Ghost runners ON = every runner is forced up by the hit, so there are no decisions — we skip
        // the "did he score / take the extra base?" prompts and just trot everyone to their bag/home.
        let promptless = game.settings.ghostRunners
        while res.index < res.runners.count {
            let (startBase, player) = res.runners[res.index]
            let desired = min(startBase + res.baseCount, 3)   // 3 == home
            // Forced = every base behind this runner (back toward the batter) is occupied, so they
            // have no choice but to advance. A non-forced advance is the runner's decision → we ask.
            let forced = (0..<startBase).allSatisfy { res.occupied.contains($0) }

            if desired >= 3 && res.ahead >= 3 {
                // Forced home (a loaded-bases walk-in, or any ghost-on runner reaching home) → trot him
                // home to score in tandem with the rest. Otherwise it's the runner's call, so we ask.
                if promptless || (res.baseCount == 1 && forced) {
                    travelers.append(RunningRunner(id: player.persistentModelID, player: player,
                                                   leg: startBase, stopAt: 4,
                                                   arrival: .scorePending(game.previousBatterLine)))
                    res.ahead = 3
                    res.index += 1
                    continue
                }
                // Clear path home, runner's choice → ask (paused until the alert is answered). Put him
                // back on his base first, so he's visible to decide about — and has somewhere to run
                // FROM if he scores.
                game.setRunner(player, onBase: startBase)
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
            // Ghost-on skips the ask (every advance is forced).
            if !promptless && !forced && target > startBase {
                game.setRunner(player, onBase: startBase)   // show him on his base while we ask
                resolution = res
                let name = player.name, base = baseLabel(target)
                DispatchQueue.main.async {   // let any prior alert fully dismiss before re-presenting
                    currentScoringPrompt = ScoringPrompt(player: player,
                                                         message: "Did \(name) take \(base)?",
                                                         targetBase: target)
                }
                return
            }

            // Forced (or nowhere further to go) → queue his advance as a trot, so he rounds the bases
            // in tandem with the batter and the other runners rather than snapping to his new bag.
            if target >= 0 {
                travelers.append(RunningRunner(id: player.persistentModelID, player: player,
                                               leg: startBase, stopAt: target,
                                               arrival: .stopOnBase(target)))
                res.ahead = target
            }
            res.index += 1
        }
        // Everyone's advance is queued → add the batter and trot them all home together.
        let batterTarget = min(res.baseCount - 1, res.ahead - 1)
        resolution = nil
        if batterTarget >= 0 {
            travelers.append(RunningRunner(id: res.batter.persistentModelID, player: res.batter,
                                           leg: -1, stopAt: batterTarget,
                                           arrival: .stopOnBase(batterTarget)))
        }
        if travelers.isEmpty { finishPlay() } else { beginTravel { finishPlay() } }
    }

    private func answerHitPrompt(advanced: Bool) {
        guard var res = resolution, let prompt = currentScoringPrompt else { return }
        let (startBase, player) = res.runners[res.index]
        let isScore = prompt.targetBase >= 3

        // A runner who scores gets the staged "run home". Queue it as a traveler and KEEP resolving,
        // rather than trotting him home alone first: the batter and any other runners get added to the
        // same trot, so the scorer rounds toward home in tandem with the batter reaching his base (the
        // final `beginTravel` in `resolveHitStep` moves them all together) — matching the "take third"
        // and forced-advance animations.
        if advanced && isScore {
            let rbiLine = game.previousBatterLine
            res.ahead = 3            // he's home; runners behind can still advance up to third
            res.index += 1
            resolution = res
            currentScoringPrompt = nil
            game.setRunner(nil, onBase: startBase)   // hand his base chip off to the trotting chip
            travelers.append(RunningRunner(id: player.persistentModelID, player: player,
                                           leg: startBase, stopAt: 4, arrival: .scorePending(rbiLine)))
            resolveHitStep()
            return
        }

        // Everything else just settles onto a base (the field animates the slide on its own). Lift him
        // off the base he was parked on for the prompt FIRST — `setRunner` only writes the destination,
        // so advancing him without this would leave a duplicate of him behind on his old bag.
        game.setRunner(nil, onBase: startBase)
        if advanced {
            game.setRunner(player, onBase: prompt.targetBase)   // took the extra base
            res.ahead = prompt.targetBase
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

    /// How long each base-to-base leg of a trot takes. Short enough to feel like running, long enough
    /// to read as touching each bag.
    static let baseLegDuration: Double = 0.32

    /// A runner trotting the bases: drawn at `leg` (-1 = home, 0/1/2 = bags, 3 = across the plate),
    /// stepped up to `stopAt`, then resolved by `arrival`.
    struct RunningRunner: Identifiable {
        let id: PersistentIdentifier
        let player: Player
        var leg: Int
        let stopAt: Int
        let arrival: Arrival

        /// What becomes of the runner once he reaches `stopAt`.
        enum Arrival {
            case stopOnBase(Int)                 // settle onto this base as a live runner
            case scorePending(GameStatLine?)     // credit a run (RBI → this line), then fade
            case fadeOnly                        // just fade — the caller already credited the run
            case hold                            // stay put on the field until the caller resolves him
        }

        var isHold: Bool { if case .hold = arrival { return true }; return false }
    }

    /// Kick off a trot: let the freshly-inserted travelers render at their START legs for one runloop
    /// tick, THEN begin stepping. Without this gap the insert and the first step collapse into one
    /// render and the chip pops onto the next bag instead of running to it.
    private func beginTravel(then finish: @escaping () -> Void) {
        DispatchQueue.main.async { driveTravelers(then: finish) }
    }

    /// Advance every traveler one leg (in parallel), pausing `baseLegDuration` between legs so the
    /// field's value-based animation slides each chip bag to bag, resolving any who reach their stop —
    /// until none remain, then run `finish`.
    private func driveTravelers(then finish: @escaping () -> Void) {
        guard travelers.contains(where: { $0.leg < $0.stopAt }) else {
            resolveArrivedTravelers()
            finish()
            return
        }
        for i in travelers.indices where travelers[i].leg < travelers[i].stopAt {
            travelers[i].leg += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.baseLegDuration) {
            resolveArrivedTravelers()
            driveTravelers(then: finish)
        }
    }

    /// Settle or score every traveler that has reached its stop, then drop them from the list. A
    /// `stopOnBase` runner hands off to a base chip of the same id (no blink); the rest fade. A `.hold`
    /// runner stays on the field (and in the list) until the caller resolves him — e.g. a play at the
    /// plate awaiting a Safe/Out call.
    private func resolveArrivedTravelers() {
        for t in travelers where t.leg >= t.stopAt {
            switch t.arrival {
            case .stopOnBase(let base):      game.setRunner(t.player, onBase: base)
            case .scorePending(let rbiLine): game.scorePendingRunner(t.player, rbiTo: rbiLine)
            case .fadeOnly, .hold:           break
            }
        }
        travelers.removeAll { $0.leg >= $0.stopAt && !$0.isHold }
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
                         battedOutType: draft.battedOutType,
                         batter: draft.batter,
                         pitcher: draft.pitcher,
                         detail: draft.strikeoutPitch ?? "",   // names the strikeout pitch, if tracked
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

    /// Snapshot the game, then run the mutating action — so Undo can revert it. The field's value-based
    /// animation slides the runners to their new bases (and fades out/scored players) on its own.
    private func perform(_ action: () -> Void) {
        pushUndo()
        game.lastPlayInheritedCharges = []   // per-play scratch; finishPlay reads what this play adds
        action()
        finishPlay()
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        // Remember where we were so Redo can come back, then roll the game AND its play log back — the
        // field animates the runners sliding home for free.
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
        if game.settings.challenges > 0 {
            Button { showChallengeTeamPicker = true } label: {
                Label("Challenge", systemImage: "hand.raised")
            }
            // A read-only recap: how many each team has left, and who challenged / when / the result.
            Button { showChallenges = true } label: {
                Label("View Challenges", systemImage: "flag.2.crossed")
            }
        }
        Divider()
        Button { showEditStats = true } label: {
            Label("Edit Stats & Score", systemImage: "pencil")
        }
        Button { showSummary = true } label: {
            Label("Game Summary", systemImage: "list.bullet.rectangle")
        }
        // A read-only glance at the rulebook this game is running under — not the editor.
        Button { showGameOptions = true } label: {
            Label("See Current Game Options", systemImage: "slider.horizontal.3")
        }
        Divider()
        // Step away without finishing — the game stays in progress and can be resumed later.
        Button { finishGameLater() } label: {
            Label("Finish Game Later", systemImage: "pause.circle")
        }
        Button(role: .destructive) { showEndConfirm = true } label: {
            Label("End Game", systemImage: "flag.checkered")
        }
    }

    /// Leave the game exactly as it is (still `.inProgress`) and go back where the user came from —
    /// the bracket for a tournament match, otherwise the main menu. Nothing is finalized, so it stays
    /// resumable (Exhibition's Resume button, or the Season / Tournament hubs).
    private func finishGameLater() {
        if let onExit {
            onExit()
        } else {
            router.returnToMainMenu()
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
        // Record who started, so the game-end Quality Start award knows the starters.
        game.markStartingPitchers()
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
    var battedOutType: BattedOutType? = nil
    let batter: Player?
    let pitcher: Player?
    let inning: Int
    let isTop: Bool
    let outs: Int
    /// The score before the play, so `finishPlay` can tell how many runs it drove in — a home run
    /// with runners aboard scores several, and the resolver scores them across separate prompts.
    let runsBefore: Int
    /// The pitch that ended a pitch-tracked strikeout (e.g. "Slider"), so the log can name it. nil for
    /// everything else.
    var strikeoutPitch: String? = nil
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

// A runner dragged from `fromBase` to `toBase` (3 = home), awaiting Safe/Out + a reason.
private struct PendingSteal: Identifiable {
    let id = UUID()
    let fromBase: Int
    let toBase: Int
}

// A batted out with its contact type + fielder chosen, awaiting the specific out kind.
private struct PendingOutType: Identifiable {
    let id = UUID()
    let type: BattedBallType
    let position: FieldPosition
    let options: [BattedOutType]
}

// A double play awaiting the "which runner was doubled off?" choice (multiple runners on base).
// A forced double play (2+ runners) waiting on the Safe/Out call on the lead runner. Holds who's
// involved (lead runner first) and the pre-play draft, so both outs (and any run) log as one play.
private struct ForcedDoublePlay {
    let batterLine: GameStatLine
    let runnersLeadFirst: [(base: Int, player: Player)]
    let draft: PlayDraft
}

// An "out at first" ground ball waiting on the Safe/Out call for a runner coming home from third.
// Holds the batter's line and the pre-play draft so the out (and any run) log as one play.
private struct OutAtFirstPlay {
    let batterLine: GameStatLine
    let draft: PlayDraft
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
    let pitcherChangeAlert: Binding<Bool>
    let pitcherChangeError: String?
    let onPitcherChosen: (Player) -> Void
    let onOverridePitcher: () -> Void

    /// Has the fielding team used all its All-Team-Pitch changes? (Only injury overrides remain.)
    private var pitcherChangeAtCap: Bool {
        game.settings.allTeamPitch && game.activePitcherSwaps >= Game.pitchingChangeCap
    }

    /// The pitching-change count shown in the Select Pitcher sheet — nil when All Team Pitch is off
    /// (no cap to report).
    private var pitcherChangeNote: String? {
        guard game.settings.allTeamPitch else { return nil }
        let used = game.activePitcherSwaps, cap = Game.pitchingChangeCap
        return used >= cap
            ? "\(used) of \(cap) pitching changes used — injury override only"
            : "Pitching changes: \(used) of \(cap) used"
    }

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
                           note: pitcherChangeNote,
                           noteIsWarning: pitcherChangeAtCap,
                           selectedPlayer: game.activePitcher) { line in
                    if let player = line.player { onPitcherChosen(player) }
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
                    game.finalize()   // awards pitching decisions, then the view switches to the Game Summary
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                endConfirmMessage
            }
            .alert("Game Over", isPresented: $showGameOver) {
                Button("End Game") { game.finalize() }
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

// MARK: - Steal reason dialog

/// The reason menu shown after a dragged runner's on-field Safe/Out call — the safe reasons (stolen
/// base, error…) or the out reasons (caught stealing, picked off…). The Safe/Out choice itself is on
/// the field now, so this is just the follow-up.
private struct StealReasonDialog: ViewModifier {
    let steal: PendingSteal?
    let isSafe: Bool?
    let baseLabel: (Int) -> String
    let onSafeReason: (SafeAdvanceReason) -> Void
    let onOutReason: (OutReason) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(reasonTitle, isPresented: shown, titleVisibility: .visible) {
            if isSafe == true {
                ForEach(SafeAdvanceReason.allCases, id: \.self) { reason in
                    Button(reason.label) { onSafeReason(reason) }
                }
            } else {
                ForEach(OutReason.allCases, id: \.self) { reason in
                    Button(reason.label) { onOutReason(reason) }
                }
            }
            Button("Cancel", role: .cancel) { onCancel() }
        }
    }

    /// Shown once the on-field Safe/Out is known (isSafe non-nil) for the dragged runner.
    private var shown: Binding<Bool> {
        Binding(get: { steal != nil && isSafe != nil }, set: { if !$0 { onCancel() } })
    }

    private var reasonTitle: String {
        guard let steal else { return "" }
        let base = baseLabel(steal.toBase)
        return isSafe == true
            ? "How did the runner take \(base)?"
            : "How did the runner get out at \(base)?"
    }
}

// MARK: - Out-type dialog

/// After a batted out's fielder is tapped: pick the specific out kind (Fly Out, Line Out (Foul)…).
/// Only presented when the contact type offers more than one option.
private struct OutTypeDialog: ViewModifier {
    let pending: PendingOutType?
    let onChoose: (BattedOutType) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("What kind of out?", isPresented: shown, titleVisibility: .visible) {
            if let pending {
                ForEach(pending.options, id: \.self) { out in
                    Button(out.label) { onChoose(out) }
                }
            }
            Button("Cancel", role: .cancel) { onCancel() }
        }
    }

    private var shown: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { onCancel() } })
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
    /// An extra line under the subtitle (e.g. the All-Team-Pitch change count). `noteIsWarning`
    /// colors it as a caution once the cap is reached.
    var note: String? = nil
    var noteIsWarning: Bool = false
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
                if let note {
                    Text(note)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(noteIsWarning ? .orange : .secondary)
                        .padding(.horizontal)
                        .padding(.top, subtitle == nil ? 8 : 3)
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
