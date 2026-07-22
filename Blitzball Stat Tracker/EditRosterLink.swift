//
//  EditRosterLink.swift
//  Blitzball Stat Tracker
//
//  The "Edit Roster" row shown on pregame screens (Season week, Tournament match) — a shortcut
//  into TeamDetailView so users can add/remove players for game day without leaving the flow.
//  Extracted here so both call sites stay identical; the caller is expected to re-run its
//  syncLineups() on return (typically via .onAppear on the pregame view).
//

import SwiftUI

struct EditRosterLink: View {
    let team: Team?

    var body: some View {
        if let team {
            NavigationLink {
                TeamDetailView(team: team)
            } label: {
                Label("Edit Roster", systemImage: "square.and.pencil")
            }
        }
    }
}
