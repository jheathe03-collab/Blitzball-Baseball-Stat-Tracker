//
//  EditGameView.swift
//  Blitzball Stat Tracker
//
//  Post-hoc corrections: fix the inning-by-inning line score, and edit any player's raw counters
//  (both teams, including subbed-out players). Rate stats like AVG/ERA recompute automatically —
//  only the raw counts are editable.
//

import SwiftUI
import SwiftData

struct EditGameView: View {
    @Bindable var game: Game

    private var awayLines: [GameStatLine] {
        game.statLines.filter { !$0.isHome }.sorted { $0.battingOrder < $1.battingOrder }
    }
    private var homeLines: [GameStatLine] {
        game.statLines.filter { $0.isHome }.sorted { $0.battingOrder < $1.battingOrder }
    }

    var body: some View {
        List {
            // Editable line score (raw run override per inning).
            Section("Line Score — \(game.awayTeam?.name ?? "Away")") {
                ForEach(game.awayInningRuns.indices, id: \.self) { i in
                    Stepper("Inning \(i + 1): \(game.awayInningRuns[i])",
                            value: $game.awayInningRuns[i], in: 0...99)
                        .monospacedDigit()
                }
            }
            Section("Line Score — \(game.homeTeam?.name ?? "Home")") {
                ForEach(game.homeInningRuns.indices, id: \.self) { i in
                    Stepper("Inning \(i + 1): \(game.homeInningRuns[i])",
                            value: $game.homeInningRuns[i], in: 0...99)
                        .monospacedDigit()
                }
            }

            playersSection(title: game.awayTeam?.name ?? "Away", lines: awayLines)
            playersSection(title: game.homeTeam?.name ?? "Home", lines: homeLines)
        }
        .navigationTitle("Edit Stats & Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func playersSection(title: String, lines: [GameStatLine]) -> some View {
        if !lines.isEmpty {
            Section("Players — \(title)") {
                ForEach(lines) { line in
                    NavigationLink {
                        EditPlayerStatsView(line: line)
                    } label: {
                        HStack {
                            Text(line.player?.name ?? "—")
                            if !line.isActive {
                                Text("(out)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Per-player raw-stat editor

struct EditPlayerStatsView: View {
    @Bindable var line: GameStatLine

    var body: some View {
        Form {
            Section("Batting") {
                editStepper("Plate Appearances", $line.batting.plateAppearances)
                editStepper("At-Bats", $line.batting.atBats)
                editStepper("Hits", $line.batting.hits)
                editStepper("Doubles", $line.batting.doubles)
                editStepper("Triples", $line.batting.triples)
                editStepper("Home Runs", $line.batting.homeRuns)
                editStepper("Runs", $line.batting.runsScored)
                editStepper("RBI", $line.batting.rbi)
                editStepper("Walks", $line.batting.walks)
                editStepper("Hit By Pitch", $line.batting.hitByPitch)
                editStepper("Strikeouts", $line.batting.strikeouts)
                editStepper("Sacrifice Flies", $line.batting.sacrificeFlies)
            }
            Section("Pitching") {
                editStepper("Outs Recorded", $line.pitching.outsRecorded)
                editStepper("Runs Allowed", $line.pitching.runsAllowed)
                editStepper("Earned Runs", $line.pitching.earnedRuns)
                editStepper("Hits Allowed", $line.pitching.hitsAllowed)
                editStepper("HR Allowed", $line.pitching.homeRunsAllowed)
                editStepper("Walks Allowed", $line.pitching.walksAllowed)
                editStepper("Strikeouts", $line.pitching.strikeouts)
                editStepper("At-Bats Against", $line.pitching.atBatsAgainst)
                editStepper("Saves", $line.pitching.saves)
                editStepper("Quality Starts", $line.pitching.qualityStarts)
            }
        }
        .navigationTitle(line.player?.name ?? "Edit Player")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func editStepper(_ label: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...9999) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue)").monospacedDigit().bold()
            }
        }
    }
}
