//
//  ExhibitionView.swift
//  Blitzball Stat Tracker
//
//  Exhibition Mode: track stats for a single one-off game. (Stub for now.)
//

import SwiftUI

struct ExhibitionView: View {
    var body: some View {
        ComingSoonView(title: "Exhibition", systemImage: "baseball.fill")
    }
}

#Preview {
    NavigationStack { ExhibitionView() }
}
