//
//  ResumeExhibitionTests.swift
//  Blitzball Stat TrackerTests
//
//  The "Resume In Progress Game" finder on the Exhibition screen: it reopens an exhibition game that
//  was started but never finished, and must ignore setup drafts, finished games, and season/
//  tournament games (those resume from their own hubs).
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct ResumeExhibitionTests {

    private func game(mode: GameMode, status: GameStatus, createdAt: Date = .now) -> Game {
        let g = Game(createdAt: createdAt, status: status)
        g.mode = mode
        return g
    }

    @Test func findsAnInProgressExhibitionGame() {
        let live = game(mode: .exhibition, status: .inProgress)
        let found = Game.resumableExhibition(in: [live])
        #expect(found === live)
    }

    @Test func ignoresSetupDraftsAndFinishedGames() {
        let setup = game(mode: .exhibition, status: .setup)
        let final = game(mode: .exhibition, status: .final)
        #expect(Game.resumableExhibition(in: [setup, final]) == nil)
    }

    @Test func ignoresSeasonAndTournamentGames() {
        let season = game(mode: .season, status: .inProgress)
        let tournament = game(mode: .tournament, status: .inProgress)
        #expect(Game.resumableExhibition(in: [season, tournament]) == nil)
    }

    @Test func returnsTheMostRecentWhenSeveralPiledUp() {
        let older = game(mode: .exhibition, status: .inProgress,
                         createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = game(mode: .exhibition, status: .inProgress,
                         createdAt: Date(timeIntervalSince1970: 2_000))
        #expect(Game.resumableExhibition(in: [older, newer]) === newer)
        #expect(Game.resumableExhibition(in: [newer, older]) === newer)
    }

    @Test func noneWhenNothingToResume() {
        #expect(Game.resumableExhibition(in: []) == nil)
    }
}
