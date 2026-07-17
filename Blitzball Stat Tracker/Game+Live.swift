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
        guard settings.allTeamPitch else { activePitcher = newPlayer; return nil }
        guard newPlayer !== activePitcher else { return nil }
        if !override {
            if activePitcherOuts < 1 {
                return "Player needs a K or Out to swap out."
            }
            if activePitcherSwaps >= 2 {
                return "This team has already used its 2 pitching changes. Use Override for an injury."
            }
        }
        activePitcher = newPlayer
        activePitcherOuts = 0
        if !override { activePitcherSwaps += 1 }
        return nil
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
        case .single, .double, .triple, .homeRun:
            let baseCount: Int
            switch outcome {
            case .single: baseCount = 1
            case .double: baseCount = 2
            case .triple: baseCount = 3
            default:      baseCount = 4
            }
            let advance = settings.ghostRunners
                ? BaseRunning.advanceOnHit(bases: runnerTokens, batter: 3, baseCount: baseCount)
                : BaseRunning.advanceForcedHit(bases: runnerTokens, batter: 3, baseCount: baseCount)
            applyAdvance(advance, batter: batter, batterPlayer: batterPlayer)
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
        }
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
    }

    private func scoreRun(by player: Player) {
        if let line = statLines.first(where: { $0.player === player && $0.isHome == battingIsHome }) {
            line.batting.runsScored += 1
        }
        creditRunToInning()
        creditRunToPitcher()
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
    }

    private func creditRunToPitcher() {
        activePitcherLine?.pitching.runsAllowed += 1
        activePitcherLine?.pitching.earnedRuns += 1
    }

    // MARK: - Innings

    /// Move to the next half-inning: clear outs and the bases, flip top/bottom, bump inning after a bottom.
    func advanceHalfInning() {
        outs = 0
        runnerFirst = nil
        runnerSecond = nil
        runnerThird = nil
        if isTopInning {
            isTopInning = false
        } else {
            isTopInning = true
            currentInning += 1
        }
        ensureInningSlots()
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
