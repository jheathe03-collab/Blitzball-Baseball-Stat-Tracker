//
//  PitchTracking.swift
//  Blitzball Stat Tracker
//
//  Small value types for the pitch-by-pitch tracking (Record Balls and Strikes / Record Pitch Type).
//  Pitch types are recorded for the play log only — they are NOT stats.
//

import Foundation

/// The type of pitch thrown — shown in the play log when Record Pitch Type is on. Not tallied anywhere.
enum PitchType: String, CaseIterable, Identifiable {
    case fastball, curveball, slider, changeup, cutter, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fastball:  return "Fastball"
        case .curveball: return "Curveball"
        case .slider:    return "Slider"
        case .changeup:  return "Changeup"
        case .cutter:    return "Cutter"
        case .other:     return "Other"
        }
    }
}

/// A count-affecting pitch from the Pitch menu — the calls that need a type when Record Pitch Type is on.
enum PitchCall {
    case calledStrike, swingingStrike, ball, foul
    /// How it reads in the play log ("Fastball — called strike").
    var logLabel: String {
        switch self {
        case .calledStrike:   return "called strike"
        case .swingingStrike: return "swinging strike"
        case .ball:           return "ball"
        case .foul:           return "foul ball"
        }
    }
}
