//
//  Game+Live.swift
//  Blitzball Stat Tracker
//
//  The live-game "engine": who's batting/pitching, ghost-runner bases, and how a tapped outcome
//  updates the lines, the bases, and the scoreboard. Kept separate from the view. These just
//  mutate already-persisted model objects, so SwiftData saves them automatically. The tricky
//  base math lives in the tested `BaseRunning` helper.
//

import Foundation
import SwiftData   // ModelContext, for inserting play-log entries

extension Game {

    // MARK: - Who's batting / fielding right now

    /// Top of the inning = away bats; bottom = home bats.
    var battingIsHome: Bool { !isTopInning }

    var battingTeam: Team? { battingIsHome ? homeTeam : awayTeam }
    var fieldingTeam: Team? { battingIsHome ? awayTeam : homeTeam }

    /// Active players on a side, in batting order.
    /// The team's OWN active batters on a side (excludes the neutral DH), in batting order.
    func teamLineup(isHome: Bool) -> [GameStatLine] {
        statLines
            .filter { $0.isHome == isHome && $0.isActive && !$0.isDH }
            .sorted { $0.battingOrder < $1.battingOrder }
    }

    /// The full batting order for a side: the team's batters, plus the shared DH batting last.
    func lineup(isHome: Bool) -> [GameStatLine] {
        teamLineup(isHome: isHome) + statLines.filter { $0.isActive && $0.isDH }
    }

    var battingLineup: [GameStatLine] { lineup(isHome: battingIsHome) }

    /// The lineup index of the side currently at bat (each side keeps its own).
    var currentBatterIndex: Int {
        get { battingIsHome ? homeBatterIndex : awayBatterIndex }
        set { if battingIsHome { homeBatterIndex = newValue } else { awayBatterIndex = newValue } }
    }

    var currentBatterLine: GameStatLine? {
        let lineup = battingLineup
        guard !lineup.isEmpty else { return nil }
        return lineup[currentBatterIndex % lineup.count]
    }

    /// The batter who JUST completed their at-bat (the order has already advanced) — the most likely
    /// RBI recipient when you manually score a run.
    var previousBatterLine: GameStatLine? {
        let lineup = battingLineup
        guard !lineup.isEmpty else { return nil }
        let index = (currentBatterIndex - 1 + lineup.count) % lineup.count
        return lineup[index]
    }

    /// The batter due up right after the current one — the "on deck" hitter. Nil for a one-batter
    /// lineup (where he'd just be the current batter again).
    var onDeckBatterLine: GameStatLine? {
        let lineup = battingLineup
        guard lineup.count > 1 else { return nil }
        return lineup[(currentBatterIndex + 1) % lineup.count]
    }

    /// The ACTIVE pitcher is the fielding side's current pitcher.
    var activePitcher: Player? {
        get { battingIsHome ? awayPitcher : homePitcher }
        set { if battingIsHome { awayPitcher = newValue } else { homePitcher = newValue } }
    }

    var activePitcherLine: GameStatLine? {
        guard let pitcher = activePitcher else { return nil }
        // Match the fielding side's line, or the shared DH's line if the DH is pitching.
        return statLines.first { $0.player === pitcher && ($0.isDH || $0.isHome != battingIsHome) }
    }

    // MARK: - All-Team-Pitch (pitching-change rules)

    /// How many non-injury pitching changes each team gets under All-Team-Pitch. Injury overrides
    /// don't count against it.
    static let pitchingChangeCap = 2

    /// The fielding side's current-pitcher outs this stint.
    var activePitcherOuts: Int {
        get { battingIsHome ? awayPitcherOuts : homePitcherOuts }
        set { if battingIsHome { awayPitcherOuts = newValue } else { homePitcherOuts = newValue } }
    }

    /// The fielding side's pitching changes used (cap 2).
    var activePitcherSwaps: Int {
        get { battingIsHome ? awayPitchingSwaps : homePitchingSwaps }
        set { if battingIsHome { awayPitchingSwaps = newValue } else { homePitchingSwaps = newValue } }
    }

    /// Change the active (fielding) pitcher. With All-Team-Pitch on, requires the current pitcher
    /// to have >=1 out this stint and enforces the 2-swap cap — unless `override` (injury) is set.
    /// Returns an error message if blocked, or nil on success.
    func changePitcher(to newPlayer: Player, override: Bool) -> String? {
        guard settings.allTeamPitch else {
            activePitcher = newPlayer
            recordPitcherEntry(isHome: !battingIsHome)   // the fielding side's new pitcher enters
            return nil
        }
        guard newPlayer !== activePitcher else { return nil }
        if !override {
            if activePitcherOuts < 1 {
                return "Player needs a K or Out to swap out."
            }
            if activePitcherSwaps >= Game.pitchingChangeCap {
                return "This team has already used its \(Game.pitchingChangeCap) pitching changes. Use Override for an injury."
            }
        }
        activePitcher = newPlayer
        activePitcherOuts = 0
        if !override { activePitcherSwaps += 1 }
        recordPitcherEntry(isHome: !battingIsHome)       // the fielding side's new pitcher enters
        return nil
    }

