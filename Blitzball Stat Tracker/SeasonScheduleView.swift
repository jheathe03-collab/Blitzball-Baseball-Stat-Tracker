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
                            matchupLabel(game)
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
        .blitzballBackground()
        .onAppear { season.syncSchedule(using: modelContext) }
    }

    private func isSet(_ game: Game) -> Bool {
        game.homeTeam != nil && game.awayTeam != nil
    }

    @ViewBuilder
    private func matchupLabel(_ game: Game) -> some View {
        if let home = game.homeTeam, let away = game.awayTeam {
            HStack(spacing: 5) {
                TeamLogoView(logoName: home.logoName, size: 20)
                Text(home.name)
                Text("vs").foregroundStyle(.secondary)
                Text(away.name)
                TeamLogoView(logoName: away.logoName, size: 20)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text("Not set").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edit one week's matchup

struct WeekMatchupView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @State private var picking: TeamRole?
    @State private var showResetConfirm = false

    /// Only an unplayed (still-setup) week can have its teams changed or cleared — clearing a
    /// played week would strip the teams off its recorded stats.
    private var isEditable: Bool { game.status == .setup }

    var body: some View {
        List {
            teamSection(role: .home, team: game.homeTeam)
            teamSection(role: .away, team: game.awayTeam)

            if isEditable && (game.homeTeam != nil || game.awayTeam != nil) {
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Clear Both Teams", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Resets this week's matchup so you can pick again.")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("Week \(game.weekNumber)")
        .blitzballBackground()
        .navigationBarTitleDisplayMode(.inline)
        // Reuses TeamRole (home/away) + TeamPickerView from the exhibition flow.
        .sheet(item: $picking) { role in
            TeamPickerView(excluding: role == .home ? game.awayTeam : game.homeTeam) { team in
                if role == .home { setTeam(team, isHome: true) } else { setTeam(team, isHome: false) }
            }
        }
        .alert("Clear This Week?", isPresented: $showResetConfirm) {
            Button("Clear Matchup", role: .destructive) {
                clearTeam(isHome: true)
                clearTeam(isHome: false)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes both teams from Week \(game.weekNumber). Their stats and records aren't affected.")
        }
    }

    @ViewBuilder
    private func teamSection(role: TeamRole, team: Team?) -> some View {
        Section(role.title) {
            Button {
                picking = role
            } label: {
                HStack {
                    if let team { TeamLogoView(logoName: team.logoName, size: 24) }
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
                if isEditable {
                    Button(role: .destructive) {
                        clearTeam(isHome: role == .home)
                    } label: {
                        Label("Clear \(role.title)", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }

    private func setTeam(_ team: Team?, isHome: Bool) {
        if isHome { game.homeTeam = team; game.homePitcher = nil }
        else { game.awayTeam = team; game.awayPitcher = nil }
        syncLineups()
    }

    /// Unset one side (team + its starting pitcher) and rebuild the lineups.
    private func clearTeam(isHome: Bool) {
        setTeam(nil, isHome: isHome)
    }

    private func syncLineups() {
        game.syncLineup(isHome: true, using: modelContext)
        game.syncLineup(isHome: false, using: modelContext)
    }
}
