import Foundation

/// The result of one plate appearance. In the live game, tapping one of these applies its deltas
/// to BOTH the batter's line and the current pitcher's line, so the two can never disagree.
/// Runs and RBIs are handled separately (ghost runners = runs are entered by hand).
public enum PlateAppearanceOutcome: String, CaseIterable, Codable, Sendable {
    case single
    case double
    case triple
    case homeRun
    case walk
    case strikeout
    case strikeoutLooking
    case out
    case hitByPitch

    /// Short label for the tap buttons.
    public var label: String {
        switch self {
        case .single:     return "1B"
        case .double:     return "2B"
        case .triple:     return "3B"
        case .homeRun:    return "HR"
        case .walk:       return "BB"
        case .strikeout:  return "K"
        case .strikeoutLooking: return "Kʟ"
        case .out:        return "Out"
        case .hitByPitch: return "HBP"
        }
    }

    public var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun: return true
        default: return false
        }
    }

    /// Walks and hit-by-pitch are plate appearances but NOT at-bats.
    public var isAtBat: Bool {
        switch self {
        case .walk, .hitByPitch: return false
        default: return true
        }
    }

    /// Whether this outcome records an out (a strikeout or an in-play out).
    public var isOut: Bool {
        self == .strikeout || self == .strikeoutLooking || self == .out
    }
}

extension BattingStats {
    /// Apply one plate-appearance outcome to this batting line. (Runs/RBI are handled separately.)
    public mutating func record(_ outcome: PlateAppearanceOutcome) {
        plateAppearances += 1
        if outcome.isAtBat { atBats += 1 }
        switch outcome {
        case .single:     hits += 1
        case .double:     hits += 1; doubles += 1
        case .triple:     hits += 1; triples += 1
        case .homeRun:    hits += 1; homeRuns += 1
        case .walk:       walks += 1
        case .strikeout:  strikeouts += 1
        case .strikeoutLooking: strikeouts += 1; strikeoutsLooking += 1
        case .out:        break
        case .hitByPitch: hitByPitch += 1
        }
    }
}

extension PitchingStats {
    /// Apply one plate-appearance outcome to the pitcher's line (the defense's side of the same
    /// event). (Runs allowed are handled separately, alongside the batting-team run entry.)
    public mutating func recordAllowed(_ outcome: PlateAppearanceOutcome) {
        if outcome.isAtBat { atBatsAgainst += 1 }
        if outcome.isOut { outsRecorded += 1 }
        switch outcome {
        case .single, .double, .triple: hitsAllowed += 1
        case .homeRun:                  hitsAllowed += 1; homeRunsAllowed += 1
        case .walk:                     walksAllowed += 1
        case .strikeout, .strikeoutLooking: strikeouts += 1
        case .out, .hitByPitch:         break
        }
    }
}
