import Foundation

/// How the ball came off the bat. Captured for every batted ball (hits and in-play outs alike) so
/// the play log, Play Summary, and future spray charts can describe *how* a ball was hit, not just
/// the result. Walks, strikeouts, and hit-by-pitch have no batted ball, so they carry none of this.
///
/// Stored on `PlayEvent` as a raw String, the same forward-compatible pattern as the rest of the
/// play log: a kind this build has never heard of still decodes instead of crashing an old store.
public enum BattedBallType: String, CaseIterable, Codable, Sendable {
    case groundBall
    case lineDrive
    case flyBall
    case popFly
    case bunt

    /// Menu / summary label ("Ground Ball").
    public var label: String {
        switch self {
        case .groundBall: return "Ground Ball"
        case .lineDrive:  return "Line Drive"
        case .flyBall:    return "Fly Ball"
        case .popFly:     return "Pop Fly"
        case .bunt:       return "Bunt"
        }
    }

    /// The noun used in the log's prose line ("Ground ball to shortstop."). Lower-cased so it reads
    /// naturally mid-sentence.
    public var summaryNoun: String {
        switch self {
        case .groundBall: return "ground ball"
        case .lineDrive:  return "line drive"
        case .flyBall:    return "fly ball"
        case .popFly:     return "pop fly"
        case .bunt:       return "bunt"
        }
    }

    /// The order the type menu offers them in.
    public static var menuOrder: [BattedBallType] {
        [.groundBall, .lineDrive, .flyBall, .popFly, .bunt]
    }

    /// The specific out kinds offered for this contact type when the play is an out. A ground ball
    /// has a single option, so its choice is auto-selected (no extra tap).
    public var outTypeOptions: [BattedOutType] {
        switch self {
        case .groundBall: return [.groundOut]
        case .lineDrive:  return [.lineOut, .lineOutFoul]
        case .flyBall:    return [.flyOut, .flyOutFoul]
        case .popFly:     return [.popOut, .popOutFoul]
        case .bunt:       return [.buntOutAtFirst, .popOut, .popOutFoul]
        }
    }
}

/// The specific kind of in-play out — chosen after a batted out's contact type and fielder. Enriches
/// the play log ("Fly Out", "Line Out (Foul)", "Out at 1st") beyond a bare "Out". Stored on
/// `PlayEvent` as a raw String, the same forward-compatible pattern as the rest of the batted-ball
/// data. (`Codable`/`Sendable` so it rides along in snapshots and across tasks.)
public enum BattedOutType: String, CaseIterable, Codable, Sendable {
    case groundOut
    case lineOut
    case lineOutFoul
    case flyOut
    case flyOutFoul
    case popOut
    case popOutFoul
    case buntOutAtFirst
    /// A ground ball where the batter is out at first and the other runners advance a base (a runner
    /// coming home is resolved Safe/Out). Offered on a ground ball when a runner is on; distinct from
    /// a plain ground out, where the runners hold.
    case outAtFirst
    /// Two outs on one batted ball — the batter and a runner. Offered on any contact type when a
    /// runner is on and there's room for two outs; not tied to a single contact type.
    case doublePlay
    /// Three outs on one batted ball — the batter and two runners. Offered only with 0 outs and runners
    /// on first and second (or bases loaded), where the forced runners can all be retired.
    case triplePlay

    /// The play-log headline ("Ground Out", "Fly Out (Foul)", "Out at 1st", "Double Play").
    public var label: String {
        switch self {
        case .groundOut:      return "Ground Out"
        case .lineOut:        return "Line Out"
        case .lineOutFoul:    return "Line Out (Foul)"
        case .flyOut:         return "Fly Out"
        case .flyOutFoul:     return "Fly Out (Foul)"
        case .popOut:         return "Pop Out"
        case .popOutFoul:     return "Pop Out (Foul)"
        case .buntOutAtFirst: return "Out at 1st"
        case .outAtFirst:     return "Out at 1st"
        case .doublePlay:     return "Double Play"
        case .triplePlay:     return "Triple Play"
        }
    }

