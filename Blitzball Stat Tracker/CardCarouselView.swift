//
//  CardCarouselView.swift
//  Blitzball Stat Tracker
//
//  The full-screen "View All Player Cards" experience: the whole league as a fanned deck you drag
//  through, grouped by team, with a tap-to-zoom card on top. This file is just the shell — the fan
//  lives in CardCarouselStack, the zoomed card in ZoomedCardView.
//
//  Note the zoomed card is a SIBLING in this ZStack rather than a sheet. `matchedGeometryEffect`
//  can't reach across a sheet/cover boundary, so the zoom would lose its animation if the hero were
//  presented separately.
//

import SwiftUI
import SwiftData

struct CardCarouselView: View {
    let players: [Player]

    @Environment(\.dismiss) private var dismiss
    @Namespace private var cardZoom

    /// Built once (see `rebuildEntries`) rather than computed in `body` — the grouping does sorting
    /// and dictionary work, and a computed property here would re-run it on every frame of a drag.
    @State private var entries: [CardEntry]
    @State private var snappedItem: Double
    @State private var draggingItem: Double
    @State private var zoomedIndex: Int?
    @State private var editingPlayer: Player?

    /// `ImageRenderer` can produce blank output for `drawingGroup` layers, so the render test turns
    /// the cards' rasterisation off.
    private let rasterizes: Bool

    init(players: [Player]) {
        self.players = players
        self.rasterizes = true
        _entries = State(initialValue: [])
        _snappedItem = State(initialValue: 0)
        _draggingItem = State(initialValue: 0)
    }

    /// Seam for the headless render test (and SwiftUI previews): start with a fixed deck at a fixed
    /// position, since `ImageRenderer` draws the body once and never runs `.task`. A fractional
    /// index renders a mid-drag frame.
    init(previewEntries: [CardEntry], previewIndex: Double) {
        self.players = previewEntries.map(\.player)
        self.rasterizes = false
        _entries = State(initialValue: previewEntries)
        _snappedItem = State(initialValue: previewIndex)
        _draggingItem = State(initialValue: previewIndex)
    }

    var body: some View {
        ZStack {
            backdrop

            if entries.isEmpty {
                ContentUnavailableView("No Cards Yet",
                                       systemImage: "rectangle.stack",
                                       description: Text("Add a player to see their card here."))
                    .foregroundStyle(.white)
            } else {
                deck
                if let index = zoomedIndex, entries.indices.contains(index) {
                    hero(entries[index])
                }
            }
        }
        .overlay(alignment: .topLeading) { closeButton }
        .modifier(CarouselPresentations(editingPlayer: $editingPlayer,
                                        snapTrigger: Int(snappedItem),
                                        rebuild: rebuildEntries))
    }

    // MARK: - Pieces

    private var backdrop: some View {
        Color.black.opacity(0.94)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            // Tapping off the card is the natural "put it back" gesture. Only listens while zoomed,
            // so it never swallows taps meant for the fan.
            .onTapGesture { if zoomedIndex != nil { zoomOut() } }
    }

