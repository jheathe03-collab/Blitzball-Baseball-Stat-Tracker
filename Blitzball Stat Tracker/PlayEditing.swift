//
//  PlayEditing.swift
//  Blitzball Stat Tracker
//
//  Correcting a play that's already been recorded: re-score the result, move it to a different
//  batter or pitcher, or mark its runs unearned.
//
//  The trick that makes this exact is that a play's stat deltas are a PURE FUNCTION of its outcome
//  — `BattingStats.record(_:)` applied to a zero line IS the delta. So nothing has to be stored
//  when a play happens: editing simply unapplies the old outcome's deltas and applies the new
//  one's. That also means an edit is perfectly reversible, and re-editing a play compounds
//  correctly instead of drifting.
//
//  What editing deliberately does NOT touch:
//   • Runners and runs — every re-scoring option leaves the batter on the base he already reached,
//     so there is nothing to move. (Out → Reached on Error is the one case where the batter should
//     now be on base; place him yourself on the diamond.)
//   • RBIs and runs scored, which are recorded separately from the outcome. Whether a run that
//     scored on a misplay counts as an RBI is a scorer's judgment call, so we leave it alone.
//

import Foundation
import SwiftData

extension Game {

    // MARK: - Deltas

    /// The batting credit an outcome is worth, as a standalone line.
    static func battingDelta(for outcome: PlateAppearanceOutcome) -> BattingStats {
        var stats = BattingStats()
        stats.record(outcome)
        return stats
    }

    /// The pitching credit an outcome is worth, as a standalone line.
    static func pitchingDelta(for outcome: PlateAppearanceOutcome) -> PitchingStats {
        var stats = PitchingStats()
        stats.recordAllowed(outcome)
        return stats
    }

    // MARK: - Finding the lines a play belongs to

    /// The stat line a play's batter is on. A play knows which half-inning it happened in, so we
    /// know which side was batting even if the game has moved on since.
    func batterLine(for play: PlayEvent) -> GameStatLine? {
        guard let player = play.batter else { return nil }
        let battingIsHome = !play.isTopInning
        return statLines.first { $0.player === player && $0.isHome == battingIsHome && !$0.isDH }
            ?? statLines.first { $0.player === player }
    }

    /// The stat line a play's pitcher is on — the fielding side, or the shared DH.
    func pitcherLine(for play: PlayEvent) -> GameStatLine? {
        guard let player = play.pitcher else { return nil }
        let battingIsHome = !play.isTopInning
        return statLines.first { $0.player === player && ($0.isDH || $0.isHome != battingIsHome) }
            ?? statLines.first { $0.player === player }
    }

    // MARK: - Re-scoring

    /// Re-score a play. Moves the batter's and pitcher's credit from the old outcome to the new one
    /// and adjusts the fielding team's error count.
    func reclassify(_ play: PlayEvent, to newOutcome: PlateAppearanceOutcome) {
        guard let old = play.outcome, old != newOutcome else { return }

        batterLine(for: play)?.batting.applyChange(from: Game.battingDelta(for: old),
                                                   to: Game.battingDelta(for: newOutcome))
        pitcherLine(for: play)?.pitching.applyChange(from: Game.pitchingDelta(for: old),
                                                     to: Game.pitchingDelta(for: newOutcome))
        adjustErrors(for: play, from: old, to: newOutcome)
        adjustLiveOuts(for: play, from: old, to: newOutcome)
        play.outcome = newOutcome
    }

    /// Charge or refund the fielding team's error. Which side fielded is fixed by the half-inning
    /// the play happened in, not by whoever is batting now.
    private func adjustErrors(for play: PlayEvent,
                              from old: PlateAppearanceOutcome,
                              to new: PlateAppearanceOutcome) {
        let delta = (new.chargesError ? 1 : 0) - (old.chargesError ? 1 : 0)
        guard delta != 0 else { return }
        let fieldingIsHome = play.isTopInning
        if fieldingIsHome {
            homeErrors = max(0, homeErrors + delta)
        } else {
            awayErrors = max(0, awayErrors + delta)
        }
    }

    /// If the play being re-scored is in the half-inning currently being played, keep the live out
    /// count honest — turning an out into "reached on error" should give the inning its out back.
    /// Plays from earlier innings are left alone: their outs are long since reset.
    private func adjustLiveOuts(for play: PlayEvent,
                                from old: PlateAppearanceOutcome,
                                to new: PlateAppearanceOutcome) {
        guard status == .inProgress,
              play.inning == currentInning,
              play.isTopInning == isTopInning else { return }
        let delta = (new.isOut ? 1 : 0) - (old.isOut ? 1 : 0)
        guard delta != 0 else { return }
        outs = max(0, outs + delta)
    }

    // MARK: - Reassigning who it belongs to

    /// Move a play's batting credit to a different batter (a mis-tapped spot in the order).
    func reassignBatter(_ play: PlayEvent, to player: Player) {
        guard let outcome = play.outcome, play.batter !== player else { return }
        let delta = Game.battingDelta(for: outcome)
        batterLine(for: play)?.batting -= delta
        play.batter = player
        batterLine(for: play)?.batting += delta
    }

    /// Move a play's pitching credit to a different pitcher.
    func reassignPitcher(_ play: PlayEvent, to player: Player) {
        guard let outcome = play.outcome, play.pitcher !== player else { return }
        let delta = Game.pitchingDelta(for: outcome)
        pitcherLine(for: play)?.pitching -= delta
        play.pitcher = player
        pitcherLine(for: play)?.pitching += delta
    }

    // MARK: - Earned vs unearned

    /// Mark this play's runs earned or unearned. Unearned runs still count as runs allowed — they
    /// just stop counting against the pitcher's ERA, which is the whole point of the distinction.
    ///
    /// The adjustment lands on the pitcher recorded for the play. If an inherited runner scored,
    /// the run may have been charged to a different pitcher; reassign the play's pitcher first, or
    /// fix it in Edit Stats.
    func setRunsUnearned(_ play: PlayEvent, unearned: Bool) {
        let target = unearned ? play.runsScored : 0
        let delta = target - play.unearnedRuns
        guard delta != 0, let line = pitcherLine(for: play) else { return }
        line.pitching.earnedRuns = max(0, line.pitching.earnedRuns - delta)
        play.unearnedRuns = target
    }
}

// MARK: - Applying a change to a line

private extension BattingStats {
    /// Swap one play's credit for another's, in place.
    mutating func applyChange(from old: BattingStats, to new: BattingStats) {
        self = self - old + new
    }
    static func -= (lhs: inout BattingStats, rhs: BattingStats) { lhs = lhs - rhs }
    static func += (lhs: inout BattingStats, rhs: BattingStats) { lhs = lhs + rhs }
}

private extension PitchingStats {
    mutating func applyChange(from old: PitchingStats, to new: PitchingStats) {
        self = self - old + new
    }
    static func -= (lhs: inout PitchingStats, rhs: PitchingStats) { lhs = lhs - rhs }
    static func += (lhs: inout PitchingStats, rhs: PitchingStats) { lhs = lhs + rhs }
}
