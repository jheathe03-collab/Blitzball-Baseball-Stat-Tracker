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
