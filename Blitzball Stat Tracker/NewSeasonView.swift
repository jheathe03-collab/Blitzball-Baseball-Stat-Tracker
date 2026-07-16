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
    @Environment(\.modelContext) private var modelContext
    @State private var season: Season?

    var body: some View {
        Group {
            if let season {
                NewSeasonForm(season: season)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("New Season")
        .blitzballBackground()
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
    @Environment(\.modelContext) private var modelContext
    @Environment(Router.self) private var router
    @State private var showStartConfirm = false

    var body: some View {
        Form {
            Section {
                TextField("", text: $season.name,
                          prompt: Text("Season Name").foregroundStyle(.white.opacity(0.5)))
                Stepper("Games Per Season: \(season.gamesPerSeason)",
                        value: $season.gamesPerSeason, in: 1...30)
            } footer: {
                Text("The name is used to filter this season's stats later.")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .blitzCardRow()

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
            .blitzCardRow()

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
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .blitzCardRow()
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
    }

    private func startSeason() {
        // Apply the season rulebook to each week's game, mark it in progress, then push its
        // schedule onto the season stack (single value → single push).
        for game in season.games { game.settings = season.settings }
        season.status = .inProgress
        router.seasonPath.append(.games(season))
    }
}