    /// Verb phrase for the prose line — reads as "\(batter) \(verb) to \(fielder)".
    public var verb: String {
        switch self {
        case .groundOut:      return "grounds out"
        case .lineOut:        return "lines out"
        case .lineOutFoul:    return "lines out foul"
        case .flyOut:         return "flies out"
        case .flyOutFoul:     return "flies out foul"
        case .popOut:         return "pops out"
        case .popOutFoul:     return "pops out foul"
        case .buntOutAtFirst: return "bunts out"
        case .outAtFirst:     return "grounds out"
        case .doublePlay:     return "hits into a double play"
        case .triplePlay:     return "hits into a triple play"
        }
    }
}

/// A defensive position — where a batted ball went, or where an out was recorded. For now these are
/// just the nine spots on the field; a later "game mode" will map each to the assigned fielder, at
/// which point the label becomes that player's name. The scorebook `number` (6 = shortstop) is
/// carried now so notation like "6-3 groundout" and player assignment come for free later.
///
/// Stored on `PlayEvent` as a raw String, same forward-compatible reasoning as `BattedBallType`.
public enum FieldPosition: String, CaseIterable, Codable, Sendable {
    case pitcher
    case catcher
    case firstBase
    case secondBase
    case thirdBase
    case shortstop
    case leftField
    case centerField
    case rightField

    /// Traditional scorekeeping number: P=1, C=2, 1B=3, 2B=4, 3B=5, SS=6, LF=7, CF=8, RF=9.
    public var number: Int {
        switch self {
        case .pitcher:     return 1
        case .catcher:     return 2
        case .firstBase:   return 3
        case .secondBase:  return 4
        case .thirdBase:   return 5
        case .shortstop:   return 6
        case .leftField:   return 7
        case .centerField: return 8
        case .rightField:  return 9
        }
    }

    /// Short label for the field diagram pucks ("SS").
    public var abbreviation: String {
        switch self {
        case .pitcher:     return "P"
        case .catcher:     return "C"
        case .firstBase:   return "1B"
        case .secondBase:  return "2B"
        case .thirdBase:   return "3B"
        case .shortstop:   return "SS"
        case .leftField:   return "LF"
        case .centerField: return "CF"
        case .rightField:  return "RF"
        }
    }

    /// Full name for the log's prose line ("Ground ball to shortstop.").
    public var fullName: String {
        switch self {
        case .pitcher:     return "pitcher"
        case .catcher:     return "catcher"
        case .firstBase:   return "first base"
        case .secondBase:  return "second base"
        case .thirdBase:   return "third base"
        case .shortstop:   return "shortstop"
        case .leftField:   return "left field"
        case .centerField: return "center field"
        case .rightField:  return "right field"
        }
    }

    /// The person who plays the position — for prose like "reaches on an error by the second
    /// baseman". Distinct from `fullName` ("second base"), which names the spot the ball went to.
    public var fielderName: String {
        switch self {
        case .pitcher:     return "pitcher"
        case .catcher:     return "catcher"
        case .firstBase:   return "first baseman"
        case .secondBase:  return "second baseman"
        case .thirdBase:   return "third baseman"
        case .shortstop:   return "shortstop"
        case .leftField:   return "left fielder"
        case .centerField: return "center fielder"
        case .rightField:  return "right fielder"
        }
    }

    /// Whether this is an infield position — handy later for defaulting a ground ball to the infield
    /// and a fly ball to the outfield.
    public var isInfield: Bool {
        switch self {
        case .pitcher, .catcher, .firstBase, .secondBase, .thirdBase, .shortstop:
            return true
        case .leftField, .centerField, .rightField:
            return false
        }
    }

    /// Ordered by scorebook number — the natural order for menus and any list.
    public static var byNumber: [FieldPosition] {
        allCases.sorted { $0.number < $1.number }
    }
}
