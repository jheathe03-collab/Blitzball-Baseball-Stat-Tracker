//
//  Game+Lineup.swift
//  Blitzball Stat Tracker
//
//  Building a team's lineup (its GameStatLines) during setup, so the batting order can be edited
//  before the game starts. Kept in sync with the selected team's roster.
//

import Foundation
import SwiftData

extension Game {
    /// Make this side's stat lines match the selected team's roster:
    /// - keep existing lines (and their batting order),
    /// - append any new roster players (in name order),
    /// - drop lines for players no longer on the team.
    /// Called by the Batting Order editor and at game start.
    func syncLineup(isHome: Bool, using context: ModelContext) {
        let roster = (isHome ? homeTeam?.players : awayTeam?.players) ?? []
        // Exclude the neutral DH line — it's managed only by syncDesignatedHitter(), not here.
        let sideLines = statLines.filter { $0.isHome == isHome && !$0.isDH }

        // Drop lines whose player is no longer on the roster.
        let stale = sideLines.filter { line in
            guard let player = line.player else { return true }
            return !roster.contains { $0 === player }
        }
        for line in stale { context.delete(line) }

        let survivors = sideLines.filter { line in !stale.contains(where: { $0 === line }) }
        let covered = survivors.compactMap { $0.player }
        var nextOrder = (survivors.map { $0.battingOrder }.max() ?? -1) + 1

        // Add lines for roster players who don't have one yet, appended after existing ones.
        let newPlayers = roster
            .filter { player in !covered.contains { $0 === player } }
            .sorted { $0.name < $1.name }
        for player in newPlayers {
            let line = GameStatLine(player: player, isHome: isHome, battingOrder: nextOrder, isActive: true)
            line.game = self
            context.insert(line)
            nextOrder += 1
        }
    }

    /// Ensure the neutral Designated Hitter's shared line exists (and matches the chosen player)
    /// when the DH option is on — or remove it otherwise.
    func syncDesignatedHitter(using context: ModelContext) {
        let existing = statLines.filter { $0.isDH }

        guard settings.designatedHitter, let dhPlayer = designatedHitter else {
            for line in existing { context.delete(line) }   // option off or nobody picked
            return
        }

        // Drop DH lines for a previously-chosen player.
        for line in existing where line.player !== dhPlayer {
            context.delete(line)
        }
        // Create the DH line if it doesn't exist yet. battingOrder is a large sentinel so it
        // sorts last, though the live lineup appends it explicitly anyway.
        if !existing.contains(where: { $0.player === dhPlayer }) {
            let line = GameStatLine(player: dhPlayer, isHome: false, battingOrder: 9_999,
                                    isActive: true, isDH: true)
            line.game = self
            context.insert(line)
        }
    }
}
