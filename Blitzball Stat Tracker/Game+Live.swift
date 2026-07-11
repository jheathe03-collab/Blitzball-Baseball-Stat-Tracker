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
    func lineup(isHome: Bool) -> [GameStatLine] {
        statLines
            .filter { $0.isHome == isHome && $0.isActive }
            .sorted { $0.battingOrder < $1.battingOrder }
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

    /// The ACTIVE pitcher is the fielding side's current pitcher.
    var activePitcher: Player? {
        get { battingIsHome ? awayPitcher : homePitcher }
        set { if battingIsHome { awayPitcher = newValue } else { homePitcher = newValue } }
    }

    var activePitcherLine: GameStatLine? {
        guard let pitcher = activePitcher else { return nil }
        return statLines.first { $0.player === pitcher && $0.isHome != battingIsHome }
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
    func record(_ outcome: PlateAppearanceOutcome) {
        guard let batter = currentBatterLine, let batterPlayer = batter.player else { return }

        batter.batting.record(outcome)
        activePitcherLine?.pitching.recordAllowed(outcome)

        // Base movement + auto-scoring is the GHOST RUNNERS rule set — only applied when that
        // Game Option is on. (Non-ghost base logic will be built later.) The raw counting stats
        // above are always recorded either way.
        if settings.ghostRunners {
            switch outcome {
            case .single, .double, .triple, .homeRun:
                let baseCount: Int
                switch outcome {
                case .single: baseCount = 1
                case .double: baseCount = 2
                case .triple: baseCount = 3
                default:      baseCount = 4
                }
                applyAdvance(
                    BaseRunning.advanceOnHit(bases: runnerTokens, batter: 3, baseCount: baseCount),
                    batter: batter, batterPlayer: batterPlayer
                )
            case .walk:
                applyAdvance(
                    BaseRunning.advanceOnWalk(bases: runnerTokens, batter: 3),
                    batter: batter, batterPlayer: batterPlayer
                )
            case .hitByPitch:
                // HBP only puts the batter on base (walk-style) when the HBP Walks rule is on.
                // Blitzball default: off — no free base on a hit-by-pitch.
                if settings.hbpWalks {
                    applyAdvance(
                        BaseRunning.advanceOnWalk(bases: runnerTokens, batter: 3),
                        batter: batter, batterPlayer: batterPlayer
                    )
                }
            case .out, .strikeout:
                break // runners hold
            }
        }

        if outcome.isOut { outs += 1 }
        advanceBatter()
        if outs >= 3 { advanceHalfInning() }
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
        statLines.filter { $0.isHome == isHome }.reduce(0) { $0 + $1.batting.hits }
    }

    /// The half-inning label, e.g. "Top 3" / "Bot 5".
    var halfInningLabel: String {
        "\(isTopInning ? "Top" : "Bot") \(currentInning)"
    }
}
