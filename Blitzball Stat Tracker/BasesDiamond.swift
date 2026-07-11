//
//  BasesDiamond.swift
//  Blitzball Stat Tracker
//
//  A little baseball diamond showing which ghost runners are on base. Tap a base to edit it.
//  Bases: index 0 = 1st (right), 1 = 2nd (top), 2 = 3rd (left).
//

import SwiftUI

struct BasesDiamond: View {
    let game: Game
    /// Called with the tapped base index (0/1/2) so the parent can open the editor.
    let onTapBase: (Int) -> Void

    private let spread: CGFloat = 42

    var body: some View {
        ZStack {
            base(index: 1, x: 0, y: -spread)      // 2nd (top)
            base(index: 0, x: spread, y: 0)       // 1st (right)
            base(index: 2, x: -spread, y: 0)      // 3rd (left)
            homePlate                             // home (bottom, reference only)
        }
        .frame(width: 150, height: 150)
    }

    private func base(index: Int, x: CGFloat, y: CGFloat) -> some View {
        let occupant = game.runner(onBase: index)
        return Button {
            onTapBase(index)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(occupant != nil ? Color.orange : Color(.systemGray5))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(45))
                .overlay {
                    if let occupant {
                        Text(initials(occupant.name))
                            .font(.caption2).bold()
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
    }

    private var homePlate: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray4))
            .frame(width: 28, height: 28)
            .rotationEffect(.degrees(45))
            .offset(x: 0, y: spread)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
