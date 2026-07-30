//
//  ZoomedCardView.swift
//  Blitzball Stat Tracker
//
//  The big card you get after tapping one in the carousel. Three things happen on this one view:
//    • tap        → flip front↔back (reusing CardFace from FlipCard)
//    • drag       → tilt the card in 3D, with a shadow that leans the other way
//    • long drag  → page to the next/previous player
//
//  Tilt/parallax technique per
//  https://medium.com/@jc_builds/swiftui-tutorials-how-to-create-a-3d-flip-card-with-parallax-effect-d75b2cd22d38
//
//  THE GESTURE DESIGN, because it's the fiddly part:
//
//  There is exactly ONE DragGesture. It is tempting to add a second one (or a `simultaneousGesture`)
//  so that tilting and swiping are separate recognizers — don't. Two drag recognizers over the same
//  view means SwiftUI has to arbitrate between them, and that arbitration is what produces the
//  "sometimes it tilts, sometimes it swipes, never the one I wanted" class of bug.
//
//  Instead the single gesture has two modes. It ALWAYS starts in tilt. It promotes itself to paging
//  the moment the drag is both far enough and clearly horizontal, and once promoted it never goes
//  back for the rest of that drag (so a wobble mid-swipe doesn't dump you back into tilting).
//
//  The nice side effect: the first stretch of a horizontal swipe visibly leans the card in the
//  direction you're pushing before it commits to flying away. The tilt becomes the affordance for
//  the page — no invisible hot-zones to discover.
//

import SwiftUI
import SwiftData

struct ZoomedCardView: View {
    let entry: CardEntry
    let heroWidth: CGFloat
    var namespace: Namespace.ID?
    /// Asks the carousel to move one player along. Returns false at either end of the deck, in which
    /// case the card springs back rather than sliding away to nothing.
    let onPage: (Int) -> Bool
    let onEdit: () -> Void
    /// Seam for the headless render test: draw a frozen tilt so the perspective and the shadow
    /// offset can be judged in a still image.
    var previewTilt: CGSize = .zero

    @State private var flipped = false
    /// Raw finger translation while tilting.
    @State private var tilt: CGSize
    /// Horizontal slide while paging.
    @State private var pageOffset: CGFloat = 0
    @State private var dragMode: DragMode = .tilting
    /// Which way the last page went, so the incoming card enters from the correct side.
    @State private var pageDirection: Int = 1

    init(entry: CardEntry,
         heroWidth: CGFloat,
         namespace: Namespace.ID? = nil,
         onPage: @escaping (Int) -> Bool,
         onEdit: @escaping () -> Void,
         previewTilt: CGSize = .zero) {
        self.entry = entry
        self.heroWidth = heroWidth
        self.namespace = namespace
        self.onPage = onPage
        self.onEdit = onEdit
        self.previewTilt = previewTilt
        _tilt = State(initialValue: previewTilt)
    }

    private enum DragMode {
        case tilting
        /// `origin` is the translation at the instant paging took over, so the slide starts from
        /// zero instead of jumping by however far the tilt had already travelled.
        case paging(origin: CGFloat)
    }

    private enum Tuning {
        /// Points of drag per degree of tilt.
        static let tiltDivisor: Double = 10
        static let maxTiltDegrees: Double = 22
        /// Horizontal travel past which the drag may become a page…
        static let pageLatch: CGFloat = 60
        /// …provided it's at least this much more horizontal than vertical.
        static let horizontalDominance: CGFloat = 1.8
        /// Slide distance that commits to the page.
        static let pageCommit: CGFloat = 110
        /// …or this much predicted flick momentum.
        static let pageFling: CGFloat = 200
        /// Distance over which the tilt straightens out as the card slides away.
        static let straightenOver: CGFloat = 200
    }