    // MARK: - Force Pitcher Rotation

    /// A team's pitching rotation, in order (only the players the user added to the rotation).
    func pitchingRotation(isHome: Bool) -> [Player] {
        teamLineup(isHome: isHome)
            .filter { $0.pitchingOrder >= 0 }
            .sorted { $0.pitchingOrder < $1.pitchingOrder }
            .compactMap(\.player)
    }

    /// Who should be pitching for `isHome` this inning: the rotation entry for the current inning,
    /// looping after the last. nil if that team has no rotation set.
    func scheduledPitcher(isHome: Bool) -> Player? {
        let rotation = pitchingRotation(isHome: isHome)
        guard !rotation.isEmpty else { return nil }
        return rotation[(currentInning - 1) % rotation.count]
    }

    /// Install the fielding team's scheduled pitcher for the current half-inning (Force Pitcher
    /// Rotation only). Resets that side's stint outs since it's a fresh appearance.
    ///
    /// Respects manual overrides: if the current pitcher isn't the one the rotation put on the
    /// mound last time this side fielded (e.g. the user tapped Select Pitcher for an injury sub),
    /// we leave them in. Silently stomping a user-chosen reliever every half-inning would undo the
    /// override with no UI signal. Rotation resumes automatically the moment the user puts the
    /// scheduled pitcher back on the mound.
    func applyPitcherRotationIfNeeded() {
        guard settings.forcePitcherRotation else { return }
        let fieldingIsHome = isTopInning   // home takes the mound in the top half
        let rotation = pitchingRotation(isHome: fieldingIsHome)
        guard !rotation.isEmpty else { return }
        let next = rotation[(currentInning - 1) % rotation.count]
        let current = fieldingIsHome ? homePitcher : awayPitcher
        guard current !== next else { return }   // already on the scheduled pitcher

        // Only auto-advance when this side is still on-schedule: current is nil (no pitcher set
        // yet) OR current is the pitcher the rotation put in LAST time this side fielded.
        let previouslyScheduled: Player? = currentInning >= 2
            ? rotation[(currentInning - 2) % rotation.count]
            : nil
        guard current == nil || current === previouslyScheduled else { return }

        if fieldingIsHome { homePitcher = next; homePitcherOuts = 0 }
        else              { awayPitcher = next; awayPitcherOuts = 0 }
        recordPitcherEntry(isHome: fieldingIsHome)   // the rotation's next arm enters this half-inning
    }

    /// Seed both starting pitchers from the rotation at kickoff (Force Pitcher Rotation only).
    func syncStartingPitchersToRotation() {
        guard settings.forcePitcherRotation else { return }
        if let first = scheduledPitcher(isHome: true) { homePitcher = first }
        if let first = scheduledPitcher(isHome: false) { awayPitcher = first }
    }

    /// Team players (both sides, not the DH) who haven't pitched yet — for the End Game warning.
    func playersWhoHaventPitched() -> [Player] {
        guard settings.allTeamPitch else { return [] }
        var result: [Player] = []
        for line in statLines where !line.isDH {
            guard let player = line.player else { continue }
            let pitched = line.pitching != PitchingStats()
                || player === homePitcher || player === awayPitcher
            if !pitched { result.append(player) }
        }
        return result
    }

    // MARK: - Bases (index 0/1/2 = 1st/2nd/3rd)

    var bases: [Player?] { [runnerFirst, runnerSecond, runnerThird] }

    func runner(onBase index: Int) -> Player? {
        switch index {
        case 0: return runnerFirst
        case 1: return runnerSecond
        default: return runnerThird
        }
    }

    /// Score a runner who advanced home on a ghost-OFF hit (he's already been lifted off the bases
    /// by the resolver), optionally crediting the RBI to whoever just batted.
    func scorePendingRunner(_ player: Player, rbiTo rbiLine: GameStatLine?) {
        scoreRun(by: player)
        if let rbiLine { rbiLine.batting.rbi += 1 }
    }

