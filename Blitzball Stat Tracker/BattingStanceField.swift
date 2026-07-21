//
//  BattingStanceField.swift
//  Blitzball Stat Tracker
//
//  One reusable batting-stance control so every place a player is created or edited (New Player,
//  the team roster builder, Edit Player) looks and behaves identically. Uses an inline segmented
//  style rather than a pop-up menu — a menu Picker inside a nested sheet dismisses the sheet on
//  selection (a SwiftUI bug), and segmented also keeps every option visible at a glance.
//
//  The bound value is the raw stored string: "" means no stance, otherwise "LH" / "RH" / "Switch".
//

import SwiftUI

struct BattingStanceField: View {
    @Binding var stance: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Batting Stance (optional)")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Picker("Batting Stance", selection: $stance) {
                Text("—").tag("")
                Text("LH").tag("LH")
                Text("RH").tag("RH")
                Text("Switch").tag("Switch")
            }
            .pickerStyle(.segmented)
        }
    }
}
