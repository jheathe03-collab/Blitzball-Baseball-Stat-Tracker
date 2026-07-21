//
//  TournamentMatchPregameView.swift
//  Blitzball Stat Tracker
//
//  Pre-game for one bracket match — the tournament cousin of WeekPregameView. The two teams are
//  fixed by the bracket; here you set each side's batting order + starting pitcher (or rotation) and
//  the DH, tweak Game Options, then Play Ball. The winner advances back on the bracket screen.
//

import SwiftUI
import SwiftData

struct TournamentMatchPregameView: View {
    @Bindable var game: Game
    /// Pops back to the bracket after the match (threaded to the finished box score).
    var onExit: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var showingDHPicker = false
    @State private var showStartConfirm = false
    @State private var startGame = false
    @State private var showPitcherWarning = false

    private var ready: Bool {
        (game.homeTeam?.players.isEmpty == false) && (game.awayTeam?.players.isEmpty == false)
    }

    private var roundLabel: String {
        game.tournament?.roundName(game.bracketRound) ?? "Round \(game.bracketRound + 1)"
    }

    private var pitcherWarningMessage: String {
        var missing: [String] = []
        if game.homePitcher == nil { missing.append(game.homeTeam?.name ?? "the home team") }
        if game.awayPitcher == nil { missing.append(game.awayTeam?.name ?? "the away team") }
        let teams = missing.joined(separator: " and ")
        let what = game.settings.forcePitcherRotation ? "pitching rotation" : "starting pitcher"
        return "Set a \(what) for \(teams) before starting the game."
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text(roundLabel)
                        .font(.headline).foregroundStyle(.secondary)
                    Text("\(game.homeTeam?.name ?? "Home") vs \(game.awayTeam?.name ?? "Away")")
                        .font(.title3).bold().multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            teamSection(isHome: true)
            teamSection(isHome: false)

            if game.settings.designatedHitter {
                Section("Designated Hitter") {
                    if let dh = game.designatedHitter {
                        HStack {
                            Label(dh.name, systemImage: "star.fill")
                            Spacer()
                            Button("Clear") { game.designatedHitter = nil; syncLineups() }
                                .foregroundStyle(.red)
                        }
                    }
                    Button { showingDHPicker = true } label: {
                        Label(game.designatedHitter == nil ? "Select Designated Hitter" : "Change Designated Hitter",
                              systemImage: "person.badge.plus")
                    }
                }
            }

            Section {
                NavigationLink {
                    GameOptionsView(game: game)
                } label: {
                    HStack {
                        Label("Game Options", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(game.settings.matchedType.displayName)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
            } footer: {
                Text("Rules for this match only.").foregroundStyle(.white.opacity(0.6))
            }

            Section {
                Button {
                    if game.homePitcher == nil || game.awayPitcher == nil {
                        showPitcherWarning = true
                    } else {
                        showStartConfirm = true
                    }
                } label: {
                    Label("Play Ball", systemImage: "play.fill").fontWeight(.semibold)
                }
                .disabled(!ready)
            } footer: {
                if !ready {
                    Text("Both teams need at least one player. Edit a team's roster first.")
                }
            }
        }
        .navigationTitle("Match Setup")
        .blitzballBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDHPicker) {
            DesignatedHitterPicker(game: game)
        }
        .navigationDestination(isPresented: $startGame) {
            LiveGameView(game: game, onExit: onExit)
        }
        .alert("Ready to Play Ball?", isPresented: $showStartConfirm) {
            Button("Play Ball") { startGame = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Start the \(roundLabel): \(game.homeTeam?.name ?? "Home") vs \(game.awayTeam?.name ?? "Away").")
        }
        .alert("Set a Starting Pitcher", isPresented: $showPitcherWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pitcherWarningMessage)
        }
        .onAppear { syncLineups() }
    }

    @ViewBuilder
    private func teamSection(isHome: Bool) -> some View {
        let team = isHome ? game.homeTeam : game.awayTeam
        let pitcher = isHome ? game.homePitcher : game.awayPitcher
        let lineup = game.teamLineup(isHome: isHome).compactMap(\.player)

        Section(isHome ? "Home" : "Away") {
            HStack {
                TeamLogoView(team: team, size: 32)
                Text(team?.name ?? "—").font(.title3).bold()
                Spacer()
                Text("\(lineup.count) player\(lineup.count == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }

            NavigationLink {
                BattingOrderView(game: game, isHome: isHome)
            } label: {
                Label("Batting Order", systemImage: "figure.baseball")
            }

            if game.settings.forcePitcherRotation {
                NavigationLink {
                    PitchingRotationView(game: game, isHome: isHome)
                } label: {
                    HStack {
                        Label("Pitching Rotation", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(rotationLabel(isHome: isHome))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
            } else {
                NavigationLink {
                    StartingPitcherView(game: game, isHome: isHome)
                } label: {
                    HStack {
                        Label("Starting Pitcher", systemImage: "baseball.fill")
                        Spacer()
                        Text(pitcher?.name ?? "Not set")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func rotationLabel(isHome: Bool) -> String {
        let count = game.pitchingRotation(isHome: isHome).count
        return count == 0 ? "Not set" : "\(count) pitcher\(count == 1 ? "" : "s")"
    }

    private func syncLineups() {
        game.syncLineup(isHome: true, using: modelContext)
        game.syncLineup(isHome: false, using: modelContext)
        game.syncDesignatedHitter(using: modelContext)
    }
}
