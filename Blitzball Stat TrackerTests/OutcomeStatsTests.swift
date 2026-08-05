//
//  OutcomeStatsTests.swift
//  Blitzball Stat TrackerTests
//
//  What each plate-appearance outcome does to the batter's and pitcher's lines.
//
//  Nothing covered this before — every outcome→stat rule was unverified — so these pin the ORIGINAL
//  nine outcomes as a regression baseline as well as the new reached-on-error / fielder's-choice
//  ones. The headline case is `singleAdvancedOnError`: scoring that misplay as a double is what
//  inflated slugging in a real game, because `singles` is derived as hits − 2B − 3B − HR.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct OutcomeStatsTests {

    private func batting(_ outcome: PlateAppearanceOutcome) -> BattingStats {
        var s = BattingStats(); s.record(outcome); return s
    }
    private func pitching(_ outcome: PlateAppearanceOutcome) -> PitchingStats {
        var s = PitchingStats(); s.recordAllowed(outcome); return s
    }

    // MARK: - Baseline: the original outcomes

    @Test func singleCreditsOneHitAndOneAtBat() throws {
        let b = batting(.single)
        #expect(b.plateAppearances == 1)
        #expect(b.atBats == 1)
        #expect(b.hits == 1)
        #expect(b.singles == 1)
        #expect(b.totalBases == 1)
    }

    @Test func doubleCreditsTwoTotalBases() throws {
        let b = batting(.double)
        #expect(b.hits == 1)
        #expect(b.doubles == 1)
        #expect(b.singles == 0)
        #expect(b.totalBases == 2)
    }

    @Test func walkIsAPlateAppearanceButNotAnAtBat() throws {
        let b = batting(.walk)
        #expect(b.plateAppearances == 1)
        #expect(b.atBats == 0)
        #expect(b.walks == 1)
    }

    @Test func strikeoutLookingCountsAsBothKAndKLooking() throws {
        let b = batting(.strikeoutLooking)
        #expect(b.strikeouts == 1)
        #expect(b.strikeoutsLooking == 1)
        #expect(pitching(.strikeoutLooking).strikeouts == 1)
        #expect(pitching(.strikeoutLooking).strikeoutsLooking == 1)
    }

    @Test func outsAreRecordedOnlyForOutcomesThatRetireTheBatter() throws {
        #expect(pitching(.out).outsRecorded == 1)
        #expect(pitching(.strikeout).outsRecorded == 1)
        #expect(pitching(.single).outsRecorded == 0)
    }

    // MARK: - Reached on error

    /// THE bug this feature exists for. A batter who reached second on a misplay is credited a
    /// single — not a double — so slugging reflects what he actually earned.
    @Test func singlePlusErrorCreditsASingleNotADouble() throws {
        let b = batting(.singleAdvancedOnError)
        #expect(b.hits == 1)
        #expect(b.doubles == 0)         // ← the inflation bug
        #expect(b.singles == 1)
        #expect(b.totalBases == 1)      // one base of credit, even though he's standing on second
        #expect(b.atBats == 1)
        #expect(b.sluggingPercentage == 1.0)
    }

    /// He's on second, but the batter and pitcher are both charged as if it were a single.
    @Test func singlePlusErrorChargesThePitcherOneHit() throws {
        let p = pitching(.singleAdvancedOnError)
        #expect(p.hitsAllowed == 1)
        #expect(p.atBatsAgainst == 1)
        #expect(p.outsRecorded == 0)
    }

    @Test func doublePlusErrorCreditsADoubleNotATriple() throws {
        let b = batting(.doubleAdvancedToThird)
        #expect(b.doubles == 1)
        #expect(b.triples == 0)
        #expect(b.totalBases == 2)
    }

    /// Reaching on an error is an at-bat with NO hit — it should drag the average down, and it must
    /// not be credited to the pitcher as a hit allowed.
    @Test func reachedOnErrorIsAnAtBatWithNoHit() throws {
        for outcome in [PlateAppearanceOutcome.reachedOnError,
                        .reachedOnTwoBaseError, .reachedOnThreeBaseError] {
            let b = batting(outcome)
            #expect(b.atBats == 1)
            #expect(b.hits == 0)
            #expect(b.reachedOnError == 1)
            #expect(b.battingAverage == 0)
            #expect(pitching(outcome).hitsAllowed == 0)
            #expect(pitching(outcome).atBatsAgainst == 1)
        }
    }

    /// Fielder's choice: an at-bat, no hit, and — per this app's scoring — no out and no error.
    @Test func fieldersChoiceIsAnAtBatWithNoHitNoOutNoError() throws {
        for outcome in [PlateAppearanceOutcome.fieldersChoice,
                        .fieldersChoiceToSecond, .fieldersChoiceToThird] {
            let b = batting(outcome)
            #expect(b.atBats == 1)
            #expect(b.hits == 0)
            #expect(b.reachedOnError == 0)      // no error charged to the BATTER's line
            #expect(outcome.isOut == false)
            #expect(pitching(outcome).outsRecorded == 0)
        }
        #expect(PlateAppearanceOutcome.fieldersChoice.chargesError == false)
    }

    // MARK: - Shape of the new cases

    /// Each variant leaves the batter on the same base as the plain hit it replaces — that's what
    /// makes re-classifying one a pure stat swap with no runners to move.
    @Test func variantsReachTheSameBaseAsTheHitTheyReplace() throws {
        #expect(PlateAppearanceOutcome.reachedOnError.basesReached == 1)
        #expect(PlateAppearanceOutcome.fieldersChoice.basesReached == 1)
        #expect(PlateAppearanceOutcome.singleAdvancedOnError.basesReached == 2)
        #expect(PlateAppearanceOutcome.reachedOnTwoBaseError.basesReached == 2)
        #expect(PlateAppearanceOutcome.fieldersChoiceToSecond.basesReached == 2)
        #expect(PlateAppearanceOutcome.singleAdvancedToThird.basesReached == 3)
        #expect(PlateAppearanceOutcome.doubleAdvancedToThird.basesReached == 3)
        #expect(PlateAppearanceOutcome.reachedOnThreeBaseError.basesReached == 3)
        #expect(PlateAppearanceOutcome.fieldersChoiceToThird.basesReached == 3)
        // Outs don't put anyone on base.
        #expect(PlateAppearanceOutcome.strikeout.basesReached == nil)
    }

    /// Every error variant charges the fielding team exactly one error; nothing else does.
    @Test func onlyErrorVariantsChargeAnError() throws {
        let charging = PlateAppearanceOutcome.allCases.filter(\.chargesError)
        #expect(charging.count == 8)
        #expect(charging.contains(.singleAdvancedOnError))
        #expect(charging.contains(.fieldersChoiceToThird))
        #expect(!charging.contains(.single))
        #expect(!charging.contains(.fieldersChoice))   // a plain FC is nobody's mistake
    }

    /// The scoring pad keeps its nine buttons; the variants live behind the menu.
    @Test func padAndMenuTogetherCoverEveryOutcome() throws {
        let pad = PlateAppearanceOutcome.primaryCases
        let menu = PlateAppearanceOutcome.reachedOnCases
        #expect(pad.count == 9)
        #expect(menu.count == 9)
        #expect(Set(pad).isDisjoint(with: Set(menu)))
        #expect(Set(pad).union(menu) == Set(PlateAppearanceOutcome.allCases))
    }

    /// Every outcome has a button label, a full name, and a readable verb phrase.
    @Test func everyOutcomeIsFullyLabeled() throws {
        for outcome in PlateAppearanceOutcome.allCases {
            #expect(!outcome.label.isEmpty)
            #expect(!outcome.playLabel.isEmpty)
            #expect(!outcome.pastTenseDescription.isEmpty)
        }
    }

    /// Old blobs written before `reachedOnError` existed still decode, with the new stat at zero.
    @Test func olderBlobWithoutReachedOnErrorDecodes() throws {
        let legacy = Data(#"{"plateAppearances":4,"atBats":4,"hits":2,"doubles":1}"#.utf8)
        let decoded = try JSONDecoder().decode(BattingStats.self, from: legacy)
        #expect(decoded.hits == 2)
        #expect(decoded.doubles == 1)
        #expect(decoded.reachedOnError == 0)
    }
}
