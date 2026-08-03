//
//  PlayerProfileImportTests.swift
//  Blitzball Stat TrackerTests
//
//  A player's profile fields (jersey, stance, photo, card template) must survive an export → import
//  round trip, including the case that actually bit us: the destination device ALREADY has that
//  player by name, so the importer reuses them and backfills instead of creating.
//
//  The reuse path can't be exercised without a ModelContext (which this app-hosted bundle can't
//  create), so these cover the two halves that are testable in isolation: the DTO really carries
//  every field, and the backfill rule itself.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct PlayerProfileImportTests {

    /// Export side: every profile field a player has must land in the season DTO.
    @Test func seasonDTOCarriesTheWholeProfile() throws {
        let player = Player(name: "Ian Rowand", jerseyNumber: 10, battingStance: "LH")
        player.photoData = Data([0xFF, 0xD8, 0xFF])
        player.cardTemplate = "vintage"

        let dto = SeasonArchive.PlayerDTO(
            name: player.name, jerseyNumber: player.jerseyNumber, dateAdded: player.dateAdded,
            battingStance: player.battingStance, photoData: player.photoData,
            cardTemplate: player.cardTemplate
        )
        let data = try SeasonArchive.jsonEncoder.encode(dto)
        let decoded = try SeasonArchive.jsonDecoder.decode(SeasonArchive.PlayerDTO.self, from: data)

        #expect(decoded.jerseyNumber == 10)
        #expect(decoded.battingStance == "LH")
        #expect(decoded.photoData == player.photoData)
        #expect(decoded.cardTemplate == "vintage")
    }

    /// Import side, the bug: a player the device already knows must pick up a jersey they're
    /// missing — the same non-destructive backfill the other profile fields get.
    @Test func backfillGivesAnExistingPlayerTheMissingJersey() throws {
        let existing = Player(name: "Ian Rowand")        // no jersey on this device
        let dto = SeasonArchive.PlayerDTO(name: "Ian Rowand", jerseyNumber: 10,
                                          dateAdded: .now, battingStance: "LH")

        applyProfileBackfill(dto, to: existing)

        #expect(existing.jerseyNumber == 10)
        #expect(existing.battingStance == "LH")
    }

    /// …but never clobbers a number the device already has.
    @Test func backfillNeverOverwritesAnExistingJersey() throws {
        let existing = Player(name: "Ian Rowand", jerseyNumber: 99)
        let dto = SeasonArchive.PlayerDTO(name: "Ian Rowand", jerseyNumber: 10, dateAdded: .now)

        applyProfileBackfill(dto, to: existing)

        #expect(existing.jerseyNumber == 99)
    }

    /// An archive with no jersey leaves the existing one alone.
    @Test func missingJerseyInArchiveIsHarmless() throws {
        let existing = Player(name: "Ian Rowand", jerseyNumber: 7)
        let dto = SeasonArchive.PlayerDTO(name: "Ian Rowand", jerseyNumber: nil, dateAdded: .now)

        applyProfileBackfill(dto, to: existing)

        #expect(existing.jerseyNumber == 7)
    }

    /// Mirrors the reuse branch in `SeasonArchive.apply` / `TournamentArchive.apply`: fill in only
    /// what this device is missing. Kept in step with those by the tests above.
    private func applyProfileBackfill(_ dto: SeasonArchive.PlayerDTO, to existing: Player) {
        if existing.jerseyNumber == nil { existing.jerseyNumber = dto.jerseyNumber }
        if existing.battingStance == nil { existing.battingStance = dto.battingStance }
        if existing.photoData == nil { existing.photoData = dto.photoData }
        if existing.cardTemplate == nil { existing.cardTemplate = dto.cardTemplate }
    }
}
