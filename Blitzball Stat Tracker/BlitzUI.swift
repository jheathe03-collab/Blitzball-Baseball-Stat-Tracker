//
//  BlitzUI.swift
//  Blitzball Stat Tracker
//
//  Reusable pieces of the branded look: the dark menu card, a list-row card style, and a nav-bar
//  tweak so the system bar reads against the gradient. Styling only — no logic.
//

import SwiftUI

// MARK: - Menu card (main menu + hubs)

/// A solid dark rounded card: an icon, an uppercase rounded title, and (unless compact) a subtitle.
/// Wrap it in a NavigationLink for a tappable menu entry.
struct MenuCard: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    /// Compact = shorter, icon + title only (for the side-by-side pair).
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(Theme.cardTitle)
                    .foregroundStyle(.white)
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if !compact { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compact ? 84 : 80)
        .background(Theme.cardFill,
                    in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

// MARK: - List styling

extension View {
    /// Turns a List row into a dark rounded card floating on the gradient. Apply per-row.
    func blitzCardRow() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.cardFill)
                    .padding(.vertical, 4)
            )
            .listRowSeparator(.hidden)
            .foregroundStyle(.white)
    }

    /// Inset-grouped list styling used by the branded list screens.
    func blitzListStyle() -> some View {
        self.listStyle(.insetGrouped)
    }

    /// Makes the system nav bar transparent with light title/back so it reads on the gradient.
    func blitzNavBar() -> some View {
        self
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
