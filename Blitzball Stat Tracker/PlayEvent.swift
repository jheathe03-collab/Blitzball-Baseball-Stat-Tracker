//
//  PlayEvent.swift
//  Blitzball Stat Tracker
//
//  One entry in a game's play-by-play log. Before this, the app stored only AGGREGATE stats per
//  player, so there was no record of what happened when — you couldn't review an inning, and a
//  mis-scored play could only be fixed by hand-editing totals.
//
//  The log sits ALONGSIDE the aggregates rather than replacing them: stats are still applied as
//  plays happen. That keeps live scoring untouched, and (because each outcome's stat deltas are a
//  pure function of the outcome) still allows a play to be re-classified later by unapplying the
//  old deltas and applying the new ones.
//

import Foundation
import SwiftData

/// What kind of thing happened. Stored as a raw String so new kinds never break an old store.
enum PlayEventKind: String, Codable, CaseIterable {
    case gameStart
    case plateAppearance
    case inningChange
    case pitchingChange
    case substitution
    case manualRun
    case lineScoreEdit
    case steal
    case caughtStealing
    case baserunning   // other advances/outs on the bases (errors, indifference, pickoff, appeal…)
}

@Model
final class PlayEvent {

    /// The game this play belongs to. (Inverse is declared on `Game.plays`.)
    var game: Game?

    /// Append order within the game — the log's sort key. Monotonic, never reused.
    var sequence: Int = 0
    var createdAt: Date = Date.now

    /// `PlayEventKind.rawValue`. Raw so an unknown future kind still decodes.
    var kindRaw: String = PlayEventKind.plateAppearance.rawValue

    // Where in the game this happened — captured BEFORE the play is applied, because recording a
    // play advances the batter and can roll the half-inning over.
    var inning: Int = 1
    var isTopInning: Bool = true
    var outsBefore: Int = 0

    /// `PlateAppearanceOutcome.rawValue` for plate appearances; nil for every other kind.
    var outcomeRaw: String?

    /// `BattedBallType.rawValue` / `FieldPosition.rawValue` for a batted ball (hits and in-play
    /// outs); nil for walks, strikeouts, HBP, and every non-plate-appearance kind. Raw so an unknown
    /// future value still decodes, and optional so old plays (scored before this existed) stay valid.
    var battedBallTypeRaw: String?
    var fieldPositionRaw: String?

    /// `BattedOutType.rawValue` for an in-play out (grounder, fly, line, pop, bunt); nil otherwise.
    /// Drives the out's headline and prose. Raw + optional, same forward-compat reasoning as above.
    var battedOutTypeRaw: String?

    /// Who was involved. Unidirectional to-one refs, the same pattern as `Game.runnerFirst`.
    var batter: Player?
    var pitcher: Player?

    /// Pre-rendered text for kinds that aren't plate appearances ("Player04 replaces Player01").
    /// Plate appearances build their prose from the outcome so it stays correct after a re-classify.
    var detail: String = ""

    /// Runs that crossed the plate on this play, and how many of those the scorer has marked
    /// unearned (which lowers ERA without touching runs allowed).
    var runsScored: Int = 0
    var unearnedRuns: Int = 0

    /// The score immediately AFTER this play. Stored rather than derived because the running score
    /// only makes sense as of the moment the play happened — later plays keep changing it.
    var homeScore: Int = 0
    var awayScore: Int = 0

    init(
        game: Game? = nil,
        sequence: Int,
        kind: PlayEventKind,
        inning: Int,
        isTopInning: Bool,
        outsBefore: Int,
        outcome: PlateAppearanceOutcome? = nil,
        battedBallType: BattedBallType? = nil,
        fieldPosition: FieldPosition? = nil,
        battedOutType: BattedOutType? = nil,
        batter: Player? = nil,
        pitcher: Player? = nil,
        detail: String = "",
        runsScored: Int = 0,
        homeScore: Int = 0,
        awayScore: Int = 0,
        createdAt: Date = .now
    ) {
        self.game = game
        self.sequence = sequence
        self.kindRaw = kind.rawValue
        self.inning = inning
        self.isTopInning = isTopInning
        self.outsBefore = outsBefore
        self.outcomeRaw = outcome?.rawValue
        self.battedBallTypeRaw = battedBallType?.rawValue
        self.fieldPositionRaw = fieldPosition?.rawValue
        self.battedOutTypeRaw = battedOutType?.rawValue
        self.batter = batter
        self.pitcher = pitcher
        self.detail = detail
        self.runsScored = runsScored
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.createdAt = createdAt
    }
}

