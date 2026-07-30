//
//  CardCarouselEntry.swift
//  Blitzball Stat Tracker
//
//  The data behind the card carousel: the league flattened into ONE ordered list of cards, grouped
//  by team. Deliberately contains no SwiftUI at all — it's plain values and one sorting function, so
//  the ordering can be reasoned about (and tested) without rendering anything.
//

import Foundation
import SwiftData

/// One card in the carousel: a player, the team they're filed under, and which group that is.
///
/// `groupIndex` exists so the team header knows when to cross-fade. It changes by exactly 1 at each
/// team boundary, which means the header can animate off a cheap `Int` comparison instead of
/// comparing `Team` objects on every frame of a drag.
struct CardEntry: Identifiable {
    /// SwiftData's stable per-object ID. Using this (rather than array position) as the SwiftUI
    /// identity means a card keeps its identity even if the list is rebuilt after an edit.
    let id: PersistentIdentifier
    let player: Player
    /// nil means "not on any team" — a Free Agent.
    let team: Team?
    let groupIndex: Int
    /// The team's name, or "Free Agents".
    let groupTitle: String
    let template: CardTemplateID
    let identity: CardIdentity
}

/// Everything about a player that can change what their card actually DRAWS.
///
/// Why this exists: the carousel gates card redraws on `Equatable` (see `CarouselCardFace` in
/// CardCarouselStack) so that dragging the fan — which changes only position and scale — doesn't
/// re-run an expensive template body 60 times a second. But `Player` is a class, so comparing two
/// `Player` references would say "equal" even after you changed the photo, and the card would never
/// repaint. Capturing the drawable fields as a *value* fixes that.
///
/// IMPORTANT: if a template ever starts drawing something not listed here (career stats on the
/// front, say), add it to this struct — otherwise editing it won't repaint the carousel.
struct CardIdentity: Equatable {
    let modelID: PersistentIdentifier
    let name: String
    let jersey: Int?
    let template: String?
    /// A cheap stand-in for "the photo changed" — comparing the actual `Data` would mean hashing
    /// tens of kilobytes on every comparison, and a re-crop essentially never lands on the exact
    /// same byte count.
    let photoByteCount: Int
    let teamName: String?
    let teamLogo: String?
    let teamLogoByteCount: Int

    init(_ player: Player) {
        modelID = player.persistentModelID
        name = player.name
        jersey = player.jerseyNumber
        template = player.cardTemplate
        photoByteCount = player.photoData?.count ?? 0
        // `.first` is the established idiom across the card templates: the app enforces one team per
        // player, even though the model relationship allows many.
        let team = player.teams.first
        teamName = team?.name
        teamLogo = team?.logoName
        teamLogoByteCount = team?.logoImageData?.count ?? 0
    }
}

/// Builds the carousel's ordered card list. Namespaced in an enum (rather than free functions) to
/// keep `build` and its helper together without needing an instance of anything.
enum CardCarouselEntry {

    /// The label for the final group — players who aren't on any team yet.
    static let freeAgentsTitle = "Free Agents"

    /// Orders the league for the carousel: team-name alphabetical, then player name within each
    /// team, with unrostered players collected into a final "Free Agents" group.
    ///
    /// Teams are bucketed by their persistent ID rather than by name, so two teams that happen to
    /// share a name stay separate groups instead of silently merging. The tie-break on ID in the
    /// sort keeps the order stable (rather than random) when names DO match.
    static func build(from players: [Player]) -> [CardEntry] {
        var rostered: [PersistentIdentifier: (team: Team, players: [Player])] = [:]
        var freeAgents: [Player] = []

        for player in players {
            if let team = player.teams.first {
                rostered[team.persistentModelID, default: (team, [])].players.append(player)
            } else {
                freeAgents.append(player)
            }
        }

        let orderedTeams = rostered.values.sorted { left, right in
            left.team.name == right.team.name
                ? left.team.persistentModelID.hashValue < right.team.persistentModelID.hashValue
                : left.team.name < right.team.name
        }

        var entries: [CardEntry] = []
        var group = 0
        for bucket in orderedTeams {
            for player in bucket.players.sorted(by: { $0.name < $1.name }) {
                entries.append(make(player, team: bucket.team, group: group, title: bucket.team.name))
            }
            group += 1
        }
        for player in freeAgents.sorted(by: { $0.name < $1.name }) {
            entries.append(make(player, team: nil, group: group, title: freeAgentsTitle))
        }
        return entries
    }

    private static func make(_ player: Player, team: Team?, group: Int, title: String) -> CardEntry {
        CardEntry(
            id: player.persistentModelID,
            player: player,
            team: team,
            groupIndex: group,
            groupTitle: title,
            // Same fallback the rest of the card code uses: an unset or unrecognised template
            // rawValue means Classic.
            template: CardTemplateID(rawValue: player.cardTemplate ?? "") ?? .classic,
            identity: CardIdentity(player)
        )
    }
}
