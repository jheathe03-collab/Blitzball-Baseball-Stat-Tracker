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
    /// An out on a caught fly that scores a runner. A plate appearance but NOT an at-bat, so it
    /// leaves AVG/SLG alone; it does count in the OBP denominator. Requires fewer than the inning's
    /// final out (so the run counts) and a runner who can tag — enforced where it's offered.
    case sacrificeFly

    // MARK: Reached on error / fielder's choice
    //
    // These separate WHERE the batter ended up from WHAT he's credited with. Scoring a misplay as a
    // double inflates hits and slugging (`singles` is derived as hits − 2B − 3B − HR), so a batter
    // who reached second on a bobble needs to be credited a single — or nothing — while still
    // standing on second. Each case below reaches the same base as the plain hit it replaces, which
    // is why re-classifying one never moves runners.
    //
    // Per the app's scoring rules a fielder's choice records NO out here: the batter is safe, and
    // you clear the retired runner yourself on the diamond.
    case reachedOnError
    case fieldersChoice
    case singleAdvancedOnError        // credited a single, ended up on 2nd
    case reachedOnTwoBaseError
    case fieldersChoiceToSecond
    case singleAdvancedToThird        // credited a single, ended up on 3rd
    case doubleAdvancedToThird        // credited a double, ended up on 3rd
    case reachedOnThreeBaseError
    case fieldersChoiceToThird

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
        case .sacrificeFly: return "SF"
        case .reachedOnError:          return "E"
        case .fieldersChoice:          return "FC"
        case .singleAdvancedOnError:   return "1B+E2"
        case .reachedOnTwoBaseError:   return "E2"
        case .fieldersChoiceToSecond:  return "FC+E2"
        case .singleAdvancedToThird:   return "1B+E3"
        case .doubleAdvancedToThird:   return "2B+E3"
        case .reachedOnThreeBaseError: return "E3"
        case .fieldersChoiceToThird:   return "FC+E3"
        }
    }

    /// Credited with a base hit. The error/FC hybrids that carry a hit count here — the batter is
    /// charged the hit he actually earned, no more.
    public var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun,
             .singleAdvancedOnError, .singleAdvancedToThird, .doubleAdvancedToThird:
            return true
        default:
            return false
        }
    }

    /// Walks and hit-by-pitch are plate appearances but NOT at-bats. Reaching on an error or a
    /// fielder's choice IS an at-bat — it's why those drag a batting average down.
    public var isAtBat: Bool {
        switch self {
        case .walk, .hitByPitch, .sacrificeFly: return false
        default: return true
        }
    }

    /// Whether this outcome records an out (a strikeout or an in-play out). A fielder's choice does
    /// NOT: the batter is safe, and the retired runner is cleared by hand on the diamond.
    public var isOut: Bool {
        self == .strikeout || self == .strikeoutLooking || self == .out || self == .sacrificeFly
    }

    /// Which base the batter ends up on (1st/2nd/3rd, 4 = home), or nil if he doesn't reach.
    /// Drives base running, so each error variant lands on the same base as the hit it replaces.
    public var basesReached: Int? {
        switch self {
        case .single, .walk, .hitByPitch, .reachedOnError, .fieldersChoice:
            return 1
        case .double, .singleAdvancedOnError, .reachedOnTwoBaseError, .fieldersChoiceToSecond:
            return 2
        case .triple, .singleAdvancedToThird, .doubleAdvancedToThird,
             .reachedOnThreeBaseError, .fieldersChoiceToThird:
            return 3
        case .homeRun:
            return 4
        case .strikeout, .strikeoutLooking, .out, .sacrificeFly:
            return nil
        }
    }

    /// Whether the ball was put in play, so a contact type and field location make sense. Walks,
    /// hit-by-pitch, and strikeouts are not batted balls; everything else (hits, in-play outs, and
    /// the reached-on-error / fielder's-choice variants) is.
    public var isBattedBall: Bool {
        switch self {
        case .walk, .hitByPitch, .strikeout, .strikeoutLooking: return false
        default: return true
        }
    }

    /// A fielder's choice — the batter is safe because the defense chose to play on a runner instead.
    public var isFieldersChoice: Bool {
        switch self {
        case .fieldersChoice, .fieldersChoiceToSecond, .fieldersChoiceToThird: return true
        default: return false
        }
    }

    /// The batter reached base ONLY because of a fielding error — he'd have been out on clean play.
    /// Under rule 9.16 such a batter is erased in the earned-run reconstruction, so ANY run he later
    /// scores is unearned. This is deliberately NARROWER than `chargesError`: the "advanced on error"
    /// variants (a real hit where an error only added bases) are excluded, because whether their run
    /// is unearned depends on a full reconstruction and is left to the manual Edit Play flow.
    public var batterReachedOnError: Bool {
        switch self {
        case .reachedOnError, .reachedOnTwoBaseError, .reachedOnThreeBaseError: return true
        default: return false
        }
    }

    /// Reached base on a misplay rather than clean contact — an error or a fielder's choice. The play
    /// summary uses this to name the fielder inline ("reaches on an error by the shortstop").
    public var isReachedOnMisplay: Bool {
        if chargesError { return true }
        switch self {
        case .fieldersChoice, .fieldersChoiceToSecond, .fieldersChoiceToThird: return true
        default: return false
        }
    }

    /// Whether the fielding team is charged an error on this play (drives the line score's E column).
    public var chargesError: Bool {
        switch self {
        case .reachedOnError, .singleAdvancedOnError, .reachedOnTwoBaseError,
             .fieldersChoiceToSecond, .singleAdvancedToThird, .doubleAdvancedToThird,
             .reachedOnThreeBaseError, .fieldersChoiceToThird:
            return true
        default:
            return false
        }
    }

    /// What this play could be re-scored as. Grouped by the base the batter ended up on, so every
    /// option leaves him where he already is — which is what makes a re-classification a pure stat
    /// swap with no runners to move. The list always includes the current outcome, and the swaps
    /// are reversible (a Single can become Reached on Error and back again).
    ///
    /// An out can become "reached on error" or a fielder's choice — the common real correction that
    /// otherwise costs a batter a plate appearance he actually survived. Walks, HBP and home runs
    /// have nothing sensible to swap to, so they offer only themselves.
    public var reclassificationOptions: [PlateAppearanceOutcome] {
        switch self {
        case .walk, .hitByPitch, .homeRun, .sacrificeFly:
            return [self]
        case .out, .strikeout, .strikeoutLooking:
            return [.out, .strikeout, .strikeoutLooking, .reachedOnError, .fieldersChoice]
        default:
            switch basesReached {
            case 1:
                return [.single, .reachedOnError, .fieldersChoice]
            case 2:
                return [.double, .singleAdvancedOnError, .reachedOnTwoBaseError, .fieldersChoiceToSecond]
            case 3:
                return [.triple, .singleAdvancedToThird, .doubleAdvancedToThird,
                        .reachedOnThreeBaseError, .fieldersChoiceToThird]
            default:
                return [self]
            }
        }
    }

    /// The plain outcomes on the scoring pad. The error/fielder's-choice variants live behind the
    /// "Reached On…" menu so the grid stays tappable mid-game.
    public static var primaryCases: [PlateAppearanceOutcome] {
        [.single, .double, .triple, .homeRun, .walk, .strikeout, .strikeoutLooking, .out, .hitByPitch]
    }

    /// The error / fielder's-choice variants, grouped by how far the batter got.
    public static var reachedOnCases: [PlateAppearanceOutcome] {
        [.reachedOnError, .fieldersChoice,
         .singleAdvancedOnError, .reachedOnTwoBaseError, .fieldersChoiceToSecond,
         .singleAdvancedToThird, .doubleAdvancedToThird, .reachedOnThreeBaseError,
         .fieldersChoiceToThird]
    }

    /// Full name for the play log, where there's room for words instead of "1B".
    public var playLabel: String {
        switch self {
        case .single:           return "Single"
        case .double:           return "Double"
        case .triple:           return "Triple"
        case .homeRun:          return "Home Run"
        case .walk:             return "Walk"
        case .strikeout:        return "Strikeout"
        case .strikeoutLooking: return "Strikeout Looking"
        case .out:              return "Out"
        case .hitByPitch:       return "Hit By Pitch"
        case .sacrificeFly:     return "Sacrifice Fly"
        case .reachedOnError:          return "Reached on Error"
        case .fieldersChoice:          return "Fielder's Choice"
        case .singleAdvancedOnError:   return "Single + 2nd on Error"
        case .reachedOnTwoBaseError:   return "Reached on Two-Base Error"
        case .fieldersChoiceToSecond:  return "Fielder's Choice + 2nd on Error"
        case .singleAdvancedToThird:   return "Single + 3rd on Error"
        case .doubleAdvancedToThird:   return "Double + 3rd on Error"
        case .reachedOnThreeBaseError: return "Reached on Three-Base Error"
        case .fieldersChoiceToThird:   return "Fielder's Choice + 3rd on Error"
        }
    }

    /// Verb phrase for the log's prose line — reads as "\(batter) \(pastTenseDescription)".
    public var pastTenseDescription: String {
        switch self {
        case .single:           return "hits a single"
        case .double:           return "hits a double"
        case .triple:           return "hits a triple"
        case .homeRun:          return "hits a home run"
        case .walk:             return "walks"
        case .strikeout:        return "strikes out swinging"
        case .strikeoutLooking: return "strikes out looking"
        case .out:              return "is out"
        case .hitByPitch:       return "is hit by a pitch"
        case .sacrificeFly:     return "hits a sacrifice fly"
        case .reachedOnError:          return "reaches on an error"
        case .fieldersChoice:          return "reaches on a fielder's choice"
        case .singleAdvancedOnError:   return "singles and takes second on an error"
        case .reachedOnTwoBaseError:   return "reaches second on a two-base error"
        case .fieldersChoiceToSecond:  return "reaches second on a fielder's choice and an error"
        case .singleAdvancedToThird:   return "singles and takes third on an error"
        case .doubleAdvancedToThird:   return "doubles and takes third on an error"
        case .reachedOnThreeBaseError: return "reaches third on a three-base error"
        case .fieldersChoiceToThird:   return "reaches third on a fielder's choice and an error"
        }
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
        // A sacrifice fly is an out with no at-bat (the shared `if outcome.isAtBat` above already
        // skipped it), so AVG/SLG are untouched; only the SF tally rises (it lifts the OBP
        // denominator). The RBI and the run are credited by the scoring code, not here.
        case .sacrificeFly: sacrificeFlies += 1

        // Reaching on an error is an at-bat with no hit — which is exactly what the shared
        // `if outcome.isAtBat` above already did, so the rate stats need no special handling:
        // AVG/OBP/SLG denominators rise while the numerators hold. We only track the count.
        case .reachedOnError, .reachedOnTwoBaseError, .reachedOnThreeBaseError:
            reachedOnError += 1

        // Fielder's choice: an at-bat, no hit, no error charged to anyone — we just tally it.
        case .fieldersChoice, .fieldersChoiceToSecond, .fieldersChoiceToThird:
            fieldersChoices += 1

        // The hybrids credit ONLY the hit the batter earned. Note that a batter standing on second
        // after "Single + 2nd on Error" gets a single, NOT a double — crediting the double is the
        // bug that inflated slugging, because `singles` is derived as hits − 2B − 3B − HR.
        case .singleAdvancedOnError, .singleAdvancedToThird:
            hits += 1
        case .doubleAdvancedToThird:
            hits += 1; doubles += 1
        }
    }
}