    /// Manually place (or clear, with nil) a runner — the diamond editor's failsafe.
    func setRunner(_ player: Player?, onBase index: Int) {
        switch index {
        case 0: runnerFirst = player
        case 1: runnerSecond = player
        default: runnerThird = player
        }
        // A newly-placed runner goes on the current pitcher's tab; anyone already mapped keeps
        // their original pitcher, so re-placing runners mid-resolution doesn't lose responsibility.
        if player != nil { recordResponsibilityForNewRunners() }
    }

    private var runnerTokens: [Int?] {
        [runnerFirst != nil ? 0 : nil,
         runnerSecond != nil ? 1 : nil,
         runnerThird != nil ? 2 : nil]
    }

    // MARK: - Recording plays

    /// Record a plate-appearance outcome: updates the batter's and pitcher's lines, advances
    /// ghost runners (auto-scoring anyone who reaches home), tracks outs, and advances the order.
    ///
    /// - Parameter resolveBasesExternally: when true, skip all base movement/scoring here — the
    ///   caller (the live view's ghost-OFF hit flow) places runners station-to-station and prompts
    ///   "did they score?" for anyone reaching home. Stats, outs, and the batting order still update.
    func record(_ outcome: PlateAppearanceOutcome, resolveBasesExternally: Bool = false) {
        guard let batter = currentBatterLine, let batterPlayer = batter.player else { return }

        batter.batting.record(outcome)
        activePitcherLine?.pitching.recordAllowed(outcome)

        // Base movement + auto-scoring. Ghost runners ON ⇒ every runner is forced up by the hit;
        // OFF ⇒ we place the batter and force runners only when their base is needed (you advance
        // the discretionary ones by hand on the diamond). Walks/HBP force only as needed in both
        // modes. Raw counting stats above are recorded regardless.
        if !resolveBasesExternally {
        switch outcome {
        case .walk:
            applyAdvance(
                BaseRunning.advanceOnWalk(bases: runnerTokens, batter: 3),
                batter: batter, batterPlayer: batterPlayer
            )
        case .hitByPitch:
            // HBP only puts the batter on base (walk-style) when the HBP Walks rule is on.
            if settings.hbpWalks {
                applyAdvance(
                    BaseRunning.advanceOnWalk(bases: runnerTokens, batter: 3),
                    batter: batter, batterPlayer: batterPlayer
                )
            }
        case .out, .strikeout, .strikeoutLooking:
            break // runners hold
        case .sacrificeFly:
            // The runner on third tags and scores; the batter is out (tallied below) but is credited
            // the RBI. Other runners hold — nudge them on the diamond for the rare extra advance.
            scoreRunner(onBase: 2, rbiTo: batter)
        default:
            // Every outcome that puts the batter on base moves runners the same way, whether he got
            // there on a hit or on a misplay — `basesReached` is what differs, not the mechanics.
            if let baseCount = outcome.basesReached {
                let advance = settings.ghostRunners
                    ? BaseRunning.advanceOnHit(bases: runnerTokens, batter: 3, baseCount: baseCount)
                    : BaseRunning.advanceForcedHit(bases: runnerTokens, batter: 3, baseCount: baseCount)
                applyAdvance(advance, batter: batter, batterPlayer: batterPlayer)
                // A batter who reached only on an error scores an unearned run if he comes around
                // (rule 9.16) — remember him so creditRunToPitcher keeps that run off the pitcher's ERA.
                if outcome.batterReachedOnError { markReachedOnError(batterPlayer) }
            }
        }
        }

        // Charge the fielding team an error (the line score's E column).
        if outcome.chargesError {
            if battingIsHome { awayErrors += 1 } else { homeErrors += 1 }
        }

        if outcome.isOut {
            outs += 1
            // Credit the fielding pitcher's current stint (for the All-Team-Pitch swap rule).
            if battingIsHome { awayPitcherOuts += 1 } else { homePitcherOuts += 1 }
        }
        advanceBatter()
        // End by the innings rule (leave the state where it is so the view can show the Game Over
        // popup), or advance to the next half-inning.
        if outs >= settings.outsPerInning && !isComplete {
            advanceHalfInning()
        }
    }

    /// Move players per the base-advancement result, credit runs + RBI, and place survivors.
    private func applyAdvance(
        _ result: (bases: [Int?], scored: [Int]),
        batter: GameStatLine,
        batterPlayer: Player
    ) {
        // Resolve tokens BEFORE we overwrite the base relationships.
        let onFirst = runnerFirst, onSecond = runnerSecond, onThird = runnerThird
        func player(for token: Int) -> Player? {
            switch token {
            case 0: return onFirst
            case 1: return onSecond
            case 2: return onThird
            case 3: return batterPlayer
            default: return nil
            }
        }

        for token in result.scored {
            if let scorer = player(for: token) { scoreRun(by: scorer) }
        }
        batter.batting.rbi += result.scored.count

        runnerFirst  = result.bases[0].flatMap(player(for:))
        runnerSecond = result.bases[1].flatMap(player(for:))
        runnerThird  = result.bases[2].flatMap(player(for:))
        recordResponsibilityForNewRunners()
    }

