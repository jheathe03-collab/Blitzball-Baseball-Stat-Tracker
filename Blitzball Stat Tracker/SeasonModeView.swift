//
//  SeasonModeView.swift
//  Blitzball Stat Tracker
//
//  The Season hub: start a new season, resume one in progress, or view season stats.
//

import SwiftUI

struct SeasonModeView: View {
    // Shared with every screen below, so a deep screen can request unwinding back to this hub.
    @State private var seasonNav = SeasonNavigator()

    var body: some View {
        List {
            NavigationLink {
                NewSeasonView(nav: seasonNav)
            } label: {
                Label("New Season", systemImage: "plus.circle")
            }
            NavigationLink {
                ResumeSeasonView(nav: seasonNav)
            } label: {
                Label("Resume Season", systemImage: "play.circle")
            }
            NavigationLink {
                ComingSoonView(title: "Season Stats", systemImage: "chart.bar")
            } label: {
                Label("Season Stats", systemImage: "chart.bar")
            }
        }
        .navigationTitle("Season Mode")
        // We're home — clear any pending exit request.
        .onAppear { seasonNav.exitRequested = false }
    }
}
