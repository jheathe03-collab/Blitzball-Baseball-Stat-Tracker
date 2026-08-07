//
//  Game+PitchingDecisions.swift
//  Blitzball Stat Tracker
//
//  End-of-game pitching decisions. Tier 2 = Quality Starts, awarded automatically when the game is
//  finalized: the STARTING pitcher on a side earns one for going deep enough (scaled to the game's
//  length) while allowing no more than three earned runs. Saves and Blown Saves follow in a later tier.
//

import Foundation

extension Game {

    /// Earned-run ceiling for a Quality Start — the classic three, regardless of game length. (The
    /// innings bar scales instead; see `GameSettings.qualityStartOutsThreshold`.)
    static let qualityStartMaxEarnedRuns = 3

    /// The largest lead that still counts as a "save situation" when a reliever enters. MLB uses 3;
    /// widened to 5 for blitzball's higher scoring (an unofficial but reasonable indicator).
    static let saveLeadWindow = 5

    /// Outs that make a "long save" on their own — three innings, regardless of the lead at entry.
    static let longSaveOuts = 9

    /// The GameStatLine for a side's pitcher (the shared DH's line if the DH is pitching, otherwise
    /// that side's own line).
    func pitchingLine(for player: Player?, isHome: Bool) -> GameStatLine? {
        guard let player else { return nil }
        return statLines.first { $0.player === player && ($0.isDH || $0.isHome == isHome) }
    }

    /// Mark each side's current pitcher as its starter — called once at first pitch, so the game-end
    /// Quality Start award knows who started (only a starter can earn one). Also seeds each side's
    /// save-entry context (a 0-0 game start is never a save situation, which is exactly right).
    func markStartingPitchers() {
        pitchingLine(for: homePitcher, isHome: true)?.isStarter = true
        pitchingLine(for: awayPitcher, isHome: false)?.isStarter = true
        recordPitcherEntry(isHome: true)
        recordPitcherEntry(isHome: false)
    }

    // MARK: - Save situation context

    /// Capture a side's save context the moment its pitcher takes the mound: the lead his team holds
    /// now and the outs already on his line (so a later "innings this stint" measures from here). Called
    /// on every entry — the starter, a manual change, and an auto-rotation change.
    func recordPitcherEntry(isHome: Bool) {
        let lead = (isHome ? homeScore : awayScore) - (isHome ? awayScore : homeScore)
        let outs = pitchingLine(for: isHome ? homePitcher : awayPitcher, isHome: isHome)?
            .pitching.outsRecorded ?? 0
        if isHome {
            homeSaveEntryLead = lead; homeSaveEntryOuts = outs; homeBlownSaveCharged = false
        } else {
            awaySaveEntryLead = lead; awaySaveEntryOuts = outs; awayBlownSaveCharged = false
        }
    }

    /// True if that side's pitcher entered protecting a save-able lead (1…`saveLeadWindow`).
    private func enteredInSaveSituation(isHome: Bool) -> Bool {
        (1...Self.saveLeadWindow).contains(isHome ? homeSaveEntryLead : awaySaveEntryLead)
    }

    // MARK: - Blown save (live, as the batting team scores)

    /// Called right after the batting team plates a run. If that run just erased the fielding side's
    /// lead (down to a tie) and their pitcher had entered in a save situation, charge him a blown save
    /// — once per stint. It lives on his pitching line, so an Undo of the run takes it back for free.
    func checkBlownSaveOnRun() {
        let fieldingIsHome = !battingIsHome
        let fieldingLead = (fieldingIsHome ? homeScore : awayScore)
            - (fieldingIsHome ? awayScore : homeScore)
        guard fieldingLead == 0 else { return }               // the tying run just crossed
        guard enteredInSaveSituation(isHome: fieldingIsHome) else { return }
        let alreadyCharged = fieldingIsHome ? homeBlownSaveCharged : awayBlownSaveCharged
        guard !alreadyCharged else { return }
        guard let line = pitchingLine(for: fieldingIsHome ? homePitcher : awayPitcher,
                                      isHome: fieldingIsHome), !line.isStarter else { return }
        line.pitching.blownSaves += 1
        if fieldingIsHome { homeBlownSaveCharged = true } else { awayBlownSaveCharged = true }
    }

    /// Credit a Quality Start to any starter who went at least `qualityStartOutsThreshold` outs while
    /// allowing at most three earned runs. Idempotent via the caller's `finalize()` guard.
    func awardQualityStarts() {
        let threshold = settings.qualityStartOutsThreshold
        for line in statLines where line.isStarter {
            if line.pitching.outsRecorded >= threshold
                && line.pitching.earnedRuns <= Self.qualityStartMaxEarnedRuns {
                line.pitching.qualityStarts += 1
            }
        }
    }

    // MARK: - Save (at game end)

    /// Credit a save to the finishing pitcher of the winning team, when he qualifies: not the starter,
    /// he never blew the lead after entering, and he either entered in a save situation (1…window lead)
    /// or threw a long save (≥3 innings this stint). The finisher is the FIELDING side of the last
    /// half-inning — so a walk-off (the batting team wins) correctly yields no save.
    func awardSaves() {
        guard homeScore != awayScore else { return }          // must be decided
        let finisherIsHome = !battingIsHome                    // whoever was fielding when it ended
        let finisherWon = finisherIsHome ? homeScore > awayScore : awayScore > homeScore
        guard finisherWon else { return }                      // no save in a walk-off loss
        guard let line = pitchingLine(for: finisherIsHome ? homePitcher : awayPitcher,
                                      isHome: finisherIsHome), !line.isStarter else { return }
        // He can't have blown the lead on this outing and still earn the save.
        let blown = finisherIsHome ? homeBlownSaveCharged : awayBlownSaveCharged
        guard !blown else { return }

        let entryOuts = finisherIsHome ? homeSaveEntryOuts : awaySaveEntryOuts
        let stintOuts = line.pitching.outsRecorded - entryOuts
        let longSave = stintOuts >= Self.longSaveOuts
        guard enteredInSaveSituation(isHome: finisherIsHome) || longSave else { return }
        line.pitching.saves += 1
    }

    /// End the game: award end-of-game pitching decisions exactly once, then mark it final. Both
    /// "End Game" buttons route through here instead of setting `status` directly.
    func finalize() {
        if !pitchingDecisionsRecorded {
            awardQualityStarts()
            awardSaves()
            pitchingDecisionsRecorded = true
        }
        status = .final
    }
}
