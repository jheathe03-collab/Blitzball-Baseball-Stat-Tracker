//
//  CardCarouselStack.swift
//  Blitzball Stat Tracker
//
//  The fanned stack of cards you drag through. Technique per
//  https://medium.com/@mkamaalg4/scaling-stacked-card-carousel-in-swiftui-db64fd6f4629 — a ZStack
//  where every card's position, scale and depth are computed from ONE number (how far that card is
//  from the centre), plus a DragGesture that moves that number. There's no ScrollView involved.
//
//  Two numbers drive everything:
//    • `snappedItem`  — the index the fan has settled on (always a whole number once at rest)
//    • `draggingItem` — the LIVE index, fractional mid-drag (e.g. 3.4 means "40% of the way from
//                       card 3 to card 4"). Everything on screen reads this one.
//

import SwiftUI
import SwiftData

// MARK: - Tuning

/// Every magic number the fan uses, in one place so the feel can be tuned without hunting.
enum CarouselTuning {
    /// Points of finger travel that equal moving one card.
    static let dragDivisor: Double = 110
    /// How far out (in points) a fully fanned neighbour sits from the centre.
    static let spread: CGFloat = 132
    /// Each card-width of distance from centre shrinks a card by this much.
    static let depthScaleStep: Double = 0.15
    static let minDepthScale: Double = 0.45
    /// The distance at which the arc reaches its widest point.
    static let fanHalf: Double = 2.0
    /// Distance out to which cards stay fully opaque, so the near neighbours read as solid cards.
    static let solidRadius: Double = 1.0
    /// Distance at which a card has faded to fully transparent. Also the boundary at which a card
    /// swaps between its real template and a cheap placeholder — see `CardCarouselStack.window`.
    static let visibleRadius: Double = 2.0
    /// Distance beyond which a card isn't in the view tree at all.
    static let renderRadius: Double = 3.0
    /// The most cards a single flick can advance. Deliberately equal to `renderRadius` — see the
    /// note in `dragGesture`.
    static let maxSnapJump: Double = 3
}

// MARK: - Geometry

/// Where one card sits in the fan, given how far it is from the centre.
///
/// This is a plain struct doing plain arithmetic, on purpose. Swift's type-checker struggles when
/// this kind of mixed `Double`/`CGFloat` maths is written inline inside a view body — this codebase
/// has already hit that limit once (see the `ChallengeDialogs` note in LiveGameView). Keeping the
/// maths out here means the view body only ever reads finished values.
struct CarouselLayout {
    let distance: Double
    let scale: Double
    let xOffset: CGFloat
    let opacity: Double
    let zIndex: Double

    /// How far card `index` is from the centre. Positive = the card is to the left of centre.
    ///
    /// NON-WRAPPING on purpose. The original article wraps with `.remainder(dividingBy:)` so the
    /// deck loops forever, but our deck is grouped by team — looping would jump from "Free Agents"
    /// straight back to the first team mid-swipe and desync the team header. It also keeps the
    /// render window a simple range instead of modular arithmetic.
    static func distance(index: Int, dragging: Double) -> Double {
        dragging - Double(index)
    }

    static func make(index: Int, dragging: Double) -> CarouselLayout {
        let d: Double = distance(index: index, dragging: dragging)
        let magnitude: Double = abs(d)

        // CLAMP BEFORE THE SIN. sin isn't monotonic: a card at twice `fanHalf` would come back
        // around to sin == 0 and sit dead centre BEHIND the top card. Clamping parks everything past
        // the fan's edge at the full spread, where it's already invisible anyway.
        let clamped: Double = max(-CarouselTuning.fanHalf, min(CarouselTuning.fanHalf, d))
        let angle: Double = (.pi / 2) * (clamped / CarouselTuning.fanHalf)
        // Negated so that dragging leftwards moves the cards leftwards, like a real deck.
        let x: CGFloat = CGFloat(sin(angle)) * CarouselTuning.spread * -1

        let s: Double = max(CarouselTuning.minDepthScale,
                            1.0 - magnitude * CarouselTuning.depthScaleStep)

        // Flat until `solidRadius`, then a straight fade to EXACTLY zero at `visibleRadius`.
        //
        // Two things ride on this. Holding the immediate neighbours fully opaque is what makes the
        // fan read as a solid deck of cards rather than a murky pile — a plain linear fade from the
        // centre puts them at 50%, which looks like fog. And landing on exactly zero at
        // `visibleRadius` is what makes the placeholder swap invisible: that's the same boundary, so
        // a card is always fully transparent at the instant its content changes.
        let fadeOver: Double = CarouselTuning.visibleRadius - CarouselTuning.solidRadius
        let o: Double = max(0, 1.0 - max(0, magnitude - CarouselTuning.solidRadius) / fadeOver)

        // Nearest the centre draws on top.
        return CarouselLayout(distance: d, scale: s, xOffset: x, opacity: o, zIndex: -magnitude)
    }
}

