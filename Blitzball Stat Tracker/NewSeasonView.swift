//
//  NewSeasonView.swift
//  Blitzball Stat Tracker
//
//  Configure a new season: name, number of weekly games, the schedule, and the rulebook, then
//  Start it. Uses the find-or-create-draft pattern (like ExhibitionView's setup game).
//

import SwiftUI
import SwiftData

struct NewSeasonView: View {
    let nav: SeasonNavigator
    @Environment(\.modelContext) private var modelContext
    @State private var season: Season?

    var body: some View {
        Group {
            if let season {
                NewSeasonForm(season: season, nav: nav)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("New Season")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadOrCreate)
    }

    private func loadOrCreate() {
        guard season == nil else { return }
        let descriptor = FetchDescriptor<Season>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let seasons = (try? modelContext.fetch(descriptor)) ?? []
        if let draft = seasons.first(where: { $0.status == .setup }) {
            season = draft
        } else {
            let newSeason = Season()
            modelContext.insert(newSeason)
            season = newSeason
        }
        season?.syncSchedule(using: modelContext)
    }
}

private struct NewSeasonForm: View {
    @Bindable var season: Season
    let nav: SeasonNavigator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showStartConfirm = false
    @State private var goToSchedule = false

    var body: some View {
        Form {
            Section {
                TextField("Season Name", text: $season.name)
                Stepper("Games Per Season: \(season.gamesPerSeason)",
                        value: $season.gamesPerSeason, in: 1...30)
            } footer: {
                Text("The name is used to filter this season's stats later.")
            }

            Section {
                NavigationLink {
                    SeasonScheduleView(season: season)
                } label: {
                    HStack {
                        Label("Set Season Schedule", systemImage: "calendar")
                        Spacer()
                        Text("\(season.weeksWithTeamsSet)/\(season.gamesPerSeason) set")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    SeasonSettingsView(season: season)
                } label: {
                    HStack {
                        Label("Season Settings", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(season.settings.matchedType.displayName)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showStartConfirm = true
                } label: {
                    Label("Start Season", systemImage: "play.fill").fontWeight(.semibold)
                }
                .disabled(!season.isScheduleComplete)
            } footer: {
                if !season.isScheduleComplete {
                    Text("Set every week's matchup before starting the season.")
                }
            }
        }
        // Resize the schedule whenever the number of games changes.
        .onChange(of: season.gamesPerSeason) {
            season.syncSchedule(using: modelContext)
        }
        .alert("Everything look good?", isPresented: $showStartConfirm) {
            Button("Start Season") { startSeason() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Start \(season.name.isEmpty ? "this season" : season.name)? You'll jump straight to its schedule to play the games.")
        }
        // After starting, drop the user right into the season's week-by-week schedule.
        .navigationDestination(isPresented: $goToSchedule) {
            SeasonGamesView(season: season, nav: nav)
        }
        // When the games screen popped and we're back on top, honor a pending exit-to-hub request.
        .onAppear {
            if nav.exitRequested {
                nav.exitRequested = false
                dismiss()
            }
        }
    }

    private func startSeason() {
        // Apply the season rulebook to each week's game, mark it in progress, then jump to the schedule.
        for game in season.games { game.settings = season.settings }
        season.status = .inProgress
        goToSchedule = true
    }
}
