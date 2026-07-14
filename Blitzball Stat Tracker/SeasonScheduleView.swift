//
//  SeasonScheduleView.swift
//  Blitzball Stat Tracker
//
//  The weekly schedule: one matchup per week. Edit each week to set its two teams (and rosters).
//

import SwiftUI
import SwiftData

struct SeasonScheduleView: View {
    @Bindable var season: Season
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(season.weeks) { game in
                    NavigationLink {
                        WeekMatchupView(game: game)
                    } label: {
                        HStack {
                            Text("Week \(game.weekNumber)").bold()
                            Spacer()
                            Text(matchupText(game))
                                .foregroundStyle(isSet(game) ? .primary : .secondary)
                        }
                    }
                }
            }

            Section {
                Button("Save Schedule") { dismiss() }
            }
        }
        .navigationTitle("Season Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { season.syncSchedule(using: modelContext) }
    }

    private func isSet(_ game: Game) -> Bool {
        game.homeTeam != nil && game.awayTeam != nil
    }

    private func matchupText(_ game: Game) -> String {
        if let home = game.homeTeam?.name, let away = game.awayTeam?.name {
            return "\(home) vs \(away)"
        }
        return "Not set"
    }
}

// MARK: - Edit one week's matchup

struct WeekMatchupView: View {
    @Bindable var game: Game
    @State private var picking: TeamRole?

    var body: some View {
        List {
            teamSection(role: .home, team: game.homeTeam)
            teamSection(role: .away, team: game.awayTeam)
        }
        .navigationTitle("Week \(game.weekNumber)")
        .navigationBarTitleDisplayMode(.inline)
        // Reuses TeamRole (home/away) + TeamPickerView from the exhibition flow.
        .sheet(item: $picking) { role in
            TeamPickerView(excluding: role == .home ? game.awayTeam : game.homeTeam) { team in
                if role == .home { game.homeTeam = team } else { game.awayTeam = team }
            }
        }
    }

    @ViewBuilder
    private func teamSection(role: TeamRole, team: Team?) -> some View {
        Section(role.title) {
            Button {
                picking = role
            } label: {
                HStack {
                    Text(team?.name ?? "Select Team")
                        .foregroundStyle(team == nil ? Color.accentColor : .primary)
                    Spacer()
                    if team != nil {
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
            }
            if let team {
                NavigationLink {
                    TeamDetailView(team: team)
                } label: {
                    Label("Edit Roster", systemImage: "person.2")
                }
            }
        }
    }
}
