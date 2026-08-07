//
//  BaserunningEventTests.swift
//  Blitzball Stat TrackerTests
//
//  Phase 1 of the drag-to-steal feature: the Caught Stealing stat plumbing (totals, subtraction,
//  lenient decoding) and the Safe/Out reason enums (their credit flags and play-log prose).
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct BaserunningEventTests {

    @Test func caughtStealingTotalsAndFloorsAtZero() {
        let a = BattingStats(stolenBases: 2, caughtStealing: 1)
        let b = BattingStats(stolenBases: 1, caughtStealing: 3)
        #expect((a + b).caughtStealing == 4)
        #expect((b - a).caughtStealing == 2)
        #expect((a - b).caughtStealing == 0)   // never underflows
    }

    @Test func caughtStealingRoundTripsAndDefaultsForOldBlobs() throws {
        let encoded = try JSONEncoder().encode(BattingStats(caughtStealing: 5))
        #expect(try JSONDecoder().decode(BattingStats.self, from: encoded).caughtStealing == 5)

        // A line saved before the stat existed (no key) loads as 0, not a decode failure.
        let legacy = try JSONDecoder().decode(BattingStats.self, from: Data(#"{"hits":1}"#.utf8))
        #expect(legacy.caughtStealing == 0)
        #expect(legacy.hits == 1)
    }

    @Test func safeReasonFlagsAndProse() {
        #expect(SafeAdvanceReason.stolenBase.creditsStolenBase)
        #expect(!SafeAdvanceReason.defensiveIndifference.creditsStolenBase)
        #expect(SafeAdvanceReason.throwingError.chargesError)
        #expect(SafeAdvanceReason.fieldingError.chargesError)
        #expect(!SafeAdvanceReason.stolenBase.chargesError)

        #expect(SafeAdvanceReason.stolenBase.logLine(runner: "Sam", base: "second") == "Sam steals second.")
        #expect(SafeAdvanceReason.throwingError.logLine(runner: "Sam", base: "second")
                == "Sam takes second on a throwing error.")
        #expect(SafeAdvanceReason.other.logLine(runner: "Sam", base: "third") == "Sam advances to third.")
    }

    @Test func outReasonFlagsAndProse() {
        #expect(OutReason.caughtStealing.creditsCaughtStealing)
        #expect(!OutReason.pickedOff.creditsCaughtStealing)

        #expect(OutReason.caughtStealing.logLine(runner: "Sam", base: "third") == "Sam caught stealing at third.")
        #expect(OutReason.pickedOff.logLine(runner: "Sam", base: "first") == "Sam picked off at first.")
        #expect(OutReason.outOnAppeal.logLine(runner: "Sam", base: "second") == "Sam out on appeal at second.")
    }
}