// MARK: - Derived

extension PlayEvent {
    var kind: PlayEventKind {
        get { PlayEventKind(rawValue: kindRaw) ?? .plateAppearance }
        set { kindRaw = newValue.rawValue }
    }

    var outcome: PlateAppearanceOutcome? {
        get { outcomeRaw.flatMap(PlateAppearanceOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var battedBallType: BattedBallType? {
        get { battedBallTypeRaw.flatMap(BattedBallType.init(rawValue:)) }
        set { battedBallTypeRaw = newValue?.rawValue }
    }

    var fieldPosition: FieldPosition? {
        get { fieldPositionRaw.flatMap(FieldPosition.init(rawValue:)) }
        set { fieldPositionRaw = newValue?.rawValue }
    }

    var battedOutType: BattedOutType? {
        get { battedOutTypeRaw.flatMap(BattedOutType.init(rawValue:)) }
        set { battedOutTypeRaw = newValue?.rawValue }
    }

    /// "Top 3" / "Bot 5" — matches `Game.halfInningLabel`.
    var halfInningLabel: String {
        "\(isTopInning ? "Top" : "Bot") \(inning)"
    }

    /// Only plate appearances can be re-classified or reassigned.
    var isEditable: Bool { kind == .plateAppearance && outcome != nil }

    /// The headline shown in the log — the outcome's name, or the event's own label.
    var title: String {
        if let outcome {
            // A tagged in-play out shows its specific kind ("Fly Out", "Out at 1st") over a bare "Out".
            if outcome == .out, let out = battedOutType { return out.label }
            return outcome.playLabel
        }
        switch kind {
        case .gameStart:      return "Game Start"
        case .inningChange:   return halfInningLabel
        case .pitchingChange: return "Pitching Change"
        case .substitution:   return "Substitution"
        case .manualRun:      return "Run Scored"
        case .lineScoreEdit:  return "Score Adjusted"
        case .steal:          return "Stolen Base"
        case .caughtStealing: return "Caught Stealing"
        case .baserunning:    return "Baserunning"
        case .plateAppearance: return "Plate Appearance"
        }
    }

    /// The prose line beneath the title. Plate appearances are generated so that re-classifying a
    /// play updates its description too; everything else uses the text captured when it happened.
    ///
    /// Sentences are composed and joined, so the batted-ball detail ("Ground ball to shortstop")
    /// slots in only when it was captured — a play with no batted ball reads exactly as before.
    var summary: String {
        guard let outcome, kind == .plateAppearance else { return detail }
        let who = batter?.name ?? "Batter"
        // A tagged in-play out reads as one phrase ("flies out to left field") — the out kind and the
        // fielder together, replacing the bare "is out" + separate contact-ball sentence.
        if outcome == .out, let out = battedOutType {
            var s = "\(who) \(out.verb)"
            if let position = fieldPosition { s += " to \(position.fullName)" }
            var parts = [s]
            if let arm = pitcher?.name { parts.append("\(arm) pitching") }
            return parts.joined(separator: ". ") + "."
        }
        var first = "\(who) \(outcome.pastTenseDescription)"
        // Error / fielder's-choice plays carry a fielder but no contact type — name them inline:
        // "reaches on an error by the shortstop".
        if battedBallType == nil, outcome.isReachedOnMisplay, let position = fieldPosition {
            first += " by the \(position.fielderName)"
        }
        var sentences = [first]
        if let phrase = battedBallPhrase { sentences.append(phrase) }
        if let arm = pitcher?.name { sentences.append("\(arm) pitching") }
        return sentences.joined(separator: ". ") + "."
    }

    /// "Ground ball to shortstop" — the contact-type detail for a cleanly-fielded ball. nil when no
    /// contact type was captured (walks, strikeouts, HBP, and the error / fielder's-choice paths,
    /// which name the fielder inline in `summary` instead). No trailing period; `summary` punctuates.
    private var battedBallPhrase: String? {
        guard let type = battedBallType else { return nil }
        let noun = type.summaryNoun
        let cased = noun.prefix(1).uppercased() + noun.dropFirst()
        if let position = fieldPosition { return "\(cased) to \(position.fullName)" }
        return cased
    }
}
