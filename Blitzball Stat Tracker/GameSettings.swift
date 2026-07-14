//
//  GameSettings.swift
//  Blitzball Stat Tracker
//
//  The rulebook for a game: how many innings, strikes/balls, ghost runners, etc. Stored on a
//  Game (as a Codable struct, like BattingStats on Player). For now these are just saved; the
//  Start Game / live-tracking phase will act on them.
//

import Foundation

/// The label shown for a game's rules. `blitzball` / `baseball` mean "matches that preset
/// exactly"; `custom` means the user has tweaked something away from either preset.
enum GameType: String, Codable, CaseIterable {
    case blitzball
    case baseball
    case custom

    var displayName: String {
        switch self {
        case .blitzball: return "Blitzball"
        case .baseball:  return "Baseball"
        case .custom:    return "Custom"
        }
    }
}

/// The full set of tunable rules for a game. Note there's no stored "gameType" — we DERIVE it
/// (`matchedType`) by comparing the values to the presets, so any manual edit becomes "Custom"
/// automatically with no extra bookkeeping.
struct GameSettings: Codable, Hashable, Sendable {
    var innings: Int          // 1...9
    var extraInnings: Bool
    var substitutions: Bool
    var allTeamPitch: Bool
    var maxStrikes: Int       // 1...10
    var maxBalls: Int         // 1...10
    var ghostRunners: Bool
    /// Does a hit-by-pitch put the batter on base (walk-style)? Off by default in blitzball.
    var hbpWalks: Bool
    var challenges: Int       // 0...3
    /// A neutral shared player who bats for both teams (for odd rosters). Off by default; opt-in.
    var designatedHitter: Bool

    // Allowed ranges, kept next to the data so the UI steppers can reuse them.
    static let inningsRange = 1...9
    static let strikesRange = 1...10
    static let ballsRange = 1...10
    static let challengesRange = 0...3

    // The two presets (from James's mockup).
    static let blitzballDefaults = GameSettings(
        innings: 7, extraInnings: true, substitutions: true, allTeamPitch: true,
        maxStrikes: 3, maxBalls: 6, ghostRunners: true, hbpWalks: false, challenges: 0,
        designatedHitter: false
    )
    static let baseballDefaults = GameSettings(
        innings: 9, extraInnings: true, substitutions: true, allTeamPitch: true,
        maxStrikes: 3, maxBalls: 4, ghostRunners: false, hbpWalks: true, challenges: 2,
        designatedHitter: false
    )

    /// Which preset the current values match — or `.custom` if they match neither. Because this
    /// compares the whole struct (Equatable via Hashable), editing any single field away from a
    /// preset instantly reads as `.custom`.
    var matchedType: GameType {
        switch self {
        case Self.blitzballDefaults: return .blitzball
        case Self.baseballDefaults:  return .baseball
        default:                     return .custom
        }
    }
}
