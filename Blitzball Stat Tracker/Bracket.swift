//
//  Bracket.swift
//  Blitzball Stat Tracker
//
//  Pure single-elimination bracket construction from a seeded list of team names. Pads up to the
//  next power of two; extra slots become byes given to the top seeds (standard seeding), so #1 and
//  #2 can only meet in the final. Stage 1 uses this to DRAW the bracket; later rounds are TBD.
//

import Foundation
import SwiftData

/// One side of a match: a seeded team, a bye (empty slot), or an undecided winner of a prior match.
enum BracketSlot: Equatable {
    case team(seed: Int, name: String)
    case bye
    case tbd
}

struct BracketMatch: Identifiable {
    let id: Int
    let round: Int          // 0 = first round
    let indexInRound: Int
    var top: BracketSlot
    var bottom: BracketSlot
}

struct Bracket {
    let rounds: Int
    let firstRoundMatches: Int
    let matches: [BracketMatch]

    var matchesByRound: [[BracketMatch]] {
        (0..<rounds).map { r in matches.filter { $0.round == r }.sorted { $0.indexInRound < $1.indexInRound } }
    }
    var isEmpty: Bool { matches.isEmpty }
}

// MARK: - Result-aware display model (what BracketView actually renders)

/// One rendered side of a match: a team (with seed + optional score + winner highlight), a bye, or
/// an undecided slot.
struct BracketDisplaySlot: Equatable {
    var name: String?
    var seed: Int?
    var score: Int?
    var isBye: Bool = false
    var isWinner: Bool = false
}

struct BracketDisplayMatch: Identifiable {
    let id: Int
    let round: Int
    let indexInRound: Int
    var top: BracketDisplaySlot
    var bottom: BracketDisplaySlot
    /// Both teams set and not yet finished — tappable to play.
    var isPlayable: Bool = false
    /// The underlying match game id (set when the match is playable or has been played), so a tap
    /// can open the pregame / summary.
    var gameID: PersistentIdentifier? = nil
}

enum BracketBuilder {

    /// Standard seeding order for a power-of-two bracket: the top-to-bottom list of seed numbers,
    /// arranged so the top seeds are spread across the bracket (1 and 2 meet only in the final).
    static func seedPositions(size: Int) -> [Int] {
        var seeds = [1]
        while seeds.count < size {
            let sum = seeds.count * 2 + 1
            var next: [Int] = []
            for s in seeds { next.append(s); next.append(sum - s) }
            seeds = next
        }
        return seeds
    }

    /// Build a bracket from participant names given in seed order (index 0 = seed 1).
    static func build(seededTeamNames names: [String]) -> Bracket {
        let n = names.count
        guard n >= 2 else { return Bracket(rounds: 0, firstRoundMatches: 0, matches: []) }

        var size = 2
        while size < n { size *= 2 }                 // next power of two ≥ n
        let rounds = Int(log2(Double(size)))
        let positions = seedPositions(size: size)     // seed at each top→bottom slot

        func slot(forSeed seed: Int) -> BracketSlot {
            seed <= n ? .team(seed: seed, name: names[seed - 1]) : .bye
        }

        var matches: [BracketMatch] = []
        var id = 0

        // Round 0: adjacent seeded slots.
        let firstRoundMatches = size / 2
        for m in 0..<firstRoundMatches {
            matches.append(BracketMatch(
                id: id, round: 0, indexInRound: m,
                top: slot(forSeed: positions[m * 2]),
                bottom: slot(forSeed: positions[m * 2 + 1])
            ))
            id += 1
        }

        // Later rounds: shape only (winners TBD until Stage 2 plays them).
        var prev = firstRoundMatches
        for r in 1..<rounds {
            let count = prev / 2
            for m in 0..<count {
                matches.append(BracketMatch(id: id, round: r, indexInRound: m, top: .tbd, bottom: .tbd))
                id += 1
            }
            prev = count
        }

        return Bracket(rounds: rounds, firstRoundMatches: firstRoundMatches, matches: matches)
    }
}
