//
//  PlayerPhotoArchiveTests.swift
//  Blitzball Stat TrackerTests
//
//  Verifies that a player's card photo survives the export → JSON → import serialization round trip
//  in both archive formats, and that older (photo-less) files still decode. The import's apply step
//  is a plain assignment (mirrors battingStance) and is covered by the in-app end-to-end round trip.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct PlayerPhotoArchiveTests {

    /// Stand-in "photo" bytes (a JPEG header is enough — we only care they round-trip losslessly).
    private let samplePhoto = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])

    /// Season archive: a player's photo survives encode → decode, and is really embedded as base64.
    @Test func photoSurvivesSeasonRoundTrip() throws {
        let dto = SeasonArchive.PlayerDTO(
            name: "Chipper", jerseyNumber: 10,
            dateAdded: Date(timeIntervalSince1970: 0),
            battingStance: "RH", photoData: samplePhoto
        )
        let data = try SeasonArchive.jsonEncoder.encode(dto)
        let decoded = try SeasonArchive.jsonDecoder.decode(SeasonArchive.PlayerDTO.self, from: data)

        #expect(decoded.photoData == samplePhoto)
        // The bytes are actually carried in the JSON (base64), not dropped. Foundation's JSONEncoder
        // escapes "/" as "\/", so un-escape before matching the base64 string.
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        #expect(json.contains(samplePhoto.base64EncodedString()))
    }

    /// Player archive: same round trip through PlayerInfo.
    @Test func photoSurvivesPlayerRoundTrip() throws {
        let info = PlayerArchive.PlayerInfo(
            name: "Chipper", jerseyNumber: 10, battingStance: "RH", photoData: samplePhoto
        )
        let data = try PlayerArchive.jsonEncoder.encode(info)
        let decoded = try PlayerArchive.jsonDecoder.decode(PlayerArchive.PlayerInfo.self, from: data)

        #expect(decoded.photoData == samplePhoto)
    }

    /// Backward compatibility: a file written before photos existed (no `photoData` key) decodes
    /// cleanly with a nil photo — it must not fail the whole player.
    @Test func olderFileWithoutPhotoDecodes() throws {
        let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
        let legacy = Data(#"{"name":"NoPhoto","jerseyNumber":7,"dateAdded":"\#(iso)"}"#.utf8)

        let decoded = try SeasonArchive.jsonDecoder.decode(SeasonArchive.PlayerDTO.self, from: legacy)
        #expect(decoded.name == "NoPhoto")
        #expect(decoded.photoData == nil)
    }
}
