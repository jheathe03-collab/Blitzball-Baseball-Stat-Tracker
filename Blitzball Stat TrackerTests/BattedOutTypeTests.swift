//
//  BattedOutTypeTests.swift
//  Blitzball Stat TrackerTests
//
//  The specific-out-kind enum: which options each contact type offers, and that every kind has a
//  headline label and a prose verb.
//

import Testing
@testable import Blitzball_Stat_Tracker

struct BattedOutTypeTests {

    @Test func eachContactTypeOffersItsOwnOutKinds() {
        #expect(BattedBallType.groundBall.outTypeOptions == [.groundOut])
        #expect(BattedBallType.lineDrive.outTypeOptions == [.lineOut, .lineOutFoul])
        #expect(BattedBallType.flyBall.outTypeOptions == [.flyOut, .flyOutFoul])
        #expect(BattedBallType.popFly.outTypeOptions == [.popOut, .popOutFoul])
        #expect(BattedBallType.bunt.outTypeOptions == [.buntOutAtFirst, .popOut, .popOutFoul])
    }

    @Test func groundBallIsTheOnlyAutoSelectedOut() {
        // A single option means the live flow records it without an extra tap; the rest ask.
        let single = BattedBallType.allCases.filter { $0.outTypeOptions.count == 1 }
        #expect(single == [.groundBall])
    }

    @Test func everyOutKindHasALabelAndVerb() {
        for out in BattedOutType.allCases {
            #expect(!out.label.isEmpty)
            #expect(!out.verb.isEmpty)
        }
    }
}
