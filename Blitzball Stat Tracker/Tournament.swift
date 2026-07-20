//
//  Tournament.swift
//  Blitzball Stat Tracker
//
//  A single-elimination tournament bracket. Mirrors Season: a named event with a shared rulebook,
//  a set of participant teams (in SEED order), a status, and — later (Stage 2) — its bracket games.
//
//  Participants are stored as an ordered list of TEAM NAMES (names are unique). This deliberately
//  avoids a unidirectional Tournament→Team relationship, which would dangle and crash if a team were
//  deleted (the same class of bug we fixed for games). Resolving by name means a deleted team simply
//  drops out of the bracket gracefully. Once the bracket's match Games exist (Stage 2), those hold
//  real Team references and are covered by the existing team-deletion guard.
//

import Foundation
import SwiftData

enum TournamentStatus: String, Codable {
    case setup       // building the participant list / bracket
    case inProgress  // bracket started, playing through rounds
    case final       // champion decided
}

@Model
final class Tournament {
    var name: String
    /// The rulebook applied to the bracket's games (per-match overrides come later). JSON blob.
    var settingsData: Data
    /// When a game ends tied: false = force extra innings until a winner; true = ask who advances.
    var decideTiesManually: Bool = false
    var status: TournamentStatus
    var createdAt: Date
    /// Participant team names in SEED order (seed 1 = first). JSON blob.
    var seedOrderData: Data

    /// The bracket's match games (created when the bracket starts). Deleting the tournament deletes
    /// them (cascade). `Game.tournament` is the inverse.
    @Relationship(deleteRule: .cascade, inverse: \Game.tournament) var matches: [Game] = []

    init(
        name: String = "",
        settings: GameSettings = .blitzballDefaults,
        decideTiesManually: Bool = false,
        status: TournamentStatus = .setup,
        createdAt: Date = .now
    ) {
        self.name = name
        self.settingsData = BlobCoder.encode(settings)
        self.decideTiesManually = decideTiesManually
        self.status = status
        self.createdAt = createdAt
        self.seedOrderData = BlobCoder.encode([String]())
    }
}

extension Tournament {
    var settings: GameSettings {
        get { BlobCoder.decode(settingsData) ?? .blitzballDefaults }
        set { settingsData = BlobCoder.encode(newValue) }
    }

    /// Participant team names in seed order.
    var seedOrder: [String] {
        get { BlobCoder.decode(seedOrderData) ?? [] }
        set { seedOrderData = BlobCoder.encode(newValue) }
    }

    /// Resolve the seeded names to live Team objects (dropping any that no longer exist), in order.
    func seededTeams(in teams: [Team]) -> [Team] {
        seedOrder.compactMap { name in teams.first { $0.name == name } }
    }

    var displayName: String { name.isEmpty ? "Untitled Bracket" : name }
}
