//
//  SeasonModeView.swift
//  Blitzball Stat Tracker
//
//  The Season hub: start a new season, resume one in progress, view season stats, or import a
//  season file exported from another device.
//

import SwiftUI

struct SeasonModeView: View {
    @State private var showingImporter = false

    var body: some View {
        List {
            NavigationLink(value: SeasonRoute.newSeason) {
                Label("New Season", systemImage: "plus.circle")
            }
            .blitzCardRow()
            NavigationLink(value: SeasonRoute.resume) {
                Label("Resume Season", systemImage: "play.circle")
            }
            .blitzCardRow()
            NavigationLink {
                SeasonStatsView()
            } label: {
                Label("View Seasons", systemImage: "chart.bar")
            }
            .blitzCardRow()

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Season…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Bring in a season file exported from another device (View Seasons → Export → Season File).")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.99))
            }
            .blitzCardRow()
        }
        .blitzListStyle()
        .navigationTitle("Season Mode")
        .blitzballBackground(watermark: true)
        .seasonImporter(isPresented: $showingImporter)
    }
}
