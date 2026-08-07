import Foundation

/// How a runner reached the base he was dragged to and called SAFE. Only `stolenBase` credits a
/// steal; the two error reasons charge the fielding team an error; the rest are plain advances that
/// touch no stats. (`Codable`/`Sendable` so it can ride along in snapshots and cross tasks.)
public enum SafeAdvanceReason: String, CaseIterable, Codable, Sendable {
    case stolenBase
    case defensiveIndifference
    case throwingError
    case fieldingError
    case other

    /// The label shown on the "How did the runner take 2nd?" menu.
    public var label: String {
        switch self {
        case .stolenBase:            return "Stolen Base"
        case .defensiveIndifference: return "Defensive Indifference"
        case .throwingError:         return "Throwing Error"
        case .fieldingError:         return "Fielding Error"
        case .other:                 return "Other"
        }
    }

    /// Credits the runner a stolen base.
    public var creditsStolenBase: Bool { self == .stolenBase }

    /// Charges the fielding team an error (the line score's E column).
    public var chargesError: Bool {
        self == .throwingError || self == .fieldingError
    }

    /// The play-log line, e.g. "Sam steals second." / "Sam takes second on a throwing error."
    /// `base` is the spoken base name ("second", "home").
    public func logLine(runner: String, base: String) -> String {
        switch self {
        case .stolenBase:            return "\(runner) steals \(base)."
        case .defensiveIndifference: return "\(runner) takes \(base) on defensive indifference."
        case .throwingError:         return "\(runner) takes \(base) on a throwing error."
        case .fieldingError:         return "\(runner) takes \(base) on a fielding error."
        case .other:                 return "\(runner) advances to \(base)."
        }
    }
}

/// How a runner dragged to a base was retired (called OUT). Only `caughtStealing` credits a caught
/// stealing; every reason records the out itself.
public enum OutReason: String, CaseIterable, Codable, Sendable {
    case caughtStealing
    case pickedOff
    case outOnAppeal
    case other

    /// The label shown on the "How did the runner get out at 2nd?" menu.
    public var label: String {
        switch self {
        case .caughtStealing: return "Caught Stealing"
        case .pickedOff:      return "Picked Off"
        case .outOnAppeal:    return "Out on Appeal"
        case .other:          return "Other"
        }
    }

    /// Credits the runner a caught stealing.
    public var creditsCaughtStealing: Bool { self == .caughtStealing }

    /// The play-log line, e.g. "Sam caught stealing at second." `base` is the spoken base name.
    public func logLine(runner: String, base: String) -> String {
        switch self {
        case .caughtStealing: return "\(runner) caught stealing at \(base)."
        case .pickedOff:      return "\(runner) picked off at \(base)."
        case .outOnAppeal:    return "\(runner) out on appeal at \(base)."
        case .other:          return "\(runner) out at \(base)."
        }
    }
}