    var body: some View {
        VStack(spacing: 18) {
            card
            Text("Tap to flip · swipe for the next card")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Button(action: onEdit) {
                Label("Edit Card", systemImage: "slider.horizontal.3")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    // MARK: - The card

    private var card: some View {
        faces
            .frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
            .overlay { foilOverlay }
            .scaleEffect(heroWidth / CardMetrics.nativeWidth)
            .frame(width: heroWidth, height: heroWidth * CardMetrics.ratio)
            // Both tilts sit OUTSIDE the flip, so the tilt is in screen space: dragging right always
            // pushes the right edge of whichever face you're looking at away from you.
            .rotation3DEffect(.degrees(yAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(xAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            // Outside the rotations too — a shadow that rotated with the card would read as part of
            // the card rather than as something cast onto the surface behind it.
            .shadow(color: .black.opacity(0.55),
                    radius: 22 + abs(yAngle) / 2,
                    x: CGFloat(-yAngle) * 1.4,
                    y: 16 + CGFloat(xAngle) * 1.2)
            .matchedZoomGeometry(id: entry.id, in: namespace)
            .offset(x: pageOffset)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .gesture(dragGesture)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: flipped)
    }

    /// The two faces. The `.id` + transition live HERE, on the inner container, rather than on the
    /// view carrying the matched geometry above — a transition and a matched-geometry source on the
    /// same view fight each other over the same frame.
    private var faces: some View {
        ZStack {
            cardFrontView(entry.template, player: entry.player)
                .modifier(CardFace(angle: flipAngle, isBack: false))
            cardBackView(entry.template, player: entry.player)
                .modifier(CardFace(angle: flipAngle, isBack: true))
        }
        .id(entry.id)
        .transition(pageTransition)
    }

    @ViewBuilder
    private var foilOverlay: some View {
        // No shipping template is foil yet, so this branch is never taken — see FoilSheen.
        if entry.template.hasFoilFinish {
            FoilSheen(yAngle: yAngle, xAngle: xAngle, maxAngle: Tuning.maxTiltDegrees)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var pageTransition: AnyTransition {
        let leading = AnyTransition.move(edge: .leading).combined(with: .opacity)
        let trailing = AnyTransition.move(edge: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: pageDirection > 0 ? trailing : leading,
                           removal: pageDirection > 0 ? leading : trailing)
    }

    // MARK: - Angles

    private var flipAngle: Double { flipped ? 180 : 0 }

    private var yAngle: Double { clampTilt(Double(tilt.width) / Tuning.tiltDivisor) }

    private var xAngle: Double { clampTilt(-Double(tilt.height) / Tuning.tiltDivisor) }

    private func clampTilt(_ raw: Double) -> Double {
        max(-Tuning.maxTiltDegrees, min(Tuning.maxTiltDegrees, raw))
    }

    // MARK: - Gestures

    private func flip() {
        withAnimation(.easeInOut(duration: 0.5)) { flipped.toggle() }
    }

    /// `minimumDistance: 8` is load-bearing. With it, SwiftUI resolves tap-vs-drag natively: a
    /// stationary touch fires the tap and flips the card, while 8pt of movement claims the drag and
    /// cancels the tap. At `minimumDistance: 0` the drag would win every single touch and the card
    /// could never be flipped. The cost is the first ~0.8° of tilt, which is imperceptible.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation
                promoteIfNeeded(translation)
                switch dragMode {
                case .tilting:
                    tilt = translation
                case .paging(let origin):
                    pageOffset = translation.width - origin
                    // Straighten up as the card leaves, so it "leans, then flies".
                    let fade = max(0, 1 - abs(pageOffset) / Tuning.straightenOver)
                    tilt = CGSize(width: origin * fade, height: translation.height * fade)
                }
            }
            .onEnded { value in
                defer { dragMode = .tilting }
                guard case .paging = dragMode else {
                    settle()
                    return
                }
                let committed = abs(pageOffset) > Tuning.pageCommit
                    || abs(value.predictedEndTranslation.width) > Tuning.pageFling
                if committed {
                    commitPage(direction: pageOffset < 0 ? 1 : -1)
                } else {
                    settle()
                }
            }
    }

    /// One-way promotion from tilting to paging.
    private func promoteIfNeeded(_ translation: CGSize) {
        guard case .tilting = dragMode else { return }
        guard abs(translation.width) > Tuning.pageLatch,
              abs(translation.width) > Tuning.horizontalDominance * abs(translation.height)
        else { return }
        dragMode = .paging(origin: translation.width)
    }

    private func commitPage(direction: Int) {
        pageDirection = direction
        guard onPage(direction) else {
            settle()
            return
        }
        // A new player always arrives face up.
        flipped = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            pageOffset = 0
            tilt = .zero
        }
    }

    private func settle() {
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 14)) {
            pageOffset = 0
            tilt = .zero
        }
    }
}

private extension View {
    /// The zoom side of the carousel's `matchedGeometryEffect`, tolerant of having no namespace (the
    /// render test has none). Position only — see the matching note in CardCarouselStack.
    @ViewBuilder
    func matchedZoomGeometry(id: PersistentIdentifier, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace, properties: .position,
                                       anchor: .center, isSource: true)
        } else {
            self
        }
    }
}
