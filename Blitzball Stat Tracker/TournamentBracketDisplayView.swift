//
//  TournamentBracketDisplayView.swift
//  Blitzball Stat Tracker
//
//  The bracket screen. Before Start: a seeded preview you can rename / randomize / extend. After
//  Start: the live bracket — tap a ready match to play it, winners advance automatically (byes too),
//  and the champion is crowned when the final resolves. Seeding stays editable until the first game.
//

import SwiftUI
import SwiftData

struct TournamentBracketDisplayView: View {
    @Bindable var tournament: Tournament
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var allTeams: [Team]

    @State private var picking = false
    @State private var showStartConfirm = false
    @State private var activeGame: Game?
    @State private var tieMatch: Game?

    private var seeded: [Team] { tournament.seededTeams(in: allTeams) }
    private var champion: Team? { tournament.champion() }
    private var editable: Bool { !tournament.hasPlayedAnyGame }
    private var isSetup: Bool { tournament.status == .setup }

    var body: some View {
        let display = tournament.displayBracket(teams: allTeams)

        VStack(spacing: 12) {
            TextField("", text: $tournament.name,
                      prompt: Text("Bracket Name").foregroundStyle(.white.opacity(0.4)))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 8)

            if let champion {
                championBanner(champion)
            }

            BracketView(rounds: display.rounds, matches: display.matches, onTap: openMatch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
        }
        .navigationTitle("Bracket")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .onAppear {
            if !isSetup { tournament.advanceWinners(); findPendingTie() }
        }
        .navigationDestination(item: $activeGame) { game in
            if game.isPlayableBracketMatch {
                TournamentMatchPregameView(game: game, onExit: { activeGame = nil })
            } else {
                GameSummaryView(game: game, onBackToBracket: { activeGame = nil })
            }
        }
        .sheet(isPresented: $picking) {
            TeamPickerView(excluding: nil, excludingTeams: seeded, allowsMultiple: true,
                           onSelectMultiple: { extend(with: $0) })
        }
        .alert("Start Bracket?", isPresented: $showStartConfirm) {
            Button("Start Bracket") { startBracket() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Lock in these \(seeded.count) teams and begin. You can still adjust seeding until the first game is played.")
        }
        .alert("Who Advances?", isPresented: tieAlert, presenting: tieMatch) { match in
            Button(match.homeTeam?.name ?? "Home") { resolveTie(match, homeWins: true) }
            Button(match.awayTeam?.name ?? "Away") { resolveTie(match, homeWins: false) }
        } message: { match in
            Text("\(match.homeTeam?.name ?? "Home") and \(match.awayTeam?.name ?? "Away") tied. Choose who moves on.")
        }
    }

    // MARK: - Champion

    private func championBanner(_ team: Team) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
            TeamLogoView(logoName: team.logoName, size: 28)
            Text("\(team.name) — Champion!")
                .font(.headline).foregroundStyle(.white)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(.yellow.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(.yellow.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            if editable {
                HStack(spacing: 12) {
                    Button {
                        tournament.seedOrder = seeded.map(\.name).shuffled()
                        onSeedingChanged()
                    } label: {
                        Label("Randomize", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.white)

                    Button { picking = true } label: {
                        Label("Extend Bracket", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if isSetup {
                Button { showStartConfirm = true } label: {
                    Label("Start Bracket", systemImage: "play.fill")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(seeded.count < 2)
            } else if champion == nil {
                Text("Tap a highlighted match to play it.")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func startBracket() {
        tournament.generateMatches(seededTeams: seeded, context: modelContext)
        tournament.status = .inProgress
    }

    /// Seeding changed while editable: if the bracket has already been generated, rebuild it.
    private func onSeedingChanged() {
        if !isSetup { tournament.generateMatches(seededTeams: seeded, context: modelContext) }
    }

    private func extend(with teams: [Team]) {
        var names = seeded.map(\.name)
        for team in teams where !names.contains(team.name) { names.append(team.name) }
        tournament.seedOrder = names
        onSeedingChanged()
    }

    private func openMatch(_ id: PersistentIdentifier) {
        activeGame = tournament.matches.first { $0.persistentModelID == id }
    }

    private func findPendingTie() {
        tieMatch = tournament.matches.first { $0.needsManualTieBreak }
    }

    private func resolveTie(_ match: Game, homeWins: Bool) {
        match.manualTieWinnerIsHome = homeWins
        tournament.advanceWinners()
        tieMatch = nil
        findPendingTie()   // in case more than one tie is pending
    }

    private var tieAlert: Binding<Bool> {
        Binding(get: { tieMatch != nil }, set: { if !$0 { tieMatch = nil } })
    }
}
