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
import UIKit

/// The canonical size a card's CONTENT is always laid out at. Both the full-screen card and the
/// picker previews render at this size and then scale to fit — so fixed point values inside a
/// template look identical everywhere (no "fits on the big card but breaks in the preview" drift).
enum CardMetrics {
    static let nativeWidth: CGFloat = 320
    static let ratio: CGFloat = 1.5
    static var nativeHeight: CGFloat { nativeWidth * ratio }
}

// MARK: - Shared portrait (used by every template)

/// Renders the player's photo filling its area (or a neutral placeholder). A GeometryReader gives
/// the image a definite box to fill+clip, so a wide/tall photo can't drag the card's own size toward
/// the image's aspect ratio.
struct PlayerPortrait: View {
    let player: Player

    var body: some View {
        GeometryReader { geo in
            Group {
                if let data = player.photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.gray.opacity(0.25)
                        Image(systemName: "person.fill")
                            .resizable().scaledToFit()
                            .padding(44)
                            .foregroundStyle(.gray.opacity(0.55))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Identifies a card design. Add a case (+ its views) to introduce a new template.
enum CardTemplateID: String, CaseIterable, Identifiable {
    case classic
    case wood
    case vintage
    case allStar
    case goldStandard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:      return "Classic"
        case .wood:         return "Woodgrain"
        case .vintage:      return "Vintage"
        case .allStar:      return "All-Star"
        case .goldStandard: return "Gold Standard"
        }
    }
}

// MARK: - Resolvers (id → that template's views)

@ViewBuilder
func cardFrontView(_ template: CardTemplateID, player: Player) -> some View {
    switch template {
    case .classic: ClassicCardFront(player: player)
    case .wood:    WoodCardFront(player: player)
    case .vintage: VintageCardFront(player: player)
    case .allStar: AllStarCardFront(player: player)
    case .goldStandard: GoldStandardCardFront(player: player)
    }
}

@ViewBuilder
func cardBackView(_ template: CardTemplateID, player: Player) -> some View {
    switch template {
    case .classic: ClassicCardBack(player: player)
    case .wood:    WoodCardBack(player: player)
    case .vintage: VintageCardBack(player: player)
    case .allStar: AllStarCardBack(player: player)
    case .goldStandard: GoldStandardCardBack(player: player)
    }
}

// MARK: - Picker

/// A grid of templates rendered as live previews of THIS player's card; tap to choose.
struct CardTemplatePicker: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

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
        let tileW: CGFloat = 160
        let scale = tileW / CardMetrics.nativeWidth
        let nativeW = CardMetrics.nativeWidth
        let nativeH = CardMetrics.nativeHeight
        return Button {
            player.cardTemplate = template.rawValue
            dismiss()
        } label: {
            VStack(spacing: 8) {
                cardFrontView(template, player: player)
                    .frame(width: nativeW, height: nativeH)   // render full-size…
                    .scaleEffect(scale)                        // …then shrink the whole card
                    .frame(width: nativeW * scale, height: nativeH * scale)  // collapse layout to the mini size
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
