//
//  ComingSoonView.swift
//  Blitzball Stat Tracker
//
//  A shared placeholder for features we haven't built yet. Reusing one view keeps the
//  three stubs tiny and consistent — we'll swap each out as we build the real feature.
//

import SwiftUI

struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text("Currently Under Construction.")
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(title: "Exhibition", systemImage: "baseball.fill")
    }
}
