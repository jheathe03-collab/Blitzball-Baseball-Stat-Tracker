//
//  TournamentParticipantsView.swift
//  Blitzball Stat Tracker
//
//  Screen 2 of the tournament flow: the seeded participant list. Add teams (from the Teams pool),
//  reorder / remove, randomize the seeding, then View Bracket. Seeding is stored as the ordered
//  team names on the Tournament.
//

import SwiftUI
import SwiftData

struct TournamentParticipantsView: View {
    @Bindable var tournament: Tournament
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var allTeams: [Team]
    @State private var picking = false

    private var seeded: [Team] { tournament.seededTeams(in: allTeams) }

    var body: some View {
        List {
            Section {
                if seeded.isEmpty {
                    Text("No teams yet — add some below.")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(Array(seeded.enumerated()), id: \.element.persistentModelID) { index, team in
                        HStack(spacing: 10) {
                            Text("\(index + 1).")
                                .foregroundStyle(.white.opacity(0.5)).monospacedDigit()
                            TeamLogoView(logoName: team.logoName, size: 24)
                            Text(team.name).foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
            } header: {
                Text("Participants (seed order)").foregroundStyle(.white)
            } footer: {
                Text("Tap Edit to drag seeds or remove teams. Seed 1 is the top of the bracket.")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .blitzCardRow()

            Section {
                Button { picking = true } label: {
                    Label("Add Participant", systemImage: "plus")
                }
                if seeded.count >= 2 {
                    Button { randomize() } label: {
                        Label("Randomize Seeding", systemImage: "shuffle")
                    }
                }
            }
            .blitzCardRow()

            Section {
                NavigationLink {
                    GameSettingsEditor(settings: $tournament.settings)
                        .navigationTitle("Game Options")
                        .navigationBarTitleDisplayMode(.inline)
                        .blitzballBackground()
                } label: {
                    HStack {
                        Label("Game Options", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(tournament.settings.matchedType.displayName)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Toggle("Decide Ties Manually", isOn: $tournament.decideTiesManually)
            } header: {
                Text("Rules").foregroundStyle(.white)
            } footer: {
                Text("Applied to every match (each match can still override its own options). When ties are decided manually, a tied game lets you pick who advances; otherwise matches play extra innings until there's a winner.")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .blitzCardRow()

            if seeded.count >= 2 {
                Section {
                    NavigationLink {
                        TournamentBracketDisplayView(tournament: tournament)
                    } label: {
                        Label("View Bracket", systemImage: "trophy")
                    }
                }
                .blitzCardRow()
            }
        }
        .blitzListStyle()
        .navigationTitle("Participants")
        .navigationBarTitleDisplayMode(.inline)
        .blitzballBackground()
        .toolbar { EditButton() }
        .sheet(isPresented: $picking) {
            TeamPickerView(excluding: nil, excludingTeams: seeded, allowsMultiple: true,
                           onSelectMultiple: { add($0) })
        }
    }

    // Seed order is always rebuilt from the resolved `seeded` names — this also drops any stale
    // names (teams deleted since) so the list stays clean. New teams keep their tapped order.
    private func add(_ teams: [Team]) {
        tournament.appendSeeds(teams, currentlySeeded: seeded)
    }

    private func remove(at offsets: IndexSet) {
        var names = seeded.map(\.name)
        names.remove(atOffsets: offsets)
        tournament.seedOrder = names
    }

    private func move(from source: IndexSet, to destination: Int) {
        var names = seeded.map(\.name)
        names.move(fromOffsets: source, toOffset: destination)
        tournament.seedOrder = names
    }

    private func randomize() {
        tournament.seedOrder = seeded.map(\.name).shuffled()
    }
}
