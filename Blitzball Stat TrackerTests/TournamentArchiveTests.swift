//
//  TournamentArchiveTests.swift
//  Blitzball Stat TrackerTests
//
//  Format/version guard for the bracket archive (pure, no SwiftData). Full reconstruction is
//  verified by an end-to-end round trip in the app.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct TournamentArchiveTests {

    @Test func rejectsASeasonOrPlayerFile() throws {
        let seasonFile = Data(#"{"format":"blitzball.season-archive","version":1}"#.utf8)
        #expect(throws: TournamentImportError.self) {
            _ = try TournamentArchive.decoded(from: seasonFile)
        }
        let playerFile = Data(#"{"format":"blitzball.player-archive","version":1}"#.utf8)
        #expect(throws: TournamentImportError.self) {
            _ = try TournamentArchive.decoded(from: playerFile)
        }
    }

    @Test func rejectsAFutureVersion() throws {
        let future = TournamentArchive.currentVersion + 1
        let file = Data(#"{"format":"blitzball.tournament-archive","version":\#(future)}"#.utf8)
        #expect(throws: TournamentImportError.self) {
            _ = try TournamentArchive.decoded(from: file)
        }
    }

    @Test func rejectsGarbage() throws {
        #expect(throws: (any Error).self) {
            _ = try TournamentArchive.decoded(from: Data("nope".utf8))
        }
    }
}
