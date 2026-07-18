//
//  SeasonArchiveTests.swift
//  Blitzball Stat TrackerTests
//
//  Tests for the season archive's format/version guard — the safety net that stops the wrong file
//  (e.g. a player export, or a newer app's export) from being imported as a season. The full
//  reconstruction (apply → rebuilt Season/Games/stats) is verified by an end-to-end round trip in
//  the app, since a SwiftData ModelContainer can't be spun up inside this app-hosted test bundle.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct SeasonArchiveTests {

    /// A player-archive JSON (or any non-season file) must be rejected with the friendly error.
    @Test func rejectsAPlayerArchiveFile() throws {
        let playerFile = Data(#"{"format":"blitzball.player-archive","version":1}"#.utf8)
        #expect(throws: SeasonImportError.self) {
            _ = try SeasonArchive.decoded(from: playerFile)
        }
    }

    /// A season file from a NEWER app version (higher format version) must be rejected, not
    /// half-imported.
    @Test func rejectsAFutureVersion() throws {
        let future = SeasonArchive.currentVersion + 1
        let futureFile = Data(#"{"format":"blitzball.season-archive","version":\#(future)}"#.utf8)
        #expect(throws: SeasonImportError.self) {
            _ = try SeasonArchive.decoded(from: futureFile)
        }
    }

    /// Garbage / non-JSON is rejected (throws something) rather than silently succeeding.
    @Test func rejectsGarbage() throws {
        let junk = Data("not a json file".utf8)
        #expect(throws: (any Error).self) {
            _ = try SeasonArchive.decoded(from: junk)
        }
    }
}
