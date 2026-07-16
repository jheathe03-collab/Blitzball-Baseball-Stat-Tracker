//
//  TeamLogo.swift
//  Blitzball Stat Tracker
//
//  The bundled team logos (transparent PNGs in Assets), a reusable view to render one next to a
//  team, and a picker grid for choosing one. `Team.logoName` stores the chosen asset name (or nil).
//

import SwiftUI

enum TeamLogo {
    /// Asset names of the bundled logos, in menu order.
    static let all = ["Banana", "BlitzDragons", "Bobcats", "Dragons",
                      "Elephants", "MightyFish", "Peppers", "Sharks"]

    /// A friendlier label, e.g. "MightyFish" → "Mighty Fish".
    static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    /// Per-logo visual scale. Wide/short artwork fits its width in a square frame and ends up
    /// looking small, so we nudge those up so every logo reads at a similar size.
    static func visualScale(_ name: String?) -> CGFloat {
        switch name {
        case "Peppers":    return 1.35
        case "Dragons":    return 1.20
        default:           return 1.0
        }
    }
}

/// Renders a team's logo fitted into a square, or a neutral placeholder when none is set.
struct TeamLogoView: View {
    let logoName: String?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let logoName, !logoName.isEmpty {
                Image(logoName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(TeamLogo.visualScale(logoName))
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A grid to choose a team's logo (or "None").
struct TeamLogoPicker: View {
    @Binding var logoName: String?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    cell(name: nil)
                    ForEach(TeamLogo.all, id: \.self) { cell(name: $0) }
                }
                .padding()
            }
            .navigationTitle("Team Logo")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func cell(name: String?) -> some View {
        let isSelected = (logoName ?? "") == (name ?? "")
        Button {
            logoName = name
            dismiss()
        } label: {
            VStack(spacing: 6) {
                TeamLogoView(logoName: name, size: 76)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                Text(name.map(TeamLogo.displayName) ?? "None")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }
}
