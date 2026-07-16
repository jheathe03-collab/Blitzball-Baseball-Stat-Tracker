//
//  SeasonModeView.swift
//  Blitzball Stat Tracker
//
//  The Season hub: start a new season, resume one in progress, or view season stats.
//

import SwiftUI

struct SeasonModeView: View {
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
                Label("Season Stats", systemImage: "chart.bar")
            }
            .blitzCardRow()
        }
        .blitzListStyle()
        .navigationTitle("Season Mode")
        .blitzballBackground(watermark: true)
    }
}