/// The whole position/depth/fade chain as a single modifier.
///
/// Four chained geometry modifiers written inline inside a `ForEach` closure is exactly the shape
/// that overloads the type-checker; bundling them here keeps the call site to one `.modifier(...)`.
private struct CardStackGeometry: ViewModifier {
    let layout: CarouselLayout

    func body(content: Content) -> some View {
        content
            .scaleEffect(layout.scale)
            .offset(x: layout.xOffset)
            .opacity(layout.opacity)
            .zIndex(layout.zIndex)
    }
}

// MARK: - Card content

/// A player's real card front, wrapped in an explicit `Equatable` so that dragging the fan doesn't
/// re-run the template's body on every frame.
///
/// This matters a lot: `.vintage` measures every glyph of the player's name to lay it along a curve,
/// and `.tacoStyle` composites pixel-derived artwork. Re-running those 60 times a second while a
/// finger is down would drop frames. `.equatable()` tells SwiftUI "if `CardIdentity` hasn't changed,
/// don't even look at my body".
///
/// The trade: this opts out of SwiftData's automatic observation here, so a change that
/// `CardIdentity` doesn't capture won't repaint the carousel. That's acceptable because the carousel
/// is read-only — all editing happens in `PlayerCardView`, after which the entry list is rebuilt.
private struct CarouselCardFace: View, Equatable {
    let entry: CardEntry

    static func == (lhs: CarouselCardFace, rhs: CarouselCardFace) -> Bool {
        lhs.entry.identity == rhs.entry.identity
    }

    var body: some View {
        cardFrontView(entry.template, player: entry.player)
    }
}

/// What a card renders when it's outside the visible radius: a flat rectangle, no photo, no
/// template. It's never actually seen (opacity is already zero out there) — it exists so a card can
/// be present in the view tree, with its identity established, a full card-width before it needs to
/// draw anything real.
private struct CardPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(white: 0.16))
    }
}

/// One card in the fan: real template or placeholder, sized by the canonical
/// "lay out at native size → scale → collapse the frame" contract used everywhere cards appear.
private struct CarouselCard: View {
    let entry: CardEntry
    let isReal: Bool
    let cardWidth: CGFloat
    let rasterizes: Bool

    var body: some View {
        nativeSized
            .scaleEffect(cardWidth / CardMetrics.nativeWidth)
            .frame(width: cardWidth, height: cardWidth * CardMetrics.ratio)
            // Outside the drawingGroup, or the shadow would be rasterised in and clipped away.
            .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
    }

    /// The card at its canonical 320×480, optionally flattened to a bitmap.
    ///
    /// Rasterising here — after the native frame, before any scaling — means the card is drawn once
    /// and every subsequent scale is a cheap texture transform rather than a re-draw. It's applied
    /// to every card uniformly; toggling it per card would show up as a crispness pop as cards pass
    /// through the centre.
    @ViewBuilder
    private var nativeSized: some View {
        let native = content.frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
        if rasterizes {
            native.drawingGroup(opaque: false, colorMode: .nonLinear)
        } else {
            native
        }
    }

    @ViewBuilder
    private var content: some View {
        if isReal {
            CarouselCardFace(entry: entry).equatable()
        } else {
            CardPlaceholder()
        }
    }
}

// MARK: - The stack

/// The draggable fan itself. Position state lives in the parent (`CardCarouselView`) so that the
/// zoomed card can page the fan underneath it and keep the two in sync.
struct CardCarouselStack: View {
    let entries: [CardEntry]
    @Binding var snappedItem: Double
    @Binding var draggingItem: Double
    let cardWidth: CGFloat
    /// Which card is currently zoomed, if any — that one hands its matched-geometry source over to
    /// the zoomed hero.
    let zoomedIndex: Int?
    /// nil disables the zoom transition entirely (used by the headless render test, which has no
    /// `@Namespace` to give us).
    var namespace: Namespace.ID?
    /// The headless renderer can produce blank output for `drawingGroup` layers, so tests turn the
    /// rasterisation off.
    var rasterizes: Bool = true
    let onZoom: (Int) -> Void

