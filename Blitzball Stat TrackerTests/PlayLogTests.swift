//
//  PlayLogTests.swift
//  Blitzball Stat TrackerTests
//
//  The play-by-play log: ordering, the state captured with each entry, and the prose it renders.
//
//  The ordering guarantee matters because plays are logged from two different places (the
//  synchronous path and the terminal step of the ghost-runners-off resolver), and the captured
//  inning/outs matter because recording a play advances the batter and can roll the half-inning —
//  so an entry written from the post-play state would describe the wrong moment.
//

import Testing
import Foundation
@testable import Blitzball_Stat_Tracker

struct PlayLogTests {

    private func makeGame() -> (game: Game, batter: Player, pitcher: Player) {
        let home = Team(name: "Sluggers")
        let away = Team(name: "Mashers")
        let game = Game(homeTeam: home, awayTeam: away)
        game.status = .inProgress
        game.currentInning = 1
        game.isTopInning = true
        game.homeInningRuns = [0]
        game.awayInningRuns = [0]
        return (game, Player(name: "Sam"), Player(name: "Darrin"))
    }

    @Test func sequenceIncrementsAndOrdersTheLog() throws {
        let f = makeGame()
        f.game.logPlay(.gameStart, detail: "Mashers at Sluggers")
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)
        f.game.logPlay(.plateAppearance, outcome: .strikeout, batter: f.batter, pitcher: f.pitcher)