extension PitchingStats {
    /// Apply one plate-appearance outcome to the pitcher's line (the defense's side of the same
    /// event). (Runs allowed are handled separately, alongside the batting-team run entry.)
    public mutating func recordAllowed(_ outcome: PlateAppearanceOutcome) {
        battersFaced += 1   // every completed plate appearance is one batter faced (BF)
        if outcome.isAtBat { atBatsAgainst += 1 }
        if outcome.isOut { outsRecorded += 1 }
        switch outcome {
        case .single, .double, .triple: hitsAllowed += 1
        case .homeRun:                  hitsAllowed += 1; homeRunsAllowed += 1
        case .walk:                     walksAllowed += 1
        case .strikeout:                strikeouts += 1
        case .strikeoutLooking:         strikeouts += 1; strikeoutsLooking += 1
        case .out:                      break
        case .hitByPitch:               hitBatters += 1   // one pitch, counts toward Total Pitches
        // Sac fly: the out is tallied by the shared `if outcome.isOut` above, and it's not an
        // at-bat against the pitcher. No hit; the run allowed is charged by the scoring code.
        case .sacrificeFly:             break

        // The pitcher is only charged the hit the batter earned — a ball misplayed into extra
        // bases isn't a hit against him at all.
        case .singleAdvancedOnError, .singleAdvancedToThird, .doubleAdvancedToThird:
            hitsAllowed += 1
        case .reachedOnError, .reachedOnTwoBaseError, .reachedOnThreeBaseError,
             .fieldersChoice, .fieldersChoiceToSecond, .fieldersChoiceToThird:
            break
        }
    }
}
