//
//  CardTemplate.swift
//  Blitzball Stat Tracker
//
//  The set of baseball-card designs a player can pick from. Each template is a distinct, self-
//  contained design (its own front/back views). `Player.cardTemplate` stores the chosen rawValue;
//  the resolver functions map an id to that template's views, used both by the live card
//  (PlayerCardView) and the picker previews. To add a design: add a case here, add its views, and
//  wire the two switches — the picker shows it automatically.
//

import SwiftUI

/// Identifies a card design. Add a case (+ its views) to introduce a new template.
enum CardTemplateID: String, CaseIterable, Identifiable {
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        }
    }
}

// MARK: - Resolvers (id → that template's views)

@ViewBuilder
func cardFrontView(_ template: CardTemplateID, player: Player) -> some View {
    switch template {
    case .classic: ClassicCardFront(player: player)
    }
}

@ViewBuilder
func cardBackView(_ template: CardTemplateID, player: Player) -> some View {
    switch template {
    case .classic: ClassicCardBack(player: player)
    }
}

// MARK: - Picker

/// A grid of templates rendered as live previews of THIS player's card; tap to choose.
struct CardTemplatePicker: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 18)]

    private var current: CardTemplateID {
        CardTemplateID(rawValue: player.cardTemplate ?? "") ?? .classic
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(CardTemplateID.allCases) { template in
                        cell(template)
                    }
                }
                .padding()
            }
            .navigationTitle("Card Template")
            .navigationBarTitleDisplayMode(.inline)
            .blitzballBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func cell(_ template: CardTemplateID) -> some View {
        let selected = current == template
        return Button {
            player.cardTemplate = template.rawValue
            dismiss()
        } label: {
            VStack(spacing: 8) {
                cardFrontView(template, player: player)
                    .frame(width: 130, height: 195)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                Text(template.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
