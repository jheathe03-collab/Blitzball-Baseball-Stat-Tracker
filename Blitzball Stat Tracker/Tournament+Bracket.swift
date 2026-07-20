//
//  Tournament+Bracket.swift
//  Blitzball Stat Tracker
//
//  The bracket engine: generate the match games from the seeding (with byes), advance winners round
//  by round, find the champion, and produce the result-aware display model BracketView renders.
//

import Foundation
import SwiftData

extension Tournament {

    /// Number of rounds for the current participant count (0 if fewer than two).
    var totalRounds: Int {
        let n = seedOrder.count
        guard n >= 2 else { return 0 }
        var size = 2
        while size < n { size *= 2 }
        return Int(log2(Double(size)))
    }

    func match(round: Int, slot: Int) -> Game? {
        matches.first { $0.bracketRound == round && $0.bracketSlot == slot }
    }

    /// A friendly name for a round: the last round is the Final, then Semifinals, etc.
    func roundName(_ round: Int) -> String {
        switch totalRounds - 1 - round {
        case 0:  return "Final"
        case 1:  return "Semifinals"
        case 2:  return "Quarterfinals"
        default: return "Round \(round + 1)"
        }
    }

    /// Append teams to the seeding (skipping any already seeded), rebuilding from the resolved
    /// current seeds so stale names are dropped. Shared by the participants + bracket screens.
    func appendSeeds(_ teams: [Team], currentlySeeded seeded: [Team]) {
        var names = seeded.map(\.name)
        for team in teams where !names.contains(team.name) { names.append(team.name) }
        seedOrder = names
    }

    /// The match (if any) where this team lost.
    private func eliminationMatch(for team: Team) -> Game? {
        matches
            .filter { $0.status == .final && !$0.isBye
                && ($0.homeTeam === team || $0.awayTeam === team)
                && $0.bracketWinner != nil && $0.bracketWinner !== team }
            .max { $0.bracketRound < $1.bracketRound }
    }

    /// How far a team got: Champion / Runner-up / "Lost in <round>" / "Still in" (or "Eliminated").
    func resultLabel(for team: Team) -> String {
        if champion() === team { return "Champion" }
        if let lost = eliminationMatch(for: team) {
            return lost.bracketRound == totalRounds - 1 ? "Runner-up" : "Lost in \(roundName(lost.bracketRound))"
        }
        return status == .final ? "Eliminated" : "Still in"
    }

    /// Sort key for the results table — higher = better finish.
    func finishRank(for team: Team) -> Int {
        if champion() === team { return totalRounds + 1 }
        if let lost = eliminationMatch(for: team) { return lost.bracketRound }
        return totalRounds   // still alive: ranks just below the champion
    }

    /// Distinct players with a finished stat line in this tournament.
    func participantPlayers() -> [Player] {
        var seen = Set<PersistentIdentifier>()
        var result: [Player] = []
        for match in matches where match.status == .final {
            for line in match.statLines {
                if let player = line.player, seen.insert(player.persistentModelID).inserted {
                    result.append(player)
                }
            }
        }
        return result
    }

    var finalMatch: Game? {
        guard totalRounds > 0 else { return nil }
        return match(round: totalRounds - 1, slot: 0)
    }

    /// Whether any real (non-bye) match has started or finished — after which seeding is locked.
    var hasPlayedAnyGame: Bool {
        matches.contains { $0.status != .setup && !$0.isBye }
    }

    /// The champion, once the final has a decided winner.
    func champion() -> Team? { finalMatch?.bracketWinner }

    // MARK: - Generation

    /// Create all bracket match games from the seeded teams. Round-0 slots get their teams (a slot
    /// with only one team is a bye). Later rounds start empty and fill as winners advance. Unless the
    /// tournament decides ties by hand, matches force extra innings so there's always a winner.
    func generateMatches(seededTeams: [Team], context: ModelContext) {
        for existing in Array(matches) { context.delete(existing) }   // snapshot: delete mutates `matches`

        let bracket = BracketBuilder.build(seededTeamNames: seededTeams.map(\.name))
        guard !bracket.isEmpty else { return }

        var matchSettings = settings
        if !decideTiesManually { matchSettings.extraInnings = true }

        func team(for slot: BracketSlot) -> Team? {
            if case .team(_, let name) = slot { return seededTeams.first { $0.name == name } }
            return nil
        }

        for bm in bracket.matches {
            let game = Game(status: .setup, settings: matchSettings)
            game.mode = .tournament
            game.tournament = self
            game.bracketRound = bm.round
            game.bracketSlot = bm.indexInRound
            if bm.round == 0 {
                game.homeTeam = team(for: bm.top)
                game.awayTeam = team(for: bm.bottom)
            }
            context.insert(game)
        }
        advanceWinners()
    }

