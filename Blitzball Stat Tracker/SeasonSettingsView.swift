//
//  SeasonSettingsView.swift
//  Blitzball Stat Tracker
//
//  The season-wide rulebook — the same editor as Game Options, bound to the season's settings.
//

import SwiftUI
import SwiftData

struct SeasonSettingsView: View {
    @Bindable var season: Season

    var body: some View {
        GameSettingsEditor(settings: $season.settings)
            .navigationTitle("Season Settings")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
    }
}