    var body: some View {
        ZStack {
            ForEach(window, id: \.self) { index in
                card(at: index)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    @ViewBuilder
    private func card(at index: Int) -> some View {
        // Bounds-guard: `entries` can shrink underneath us mid-animation. If the parent's
        // `players` binding loses a player (delete elsewhere, cascade from a season delete, an
        // @Query invalidation) while a spring is still targeting an old index, ForEach can
        // dispatch a stale index into this function. A subscript trap here would crash the app.
        // Rendering nothing for the stale slot is the safe alternative — the next body pass will
        // recompute `window` from the fresh `entries` and everything settles.
        if entries.indices.contains(index) {
            let entry = entries[index]
            let layout = CarouselLayout.make(index: index, dragging: draggingItem)
            CarouselCard(entry: entry,
                         isReal: abs(layout.distance) <= CarouselTuning.visibleRadius,
                         cardWidth: cardWidth,
                         rasterizes: rasterizes)
                .modifier(CardStackGeometry(layout: layout))
                .matchedCardGeometry(id: entry.id, in: namespace, isSource: zoomedIndex != index)
                .onTapGesture { tapped(index) }
        }
    }

    // MARK: Windowing

    /// The indices actually in the ZStack right now, derived from the LIVE index so the window
    /// follows the finger. At most 7 cards exist, and at most 5 of those draw a real template — a
    /// forty-player league costs exactly what a five-player league costs.
    private var window: [Int] {
        guard !entries.isEmpty else { return [] }
        // Clamp BOTH bounds into [0, upper] independently. `draggingItem` can overshoot the ends
        // via `rubberBanded`, and a hard flick on a small deck can push it well past `upper` —
        // producing `lo` = 8 while `upper` = 4. The previous form only clamped one side, so the
        // range `max(0, lo)...min(upper, hi)` became `8...4` and crashed with a Range precondition
        // failure. Clamping both sides guarantees `lo <= hi` (both collapse to `upper` at the
        // overshoot end, giving a valid single-element range).
        let upper = entries.count - 1
        let lo = min(upper, max(0, Int((draggingItem - CarouselTuning.renderRadius).rounded(.down))))
        let hi = min(upper, max(0, Int((draggingItem + CarouselTuning.renderRadius).rounded(.up))))
        return Array(lo...hi)
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let delta: Double = Double(value.translation.width) / CarouselTuning.dragDivisor
                draggingItem = Self.rubberBanded(snappedItem - delta, count: entries.count)
            }
            .onEnded { value in
                let predicted: Double =
                    Double(value.predictedEndTranslation.width) / CarouselTuning.dragDivisor
                // Clamp the flick. `withAnimation` re-runs the body ONCE with the target index, so
                // the render window during the snap is the TARGET's window. A card that should fly
                // off screen has to still be inside that window or it just vanishes at frame one.
                // Capping the jump at `renderRadius` guarantees it isn't. (It's also better to use:
                // a fan you can flick twenty cards through is a fan you can't aim.)
                let jump: Double = max(-CarouselTuning.maxSnapJump,
                                       min(CarouselTuning.maxSnapJump, -predicted))
                let target: Double = min(max((snappedItem + jump).rounded(), 0),
                                         Double(max(entries.count - 1, 0)))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    snappedItem = target
                    draggingItem = target
                }
            }
    }

    /// Soft resistance past either end of the deck instead of a dead stop.
    private static func rubberBanded(_ raw: Double, count: Int) -> Double {
        let upper: Double = Double(max(count - 1, 0))
        if raw < 0 { return raw / 3 }
        if raw > upper { return upper + (raw - upper) / 3 }
        return raw
    }

    /// Only the centred card zooms. Tapping any other card brings it to the centre first.
    ///
    /// The fanned cards overlap heavily, so "which one did I mean to hit" is genuinely ambiguous —
    /// and centre-then-pick is how you'd handle a real fan of cards in your hand anyway.
    private func tapped(_ index: Int) {
        let isCentre = abs(CarouselLayout.distance(index: index, dragging: draggingItem)) < 0.5
        if isCentre {
            onZoom(index)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                snappedItem = Double(index)
                draggingItem = Double(index)
            }
        }
    }
}

private extension View {
    /// `matchedGeometryEffect`, but tolerant of not having a namespace (the render test has none).
    ///
    /// Only `.position` is matched, never `.frame`. Matching the frame would fight the card sizing
    /// contract: the outer box would animate smoothly while the fixed-size content inside popped to
    /// its final `scaleEffect` in one step. Matching just the centre point lets our own
    /// `scaleEffect` handle the size, inside the same animation.
    @ViewBuilder
    func matchedCardGeometry(id: PersistentIdentifier, in namespace: Namespace.ID?, isSource: Bool) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace, properties: .position,
                                       anchor: .center, isSource: isSource)
        } else {
            self
        }
    }
}
