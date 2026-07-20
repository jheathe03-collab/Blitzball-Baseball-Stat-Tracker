//
//  BracketTests.swift
//  Blitzball Stat TrackerTests
//
//  Verifies single-elim seeding + byes (pure logic, no SwiftData).
//

import Testing
@testable import Blitzball_Stat_Tracker

struct BracketTests {

    @Test func twoTeams() throws {
        let b = BracketBuilder.build(seededTeamNames: ["A", "B"])
        #expect(b.rounds == 1)
        #expect(b.matches.count == 1)
        #expect(b.matches[0].top == .team(seed: 1, name: "A"))
        #expect(b.matches[0].bottom == .team(seed: 2, name: "B"))
    }

    @Test func fourTeamsStandardSeeding() throws {
        // Standard 4-team: 1v4 and 2v3, winners meet in the final.
        let b = BracketBuilder.build(seededTeamNames: ["A", "B", "C", "D"])
        #expect(b.rounds == 2)
        let r0 = b.matchesByRound[0]
        #expect(r0.count == 2)
        #expect(r0[0].top == .team(seed: 1, name: "A"))
        #expect(r0[0].bottom == .team(seed: 4, name: "D"))
        #expect(r0[1].top == .team(seed: 2, name: "B"))
        #expect(r0[1].bottom == .team(seed: 3, name: "C"))
        // The final exists and is TBD.
        #expect(b.matchesByRound[1].count == 1)
        #expect(b.matchesByRound[1][0].top == .tbd)
    }

    @Test func fiveTeamsGivesByesToTopSeeds() throws {
        // 5 teams → size 8, 3 rounds. Seeds 1,2,3 get byes; 4 vs 5 is the only real first-round game.
        let b = BracketBuilder.build(seededTeamNames: ["A", "B", "C", "D", "E"])
        #expect(b.rounds == 3)
        let r0 = b.matchesByRound[0]
        #expect(r0.count == 4)

        // Exactly one real (team-vs-team) first-round match, and it's 4 vs 5.
        let realMatches = r0.filter {
            if case .team = $0.top, case .team = $0.bottom { return true }
            return false
        }
        #expect(realMatches.count == 1)
        #expect(realMatches[0].top == .team(seed: 4, name: "D"))
        #expect(realMatches[0].bottom == .team(seed: 5, name: "E"))

        // Seed 1 is paired with a bye (no double-byes anywhere).
        let seed1 = r0.first { $0.top == .team(seed: 1, name: "A") }
        #expect(seed1?.bottom == .bye)
        let doubleByes = r0.filter { $0.top == .bye && $0.bottom == .bye }
        #expect(doubleByes.isEmpty)
    }

    @Test func eightTeamsAllRealFirstRound() throws {
        let b = BracketBuilder.build(seededTeamNames: (1...8).map { "T\($0)" })
        #expect(b.rounds == 3)
        #expect(b.matchesByRound[0].count == 4)
        let anyBye = b.matchesByRound[0].contains { $0.top == .bye || $0.bottom == .bye }
        #expect(!anyBye)
        // #1 and #2 are in opposite halves (can only meet in the final): seeds 1 and 2 are not in
        // the same first-round match.
        for match in b.matchesByRound[0] {
            let seeds = [match.top, match.bottom].compactMap { slot -> Int? in
                if case .team(let s, _) = slot { return s }; return nil
            }
            #expect(!(seeds.contains(1) && seeds.contains(2)))
        }
    }

    @Test func onlyOneTeamIsEmptyBracket() throws {
        #expect(BracketBuilder.build(seededTeamNames: ["A"]).isEmpty)
        #expect(BracketBuilder.build(seededTeamNames: []).isEmpty)
    }
}