    // MARK: - Advancement

    /// Push each decided winner into its parent slot, round by round. Idempotent — safe to run after
    /// every game and whenever the bracket appears. Flips status to `.final` once there's a champion.
    func advanceWinners() {
        guard totalRounds > 1 else {
            updateFinalStatus()
            return
        }
        for round in 0..<(totalRounds - 1) {
            let roundMatches = matches
                .filter { $0.bracketRound == round }
                .sorted { $0.bracketSlot < $1.bracketSlot }
            for m in roundMatches {
                guard let winner = m.bracketWinner,
                      let parent = match(round: round + 1, slot: m.bracketSlot / 2),
                      parent.status != .final   // don't disturb an already-played downstream match
                else { continue }
                if m.bracketSlot % 2 == 0 { parent.homeTeam = winner } else { parent.awayTeam = winner }
            }
        }
        updateFinalStatus()
    }

    private func updateFinalStatus() {
        if champion() != nil {
            if status != .final { status = .final }
        } else if status == .final {
            status = .inProgress   // a result was undone
        }
    }

    // MARK: - Display model

    /// The bracket to draw: a live, result-aware view once started; a seeded preview while in setup.
    func displayBracket(teams: [Team]) -> (rounds: Int, matches: [BracketDisplayMatch]) {
        let seeded = seededTeams(in: teams)
        let seedOf = Dictionary(uniqueKeysWithValues: seeded.enumerated().map { ($1.name, $0 + 1) })

        if status == .setup || matches.isEmpty {
            let b = BracketBuilder.build(seededTeamNames: seeded.map(\.name))
            let display = b.matches.map { bm in
                BracketDisplayMatch(
                    id: bm.round * 1000 + bm.indexInRound,
                    round: bm.round, indexInRound: bm.indexInRound,
                    top: previewSlot(bm.top), bottom: previewSlot(bm.bottom)
                )
            }
            return (b.rounds, display)
        }

        let display = matches
            .sorted { ($0.bracketRound, $0.bracketSlot) < ($1.bracketRound, $1.bracketSlot) }
            .map { gameDisplay($0, seedOf: seedOf) }
        return (totalRounds, display)
    }

    private func previewSlot(_ slot: BracketSlot) -> BracketDisplaySlot {
        switch slot {
        case .team(let seed, let name): return BracketDisplaySlot(name: name, seed: seed)
        case .bye:                       return BracketDisplaySlot(isBye: true)
        case .tbd:                       return BracketDisplaySlot()
        }
    }

    private func gameDisplay(_ game: Game, seedOf: [String: Int]) -> BracketDisplayMatch {
        let winner = game.bracketWinner
        let played = game.status == .final && game.homeTeam != nil && game.awayTeam != nil

        func slot(_ team: Team?, score: Int?) -> BracketDisplaySlot {
            if let team {
                return BracketDisplaySlot(name: team.name, seed: seedOf[team.name],
                                          score: score, isBye: false, isWinner: winner === team)
            }
            // Empty side: "Bye" only for a genuine round-0 bye, otherwise it's just waiting.
            return BracketDisplaySlot(isBye: game.isBye)
        }

        return BracketDisplayMatch(
            id: game.bracketRound * 1000 + game.bracketSlot,
            round: game.bracketRound, indexInRound: game.bracketSlot,
            top: slot(game.homeTeam, score: played ? game.homeScore : nil),
            bottom: slot(game.awayTeam, score: played ? game.awayScore : nil),
            isPlayable: game.isPlayableBracketMatch,
            gameID: (game.isPlayableBracketMatch || played) ? game.persistentModelID : nil
        )
    }
}

// MARK: - Match (Game) bracket helpers

extension Game {
    /// A round-0 slot with only one team (its opponent was a bye).
    var isBye: Bool { bracketRound == 0 && ((homeTeam == nil) != (awayTeam == nil)) }

    /// The team advancing from this bracket match, or nil if undecided.
    var bracketWinner: Team? {
        if isBye { return homeTeam ?? awayTeam }
        guard let home = homeTeam, let away = awayTeam, status == .final else { return nil }
        if homeScore > awayScore { return home }
        if awayScore > homeScore { return away }
        if let manual = manualTieWinnerIsHome { return manual ? home : away }
        return nil   // tie awaiting a manual pick
    }

    /// Both teams set and not finished — ready to play.
    var isPlayableBracketMatch: Bool {
        homeTeam != nil && awayTeam != nil && status != .final
    }

    /// A finished match that ended tied and still needs the tracker to choose who advances.
    var needsManualTieBreak: Bool {
        guard status == .final, homeTeam != nil, awayTeam != nil else { return false }
        return homeScore == awayScore && manualTieWinnerIsHome == nil
    }
}