    /// The fan plus its team header and player caption. Dimmed rather than removed while zoomed —
    /// removing it would tear down the geometry namespace the zoom needs for the trip back.
    private var deck: some View {
        GeometryReader { geo in
            let cardW = min(geo.size.width * 0.62, (geo.size.height - 260) / CardMetrics.ratio)
            VStack(spacing: 0) {
                teamHeader
                Spacer(minLength: 0)
                CardCarouselStack(entries: entries,
                                  snappedItem: $snappedItem,
                                  draggingItem: $draggingItem,
                                  cardWidth: cardW,
                                  zoomedIndex: zoomedIndex,
                                  namespace: cardZoom,
                                  rasterizes: rasterizes,
                                  onZoom: zoomIn)
                Spacer(minLength: 0)
                playerCaption
            }
            .padding(.vertical, 28)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .opacity(zoomedIndex == nil ? 1 : 0)
        .allowsHitTesting(zoomedIndex == nil)
    }

    private func hero(_ entry: CardEntry) -> some View {
        GeometryReader { geo in
            let heroW = min(geo.size.width * 0.84, (geo.size.height - 200) / CardMetrics.ratio)
            ZoomedCardView(entry: entry,
                           heroWidth: heroW,
                           namespace: cardZoom,
                           onPage: page(by:),
                           onEdit: { editingPlayer = entry.player })
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity)
    }

    /// The centred card's team. Keyed on `groupIndex` so it cross-fades exactly when you cross a
    /// team boundary — and read from the LIVE index, so it changes at the halfway point of a drag
    /// rather than after the spring settles.
    private var teamHeader: some View {
        ZStack {
            if let entry = centered {
                HStack(spacing: 10) {
                    TeamLogoView(team: entry.team, size: 34)
                    Text(entry.groupTitle.uppercased())
                        .font(Theme.cardTitle)
                        .foregroundStyle(.white)
                }
                .id(entry.groupIndex)
                .transition(.opacity)
            }
        }
        .frame(height: 40)
        .animation(.easeInOut(duration: 0.25), value: centered?.groupIndex ?? -1)
    }

    private var playerCaption: some View {
        ZStack {
            if let entry = centered {
                HStack(spacing: 10) {
                    Text(entry.player.name)
                        .font(.title3.bold())
                    if let number = entry.player.jerseyNumber {
                        Text("#\(number)")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .foregroundStyle(.white)
                .id(entry.id)
                .transition(.opacity)
            }
        }
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.2), value: centeredIndex)
    }

    private var closeButton: some View {
        Button {
            if zoomedIndex != nil { zoomOut() } else { dismiss() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }

    // MARK: - State

    private var centeredIndex: Int {
        min(max(Int(draggingItem.rounded()), 0), max(entries.count - 1, 0))
    }

    private var centered: CardEntry? {
        entries.indices.contains(centeredIndex) ? entries[centeredIndex] : nil
    }

    private func rebuildEntries() {
        entries = CardCarouselEntry.build(from: players)
    }

    private func zoomIn(_ index: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { zoomedIndex = index }
    }

    private func zoomOut() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { zoomedIndex = nil }
    }

    /// Move the zoomed card one player along. Also moves the fan underneath, so closing the zoom
    /// lands you on the card you were actually looking at. Returns false at either end of the deck
    /// so the card can spring back instead of flying off into nothing.
    private func page(by delta: Int) -> Bool {
        guard let current = zoomedIndex else { return false }
        let next = current + delta
        guard entries.indices.contains(next) else { return false }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            zoomedIndex = next
            snappedItem = Double(next)
            draggingItem = Double(next)
        }
        return true
    }
}

/// The screen's presentation/side-effect chain, pulled out as a modifier.
///
/// Same treatment (and same reason) as `ChallengeDialogs` in LiveGameView: a long run of
/// `.task` / `.onChange` / `.sensoryFeedback` / `.fullScreenCover` on one view is what pushes the
/// Swift type-checker over its complexity limit.
private struct CarouselPresentations: ViewModifier {
    @Binding var editingPlayer: Player?
    let snapTrigger: Int
    let rebuild: () -> Void

    func body(content: Content) -> some View {
        content
            .task { rebuild() }
            // Editing a card can change its photo or template, which the carousel's redraw gate
            // keys off. Rebuilding on dismissal refreshes those tokens so the card repaints.
            .onChange(of: editingPlayer) { _, newValue in
                if newValue == nil { rebuild() }
            }
            // Keyed on the SETTLED index, not the live one — otherwise it would buzz continuously
            // while a finger is dragging.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: snapTrigger)
            .fullScreenCover(item: $editingPlayer) { player in
                PlayerCardView(player: player)
            }
    }
}