        let ordered = f.game.orderedPlays
        #expect(ordered.map(\.sequence) == [0, 1, 2])
        #expect(ordered.first?.kind == .gameStart)
        #expect(ordered.last?.outcome == .strikeout)
    }

    /// The log must record where the game WAS, not where it ended up — a play that ends a
    /// half-inning would otherwise be filed under the next one.
    @Test func capturesTheStatePassedInNotTheCurrentState() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .out, batter: f.batter, pitcher: f.pitcher,
                       inning: 3, isTop: false, outs: 2)

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.inning == 3)
        #expect(play.isTopInning == false)
        #expect(play.outsBefore == 2)
        #expect(play.halfInningLabel == "Bot 3")
    }

    /// With nothing passed, it falls back to the game's current state.
    @Test func defaultsToTheGamesCurrentState() throws {
        let f = makeGame()
        f.game.currentInning = 5
        f.game.isTopInning = false
        f.game.outs = 1
        f.game.logPlay(.steal, batter: f.batter, detail: "Sam steals a base.")

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.inning == 5)
        #expect(play.outsBefore == 1)
        #expect(play.halfInningLabel == "Bot 5")
    }

    /// Plate-appearance prose is generated from the outcome, so re-classifying a play later will
    /// update its description too rather than leaving stale text behind.
    @Test func plateAppearanceProseIsGenerated() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.title == "Single")
        #expect(play.summary == "Sam hits a single. Darrin pitching.")
        #expect(play.isEditable)
    }

    /// A batted ball's contact type and location fold into the prose as their own sentence, between
    /// the outcome and the pitcher.
    @Test func battedBallDetailAppearsInProse() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .single,
                       battedBallType: .groundBall, fieldPosition: .shortstop,
                       batter: f.batter, pitcher: f.pitcher)

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.summary == "Sam hits a single. Ground ball to shortstop. Darrin pitching.")
    }

    /// In-play outs read the same way — "is out" plus how and where it was fielded.
    @Test func battedOutDetailAppearsInProse() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .out,
                       battedBallType: .flyBall, fieldPosition: .leftField,
                       batter: f.batter, pitcher: f.pitcher)

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.summary == "Sam is out. Fly ball to left field. Darrin pitching.")
    }

    /// Errors and fielder's choices carry the fielder (not a contact type), and read it inline —
    /// "reaches on an error by the shortstop" — using the fielder's name, not the base's.
    @Test func reachedOnMisplayNamesTheFielderInProse() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .reachedOnError, fieldPosition: .shortstop,
                       batter: f.batter, pitcher: f.pitcher)
        f.game.logPlay(.plateAppearance, outcome: .fieldersChoice, fieldPosition: .secondBase,
                       batter: f.batter, pitcher: f.pitcher)

        let plays = f.game.orderedPlays
        #expect(plays[plays.count - 2].summary == "Sam reaches on an error by the shortstop. Darrin pitching.")
        #expect(plays[plays.count - 1].summary == "Sam reaches on a fielder's choice by the second baseman. Darrin pitching.")
    }

    /// Non-plate-appearance events keep the text captured when they happened.
    @Test func otherEventsKeepTheirCapturedDetail() throws {
        let f = makeGame()
        f.game.logPlay(.pitchingChange, pitcher: f.pitcher,
                       detail: "Darrin replaces Kelsie pitching.")

        let play = try #require(f.game.orderedPlays.last)
        #expect(play.title == "Pitching Change")
        #expect(play.summary == "Darrin replaces Kelsie pitching.")
        #expect(play.isEditable == false)   // only plate appearances can be re-classified
    }

    /// Every outcome renders a label and a readable sentence — no "Optional(…)" or empty strings.
    @Test func everyOutcomeRendersProse() throws {
        let f = makeGame()
        for outcome in PlateAppearanceOutcome.allCases {
            f.game.logPlay(.plateAppearance, outcome: outcome, batter: f.batter, pitcher: f.pitcher)
        }
        for play in f.game.orderedPlays {
            #expect(!play.title.isEmpty)
            #expect(play.summary.hasPrefix("Sam "))
            #expect(play.summary.hasSuffix("Darrin pitching."))
        }
    }

    /// A game played before the log existed simply has no entries — not an error.
    @Test func gameWithNoLogIsEmpty() throws {
        let f = makeGame()
        #expect(f.game.orderedPlays.isEmpty)
    }

    /// A scoring play captures the score AS OF that play. Later runs must not rewrite it — the whole
    /// point is being able to read back what the score was at each moment.
    @Test func scoringPlayCapturesTheRunningScore() throws {
        let f = makeGame()
        f.game.awayInningRuns = [1]                       // 1–0 away
        f.game.logPlay(.manualRun, batter: f.batter, detail: "Sam scores.", runsScored: 1)

        f.game.awayInningRuns = [3]                       // two more score later
        f.game.logPlay(.manualRun, batter: f.batter, detail: "Ian scores.", runsScored: 1)

        let plays = f.game.orderedPlays
        #expect(plays[0].awayScore == 1)                  // frozen at the earlier moment
        #expect(plays[0].homeScore == 0)
        #expect(plays[1].awayScore == 3)
    }

    /// Plays that don't score anything carry runsScored 0, so the summary shows no score badge.
    @Test func nonScoringPlayHasNoRuns() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .strikeout, batter: f.batter, pitcher: f.pitcher)
        #expect(f.game.orderedPlays.last?.runsScored == 0)
    }

    // MARK: - Undo

    /// Undo has to take the play back out of the log too, or the summary keeps describing a play the
    /// game no longer counts.
    @Test func undoRemovesThePlayItLogged() throws {
        let f = makeGame()
        f.game.logPlay(.gameStart, detail: "Mashers at Sluggers")

        let snapshot = f.game.snapshot()          // taken BEFORE the play, as `perform` does
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)
        #expect(f.game.orderedPlays.count == 2)

        f.game.restore(from: snapshot)
        #expect(f.game.orderedPlays.count == 1)
        #expect(f.game.orderedPlays.last?.kind == .gameStart)
    }

    /// Undoing must not eat entries that were already there — only what the undone action added.
    @Test func undoKeepsEarlierPlays() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)
        f.game.logPlay(.plateAppearance, outcome: .double, batter: f.batter, pitcher: f.pitcher)

        let snapshot = f.game.snapshot()
        f.game.logPlay(.plateAppearance, outcome: .strikeout, batter: f.batter, pitcher: f.pitcher)
        f.game.restore(from: snapshot)

        #expect(f.game.orderedPlays.map(\.outcome) == [.single, .double])
    }

    /// Undoing back to an empty log clears it — the very first play of a game is undoable too.
    @Test func undoToEmptyLogClearsIt() throws {
        let f = makeGame()
        let snapshot = f.game.snapshot()          // nothing logged yet
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)
        f.game.restore(from: snapshot)

        #expect(f.game.orderedPlays.isEmpty)
    }

    /// After an undo the next play reuses the freed sequence number, so ordering stays contiguous
    /// rather than leaving a gap that later sorting could trip over.
    @Test func sequenceIsReusedAfterUndo() throws {
        let f = makeGame()
        f.game.logPlay(.plateAppearance, outcome: .single, batter: f.batter, pitcher: f.pitcher)
        let snapshot = f.game.snapshot()
        f.game.logPlay(.plateAppearance, outcome: .double, batter: f.batter, pitcher: f.pitcher)
        f.game.restore(from: snapshot)
        f.game.logPlay(.plateAppearance, outcome: .triple, batter: f.batter, pitcher: f.pitcher)

        #expect(f.game.orderedPlays.map(\.sequence) == [0, 1])
        #expect(f.game.orderedPlays.last?.outcome == .triple)
    }
}
