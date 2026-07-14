//
//  Player+Career.swift
//  Blitzball Stat Tracker
//
//  A player's career stats are DERIVED, not stored: sum the batting/pitching lines from their
//  finished games. Because it's computed, correcting or deleting a game automatically fixes a
//  player's career totals everywhere they're shown.
//

import Foundation

extension Player {
    /// Only completed games count toward career totals.
    var finalStatLines: [GameStatLine] {
        gameStatLines.filter { $0.game?.status == .final }
    }

    var careerBatting: BattingStats {
        finalStatLines.reduce(BattingStats()) { $0 + $1.batting }
    }

    var careerPitching: PitchingStats {
        finalStatLines.reduce(PitchingStats()) { $0 + $1.pitching }
    }
}