    /// A dropped third strike where the batter reaches first: a strikeout is charged to the batter and
    /// the pitcher (an at-bat, a K), but NO out is made — the batter is safe at first, forcing any
    /// runners ahead exactly as a walk would. `wildPitch` only colors the play-log wording (wild pitch
    /// vs passed ball); the base mechanics are identical.
    func recordDroppedThirdStrike(wildPitch: Bool) {
        guard let batter = currentBatterLine, let batterPlayer = batter.player else { return }
        batter.batting.record(.strikeout)                     // K + at-bat for the batter
        activePitcherLine?.pitching.recordAllowed(.strikeout) // K + at-bat-against, but this also…
        activePitcherLine?.pitching.outsRecorded -= 1         // …counted an out that never happened — undo it
        if wildPitch { activePitcherLine?.pitching.wildPitches += 1 }   // charged a WP when the ball got away
        applyAdvance(BaseRunning.advanceOnWalk(bases: runnerTokens, batter: 3),
                     batter: batter, batterPlayer: batterPlayer)   // batter to first, force runners ahead
        advanceBatter()                                       // no out, so no half-inning check needed
    }

    /// A double play: the batter is out (an at-bat, no hit, like any out) and the runner on
    /// `secondOutBase` is doubled off. Two outs go on the board (charged to the pitcher), and it can
    /// end the half-inning. Other runners hold — nudge them on the diamond for the rare extra advance.
    func recordDoublePlay(secondOutBase: Int) {
        guard let batter = currentBatterLine else { return }
        batter.batting.record(.out)
        activePitcherLine?.pitching.recordAllowed(.out)   // the batter's out (outsRecorded += 1)

        setRunner(nil, onBase: secondOutBase)             // the runner is doubled off
        outs += 2
        activePitcherLine?.pitching.outsRecorded += 1     // the runner's out (batter's counted above)
        if battingIsHome { awayPitcherOuts += 2 } else { homePitcherOuts += 2 }

        advanceBatter()
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    /// The "outs" beat of a staged ground-ball double play, after the forced runner and batter have
    /// visibly advanced (the runner to `runnerBase`, the batter to `batterBase`). Records the batter's
    /// out, clears both, and puts the two outs on the board — able to end the half-inning.
    func finishGroundBallDoublePlay(batterLine: GameStatLine, runnerBase: Int, batterBase: Int) {
        batterLine.batting.record(.out)
        activePitcherLine?.pitching.recordAllowed(.out)   // the batter's out
        setRunner(nil, onBase: runnerBase)
        setRunner(nil, onBase: batterBase)
        outs += 2
        activePitcherLine?.pitching.outsRecorded += 1     // the runner's out (batter's counted above)
        if battingIsHome { awayPitcherOuts += 2 } else { homePitcherOuts += 2 }
        advanceBatter()
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    /// MLB rule 5.08(a): a run does NOT score when the play's inning-ending out is a force out or
    /// the batter-runner is retired before reaching first base. The multi-out finishers below make
    /// exactly those kinds of outs, so each asks this before crediting a forced/driven-in run —
    /// if the outs recorded on THIS play reach the inning limit, the run is voided. `outs` here is
    /// the count BEFORE this play's outs are applied.
    private func playMakesFinalOut(addingOuts n: Int) -> Bool {
        outs + n >= settings.outsPerInning
    }

    /// Resolve a forced double play once the trot has played out: the batter is out at first, and
    /// `runnersLeadFirst[outIndex]` (lead runner first, highest base) is the second out. Every other
    /// runner is credited one base — scoring if that base is home (index 3), no RBI since the batter hit
    /// into the play. So an out on the lead reaching home means no run; anyone else out lets the lead's
    /// run count. Two outs; can end the half-inning.
    func finishForcedDoublePlay(batterLine: GameStatLine,
                                runnersLeadFirst: [(base: Int, player: Player)],
                                outIndex: Int) {
        batterLine.batting.record(.out)                   // the batter, out at first
        activePitcherLine?.pitching.recordAllowed(.out)

        // Both outs (batter at first + a forced runner) are 5.08(a) exceptions, so if this DP is the
        // third out no forced runner's run counts.
        let voidsRun = playMakesFinalOut(addingOuts: 2)

        for r in runnersLeadFirst { setRunner(nil, onBase: r.base) }   // clear the starting bases

        for (i, r) in runnersLeadFirst.enumerated() where i != outIndex {
            let dest = r.base + 1
            if dest >= 3 {
                if !voidsRun { scoreRun(by: r.player) }   // 5.08(a): no run when the DP is the 3rd out
            } else {
                setRunner(r.player, onBase: dest)
            }
        }

        outs += 2
        activePitcherLine?.pitching.outsRecorded += 1     // the second out (the batter's is counted above)
        if battingIsHome { awayPitcherOuts += 2 } else { homePitcherOuts += 2 }
        advanceBatter()
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    /// A triple play: the batter and two forced runners are all out for three outs on one batted ball.
    /// Every runner is a force (first and second are occupied), so no run scores — a run never counts
    /// when the third out is a force out — and the bases clear. Charged to the pitcher; ends the
    /// half-inning under the standard three-out rule.
    func finishTriplePlay(batterLine: GameStatLine) {
        batterLine.batting.record(.out)                   // the batter, out at first
        activePitcherLine?.pitching.recordAllowed(.out)   // outsRecorded += 1 for the batter

        runnerFirst = nil; runnerSecond = nil; runnerThird = nil   // all forced out (or stranded, no run)

        outs += 3
        activePitcherLine?.pitching.outsRecorded += 2     // the two runners (the batter's is counted above)
        if battingIsHome { awayPitcherOuts += 3 } else { homePitcherOuts += 3 }
        advanceBatter()
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    /// An "out at first" ground ball: the batter is out at first (an at-bat, no hit) and every runner
    /// advances one base. A runner coming home from third is resolved by the caller's Safe/Out call:
    /// `runnerHomeSafe == true` scores him (RBI to the batter), `false` is a second out at the plate
    /// (no run), and `nil` means no runner was on third. Can end the half-inning.
    func finishOutAtFirst(batterLine: GameStatLine, runnerHomeSafe: Bool?) {
        batterLine.batting.record(.out)                   // the batter, out at first
        activePitcherLine?.pitching.recordAllowed(.out)   // outsRecorded += 1 for the batter

        // Resolve who's aboard BEFORE moving anyone, then clear and re-place one base up.
        let onFirst = runnerFirst, onSecond = runnerSecond, onThird = runnerThird
        runnerFirst = nil; runnerSecond = nil; runnerThird = nil

        // The batter is out at first; if that's the inning's third out, rule 5.08(a)(1) (batter-runner
        // retired before first base) voids any run on the play — even a runner who "beat the throw" home.
        let batterOutEndsInning = playMakesFinalOut(addingOuts: 1)

        var outsOnPlay = 1                                 // the batter
        if let third = onThird {
            if runnerHomeSafe == false {
                outsOnPlay += 1                            // thrown out at home
            } else if runnerHomeSafe == true && !batterOutEndsInning {
                scoreRun(by: third)                        // safe — the run counts, RBI to the batter
                batterLine.batting.rbi += 1
            }
        }
        if let second = onSecond { setRunner(second, onBase: 2) }   // 2nd → 3rd
        if let first = onFirst { setRunner(first, onBase: 1) }      // 1st → 2nd

        outs += outsOnPlay
        if outsOnPlay > 1 { activePitcherLine?.pitching.outsRecorded += 1 }   // the runner (batter's above)
        if battingIsHome { awayPitcherOuts += outsOnPlay } else { homePitcherOuts += outsOnPlay }
        advanceBatter()
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    private func scoreRun(by player: Player) {
        if let line = statLines.first(where: { $0.player === player && $0.isHome == battingIsHome }) {
            line.batting.runsScored += 1
        }
        creditRunToInning()
        creditRunToPitcher(for: player)
    }

    /// Record a fielder's choice: the batter reaches (an at-bat, no hit), the defense played on the
    /// runner at `playedOnBase`, and if `runnerOut` that runner is retired — a real out, charged to
    /// the pitcher and able to end the half-inning. The out is applied BEFORE the batter forces the
    /// rest, so a retired runner never occupies a base and trailing runners aren't forced by a runner
    /// who's gone. Anyone the batter forces past third scores (RBI to the batter).
    func recordFieldersChoice(_ outcome: PlateAppearanceOutcome, playedOnBase: Int?, runnerOut: Bool) {
        guard let batter = currentBatterLine, let batterPlayer = batter.player else { return }
        let baseCount = outcome.basesReached ?? 1

        batter.batting.record(outcome)
        activePitcherLine?.pitching.recordAllowed(outcome)

        // Remember who's on each base, then turn the diamond into runner tokens (0/1/2).
        let onBase = [runnerFirst, runnerSecond, runnerThird]
        var tokens: [Int?] = [runnerFirst != nil ? 0 : nil,
                              runnerSecond != nil ? 1 : nil,
                              runnerThird != nil ? 2 : nil]

        // The runner the defense retired is gone before the batter forces anyone.
        var forceOutEndsInning = false
        if runnerOut, let base = playedOnBase {
            tokens[base] = nil
            outs += 1
            activePitcherLine?.pitching.outsRecorded += 1
            if battingIsHome { awayPitcherOuts += 1 } else { homePitcherOuts += 1 }
            // The fielder's-choice out is a force out; if it's the third out, 5.08(a) voids any
            // run forced in on the play.
            forceOutEndsInning = outs >= settings.outsPerInning
        }

        let result = BaseRunning.advanceForcedHit(bases: tokens, batter: 3, baseCount: baseCount)
        func player(for token: Int) -> Player? {
            switch token {
            case 0, 1, 2: return onBase[token]
            case 3:       return batterPlayer
            default:      return nil
            }
        }
        if !forceOutEndsInning {
            for token in result.scored { if let scorer = player(for: token) { scoreRun(by: scorer) } }
            batter.batting.rbi += result.scored.count
        }
        runnerFirst  = result.bases[0].flatMap(player(for:))
        runnerSecond = result.bases[1].flatMap(player(for:))
        runnerThird  = result.bases[2].flatMap(player(for:))
        recordResponsibilityForNewRunners()

        advanceBatter()
        // End the half-inning if the fielder's-choice out was the last one.
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
    }

    // MARK: - Baserunning (drag to steal / advance)

    /// The batting-side stat line for a baserunner, used to credit a stolen base / caught stealing.
    private func battingLine(for player: Player) -> GameStatLine? {
        statLines.first { $0.player === player && $0.isHome == battingIsHome }
    }

    /// Spoken base name for a play-log line ("second", "home").
    private func spokenBase(_ index: Int) -> String {
        switch index {
        case 0:  return "first"
        case 1:  return "second"
        case 2:  return "third"
        default: return "home"
        }
    }

    /// A runner dragged to `toBase` and called SAFE. Moves him there — or scores him at home (a run,
    /// never an RBI) — and applies the reason's credit: a stolen base, or an error charged to the
    /// fielding team. Returns the play-log line. Assumes `toBase` is empty (or home); the drag UI
    /// only offers empty forward bases.
    @discardableResult
    func recordSafeAdvance(fromBase: Int, toBase: Int, reason: SafeAdvanceReason) -> String {
        guard let runner = runner(onBase: fromBase) else { return "" }
        setRunner(nil, onBase: fromBase)
        if toBase >= 3 {
            scoreRun(by: runner)          // steal of home / advance home — a run, never an RBI
        } else {
            setRunner(runner, onBase: toBase)
        }
        if reason.creditsStolenBase {
            battingLine(for: runner)?.batting.stolenBases += 1
            activePitcherLine?.pitching.stolenBasesAllowed += 1   // charged to the pitcher on the mound
        }
        if reason.chargesError {
            if battingIsHome { awayErrors += 1 } else { homeErrors += 1 }
        }
        return reason.logLine(runner: runner.name, base: spokenBase(toBase))
    }

    /// A runner dragged toward `toBase` and called OUT. Removes him and records the out — charged to
    /// the current pitcher, and able to end the half-inning — plus a caught stealing when that's the
    /// reason. `toBase` is only for the play-log line ("caught stealing at second"). Returns it.
    @discardableResult
    func recordBaserunningOut(fromBase: Int, toBase: Int, reason: OutReason) -> String {
        guard let runner = runner(onBase: fromBase) else { return "" }
        setRunner(nil, onBase: fromBase)
        if reason.creditsCaughtStealing {
            battingLine(for: runner)?.batting.caughtStealing += 1
            activePitcherLine?.pitching.caughtStealing += 1   // the battery's caught stealing
        }
        if reason.creditsPickedOff {
            battingLine(for: runner)?.batting.pickedOff += 1
            activePitcherLine?.pitching.pickoffs += 1
        }
        outs += 1
        activePitcherLine?.pitching.outsRecorded += 1
        if battingIsHome { awayPitcherOuts += 1 } else { homePitcherOuts += 1 }
        if outs >= settings.outsPerInning && !isComplete { advanceHalfInning() }
        return reason.logLine(runner: runner.name, base: spokenBase(toBase))
    }

    /// Manually score the runner on `baseIndex` (they advanced home on their own — e.g. from 1st on
    /// a triple with ghost runners off), optionally crediting an RBI to `rbiLine`. Clears that base.
    /// Powers the "Run" button; scoring + pitcher runs allowed are handled by `scoreRun`.
    func scoreRunner(onBase baseIndex: Int, rbiTo rbiLine: GameStatLine?) {
        guard let runnerPlayer = runner(onBase: baseIndex) else { return }
        scoreRun(by: runnerPlayer)
        setRunner(nil, onBase: baseIndex)
        if let rbiLine { rbiLine.batting.rbi += 1 }
    }

    private func advanceBatter() {
        let count = battingLineup.count
        guard count > 0 else { return }
        currentBatterIndex = (currentBatterIndex + 1) % count
    }

    private func creditRunToInning() {
        ensureInningSlots()
        let index = currentInning - 1
        if battingIsHome { homeInningRuns[index] += 1 } else { awayInningRuns[index] += 1 }
        checkBlownSaveOnRun()   // did that run just erase a save-able lead?
    }

    /// Charge a run to whoever is on the hook for THIS runner. A reliever is never charged for a
    /// runner he inherited (MLB 9.16) — the run goes to the pitcher who put that runner on base.
    /// Falls back to the current pitcher when the runner isn't mapped (he put them on himself).
    private func creditRunToPitcher(for runner: Player) {
        let responsibleName = runnerResponsibility[runner.name]
        let line = responsibleName.flatMap(pitcherLine(named:)) ?? activePitcherLine
        line?.pitching.runsAllowed += 1
        // A run is unearned when its runner reached base on an error (rule 9.16): it still counts
        // as a run allowed but not against ERA. Everything else defaults to earned.
        if reachedOnErrorRunners.contains(runner.name) {
            lastPlayUnearnedRuns += 1
        } else {
            line?.pitching.earnedRuns += 1
        }

        // Flag it for the live screen when the run went to someone other than the current pitcher.
        if let responsibleName, responsibleName != activePitcher?.name, line != nil {
            lastPlayInheritedCharges.append(
                InheritedCharge(runner: runner.name, chargedTo: responsibleName)
            )
        }
        // He's home — a later trip to the plate this inning starts fresh against whoever is pitching.
        clearResponsibility(for: runner)
        clearReachedOnError(for: runner)
    }

    /// The fielding side's stat line for a pitcher, by name (mirrors `activePitcherLine`'s matching).
    private func pitcherLine(named name: String) -> GameStatLine? {
        statLines.first { $0.player?.name == name && ($0.isDH || $0.isHome != battingIsHome) }
    }

    // MARK: - Play log

    /// The log in the order things happened.
    var orderedPlays: [PlayEvent] {
        plays.sorted { $0.sequence < $1.sequence }
    }

    /// Append one entry to the play-by-play log.
    ///
    /// Callers must pass the state as it was BEFORE the play was applied — recording a plate
    /// appearance advances the batter and can roll the half-inning over, so reading `currentInning`
    /// or `currentBatterLine` afterwards describes the NEXT play, not the one being logged.
    @discardableResult
    func logPlay(
        _ kind: PlayEventKind,
        outcome: PlateAppearanceOutcome? = nil,
        battedBallType: BattedBallType? = nil,
        fieldPosition: FieldPosition? = nil,
        battedOutType: BattedOutType? = nil,
        batter: Player? = nil,
        pitcher: Player? = nil,
        detail: String = "",
        runsScored: Int = 0,
        unearnedRuns: Int = 0,
        inning: Int? = nil,
        isTop: Bool? = nil,
        outs: Int? = nil,
        context: ModelContext? = nil
    ) -> PlayEvent {
        let event = PlayEvent(
            game: self,
            sequence: (plays.map(\.sequence).max() ?? -1) + 1,
            kind: kind,
            inning: inning ?? currentInning,
            isTopInning: isTop ?? isTopInning,
            outsBefore: outs ?? self.outs,
            outcome: outcome,
            battedBallType: battedBallType,
            fieldPosition: fieldPosition,
            battedOutType: battedOutType,
            batter: batter,
            pitcher: pitcher,
            detail: detail,
            runsScored: runsScored,
            // The running score as of right now — this is called after the play was applied.
            homeScore: homeScore,
            awayScore: awayScore
        )
        event.unearnedRuns = min(unearnedRuns, runsScored)   // can't be more unearned than scored
        context?.insert(event)
        plays.append(event)
        return event
    }

    // MARK: - Inherited runners

    /// Put every runner now standing on a base on some pitcher's tab. Anyone already mapped keeps
    /// their original pitcher — that's the whole point, responsibility follows the RUNNER, not the
    /// base — so this is safe to call after any base change, including the ghost-runners-off
    /// resolver that briefly lifts everyone off the diamond.
    func recordResponsibilityForNewRunners() {
        guard let pitcherName = activePitcher?.name else { return }
        var map = runnerResponsibility
        var changed = false
        for base in 0..<3 {
            guard let runner = runner(onBase: base), map[runner.name] == nil else { continue }
            map[runner.name] = pitcherName
            changed = true
        }
        if changed { runnerResponsibility = map }
    }

    /// Override an inherited-run charge: move its R+ER off the pitcher who was billed and onto the
    /// pitcher currently on the mound. Used by the "charge to current pitcher instead" prompt.
    func reassignInheritedCharge(_ charge: InheritedCharge) {
        guard let from = pitcherLine(named: charge.chargedTo),
              let to = activePitcherLine, from !== to else { return }
        from.pitching.runsAllowed = max(0, from.pitching.runsAllowed - 1)
        from.pitching.earnedRuns = max(0, from.pitching.earnedRuns - 1)
        to.pitching.runsAllowed += 1
        to.pitching.earnedRuns += 1
    }

    /// Hand a runner's tab to someone else — used when a pinch runner takes over the base.
    func transferResponsibility(from old: Player, to new: Player) {
        var map = runnerResponsibility
        if let pitcherName = map.removeValue(forKey: old.name) {
            map[new.name] = pitcherName
            runnerResponsibility = map
        }
        // A pinch runner inherits the reached-on-error status too — the run stays unearned.
        var errored = reachedOnErrorRunners
        if errored.remove(old.name) != nil {
            errored.insert(new.name)
            reachedOnErrorRunners = errored
        }
    }

    private func clearResponsibility(for runner: Player) {
        var map = runnerResponsibility
        guard map.removeValue(forKey: runner.name) != nil else { return }
        runnerResponsibility = map
    }

    /// Remember a runner reached base on an error — a run he scores is unearned (rule 9.16).
    private func markReachedOnError(_ player: Player) {
        var set = reachedOnErrorRunners
        if set.insert(player.name).inserted { reachedOnErrorRunners = set }
    }

    private func clearReachedOnError(for player: Player) {
        var set = reachedOnErrorRunners
        if set.remove(player.name) != nil { reachedOnErrorRunners = set }
    }

    // MARK: - Innings

    /// Move to the next half-inning: clear outs and the bases, flip top/bottom, bump inning after a bottom.
    func advanceHalfInning() {
        outs = 0
        runnerFirst = nil
        runnerSecond = nil
        runnerThird = nil
        // Nobody is left on base, so no pitcher is on the hook for anyone and no reached-on-error
        // runners remain to carry an unearned run into the next inning.
        runnerResponsibility = [:]
        reachedOnErrorRunners = []
        if isTopInning {
            isTopInning = false
        } else {
            isTopInning = true
            currentInning += 1
        }
        ensureInningSlots()
        // The new fielding team sends in their scheduled pitcher (no-op unless the option is on).
        applyPitcherRotationIfNeeded()
    }

    /// Make sure both per-inning run arrays have a slot for the current inning.
    func ensureInningSlots() {
        while awayInningRuns.count < currentInning { awayInningRuns.append(0) }
        while homeInningRuns.count < currentInning { homeInningRuns.append(0) }
    }

    // MARK: - Scoreboard helpers

    /// Total hits by a side (for the line score's H column), summed from that side's lines.
    func hits(isHome: Bool) -> Int {
        statLines.filter { !$0.isDH && $0.isHome == isHome }.reduce(0) { $0 + $1.batting.hits }
    }

    /// The half-inning label, e.g. "Top 3" / "Bot 5".
    var halfInningLabel: String {
        "\(isTopInning ? "Top" : "Bot") \(currentInning)"
    }

    /// Whether the game is finished by the Innings rule, given the current score/inning/outs.
    /// Checked by the live view after each play to show the Game Over popup. Cases:
    /// - **Walk-off / home ahead** in the bottom of the final-or-later inning → over immediately.
    /// - **Top of final+ inning done** and home already leads → over (home doesn't bat the bottom).
    /// - **Bottom of final+ inning done**: someone leads → over; tied → over only if Extra Innings
    ///   is off (a tie), otherwise play on.
    var isComplete: Bool {
        let final = settings.innings
        guard currentInning >= final else { return false }

        // Home ahead in the bottom half of a final-or-later inning ends it the instant it happens.
        if !isTopInning && homeScore > awayScore { return true }

        // The remaining cases only trigger once the current half-inning is complete.
        guard outs >= settings.outsPerInning else { return false }

        if isTopInning {
            // Away just finished the top of the final+ inning; home skips the bottom if already up.
            return homeScore > awayScore
        } else {
            // Home just finished the bottom of the final+ inning.
            if homeScore != awayScore { return true }   // decided
            return !settings.extraInnings               // tie ends the game only without extras
        }
    }
}
