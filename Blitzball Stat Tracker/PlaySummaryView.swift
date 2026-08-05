//
//  PlaySummaryView.swift
//  Blitzball Stat Tracker
//
//  The play-by-play log for one game — newest first, grouped by half-inning, so you can scroll back
//  and see exactly what happened when. Live, it also shows who's at bat right now.
//
//  Games played before the log existed have no entries; that's expected, not an error state.
//

import SwiftUI
import SwiftData

struct PlaySummaryView: View {
    @Bindable var game: Game
    /// Live games show the current batter at the top; a finished game doesn't.
    var showsCurrentActivity: Bool = true
    /// The play being corrected, if any.
    @State private var editing: PlayEvent?

    /// Newest first, so the most recent play is the one you land on.
    private var plays: [PlayEvent] {
        game.orderedPlays.reversed()
    }

    var body: some View {
        Group {
            if plays.isEmpty {
                ContentUnavailableView {
                    Label("No Plays Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text(game.status == .setup
                         ? "Plays appear here as the game is scored."
                         : "This game was played before the play log existed.")
                }
                .foregroundStyle(.white)
            } else {
                List {
                    if showsCurrentActivity, game.status == .inProgress {
                        Section {
                            currentActivity
                        } header: {
                            Text("Now").foregroundStyle(.white)
                        }
                        .blitzCardRow()
                    }
                    Section {
                        ForEach(plays) { play in
                            if play.isEditable {
                                Button { editing = play } label: { row(play) }
                                    .buttonStyle(.plain)
                            } else {
                                row(play)
                            }
                        }
                    } header: {
                        Text("Plays").foregroundStyle(.white)
                    }
                    .blitzCardRow()
                }
                .blitzListStyle()
            }
        }
        .navigationTitle("Play Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { play in
            EditPlayView(game: game, play: play)
        }
    }

    // MARK: - Rows

    private var currentActivity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(game.halfInningLabel) — \(game.battingTeam?.name ?? "Batting")")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Text("\(game.currentBatterLine?.player?.name ?? "—") at bat")
                .font(.headline).foregroundStyle(.white)
            if let pitcher = game.activePitcher?.name {
                Text("\(pitcher) pitching · \(game.outs) out\(game.outs == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func row(_ play: PlayEvent) -> some View {
        switch play.kind {
        case .gameStart, .inningChange:
            // Structural markers read as dividers rather than plays.
            HStack {
                Text(play.kind == .gameStart ? "Game Start" : play.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
        default:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(play.title)
                        .font(.headline).foregroundStyle(.white)
                    if play.outsBefore > 0 || play.outcome?.isOut == true {
                        Text("·").foregroundStyle(.white.opacity(0.35))
                        Text("\(play.outsBefore) out\(play.outsBefore == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    if play.isEditable {
                        Text("Edit")
                            .font(.caption).foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(play.halfInningLabel)
                            .font(.caption).foregroundStyle(.white.opacity(0.45))
                            .monospacedDigit()
                        // Only plays that put runs on the board show a score, so the column stays
                        // quiet until something actually changed it.
                        if play.runsScored > 0 {
                            scoreBadge(play)
                        }
                    }
                }
                Text(play.summary)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// The running score as of this play, away–home, matching how the line score reads.
    private func scoreBadge(_ play: PlayEvent) -> some View {
        Text("\(play.awayScore)–\(play.homeScore)")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.green.opacity(0.28), in: Capsule())
    }
}
