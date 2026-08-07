//
//  BaseballField.swift
//  Blitzball Stat Tracker
//
//  The live game's field: the custom park art running full width behind the scoring controls, with
//  a chip for each on-field player. TAP a base to open the base editor; DRAG a runner's chip forward
//  to steal/advance; and when a play needs it, each runner shows on-field Safe/Out buttons.
//
//  Chips are keyed by PLAYER (not by base), so when a runner advances — or the batter reaches base —
//  the SAME chip slides to its new spot instead of blinking out and in. A player who leaves the field
//  (out or scored) fades away. All of it rides one value-based animation on the field arrangement, so
//  it animates whatever caused the change — a play, a trot leg, or Undo (which reverses for free).
//
//  Base positions are FRACTIONS of the artwork rather than fixed points, so the chips stay glued to
//  the bags at any size — and because the chips live inside the same frame as the image, they scale
//  with it even when the art is overscaled to bleed off the screen edges.
//

import SwiftUI
import SwiftData

struct BaseballField: View {
    @Bindable var game: Game
    /// Tapped base index: 0 = first, 1 = second, 2 = third.
    var onTapBase: (Int) -> Void
    /// A runner was dragged from one base to a forward base — (fromBase, toBase) where 0/1/2 = bases
    /// and 3 = home. The caller resolves Safe/Out and the reason.
    var onDragRunner: (Int, Int) -> Void = { _, _ in }
    /// Bases whose runner is awaiting a Safe/Out call — each gets on-field Safe/Out buttons. Dragging
    /// and tapping are disabled while any are showing.
    var resolvingBases: [Int] = []
    /// A Safe (`true`) or Out (`false`) button was tapped for the runner on `base`.
    var onResolve: (Int, Bool) -> Void = { _, _ in }
    /// Runners currently mid-trot on a rounding/scoring play (a scoring runner, the batter circling on
    /// a home run, etc.). Each is drawn at its `leg` — -1 = home plate, 0/1/2 = the bags, 3 = across
    /// the plate — instead of wherever the game state has it, and is skipped as a base/batter chip so
    /// it isn't drawn twice. The caller steps the legs and, on arrival, hands off to a base chip or
    /// fades it. Keeping each traveler's id equal to its player's makes the base→trot handoff seamless.
    var travelers: [Traveler] = []

    struct Traveler: Identifiable {
        let id: PersistentIdentifier
        let player: Player
        let leg: Int
    }
    /// Hide the current batter's chip — used while a play resolves at the plate, so a batter who has
    /// run to first and faded (out) doesn't reappear at home underneath.
    var hideBatter: Bool = false

    // The runner currently being dragged and how far, so its chip follows the finger and lifts above
    // the others.
    @State private var dragging: RunnerDrag?

    private var resolving: Bool { !resolvingBases.isEmpty }

    /// Where each base sits in `BaseballDiamondCustomZoom`, as a fraction of its width/height.
    /// Measured off the artwork — update these together with the asset.
    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.631, y: 0.653),   // 1st
        CGPoint(x: 0.495, y: 0.488),   // 2nd
        CGPoint(x: 0.372, y: 0.654),   // 3rd
    ]
    private static let homePlate = CGPoint(x: 0.496, y: 0.854)
    /// Just past the plate, toward the dugout — where a scoring runner's chip glides before it fades,
    /// so a run reads as "crossed the plate" rather than parking on top of the batter.
    private static let scoringSpot = CGPoint(x: 0.63, y: 0.93)
    /// Just below the pitcher's rubber — clear of the 1st/3rd base line so it reads as the mound.
    private static let moundLabel = CGPoint(x: 0.496, y: 0.72)

    private static let aspect: CGFloat = 2857.0 / 2325.0

    // MARK: - On-field players

    /// One chip on the field, keyed by its player so it animates when it moves. `base` is the runner's
    /// base (0/1/2) for the drag; nil means the batter at the plate.
    private struct FieldChip: Identifiable {
        let id: PersistentIdentifier
        let player: Player
        let frac: CGPoint
        let base: Int?
        /// A runner crossing the plate to score — drawn like a runner (yellow) but not draggable.
        var scoring: Bool = false
    }

    /// The batting side on the field: runners on their bases and the current batter at home — minus
    /// anyone mid-trot — plus the travelers themselves, drawn at their current leg.
    private var fieldChips: [FieldChip] {
        var chips: [FieldChip] = []
        let traveling = Set(travelers.map(\.id))
        for base in 0..<3 {
            if let runner = game.runner(onBase: base),
               !traveling.contains(runner.persistentModelID) {
                chips.append(FieldChip(id: runner.persistentModelID, player: runner,
                                       frac: Self.basePositions[base], base: base))
            }
        }
        if !hideBatter, let batter = game.currentBatterLine?.player,
           !traveling.contains(batter.persistentModelID),
           !chips.contains(where: { $0.id == batter.persistentModelID }) {
            chips.append(FieldChip(id: batter.persistentModelID, player: batter,
                                   frac: Self.homePlate, base: nil))
        }
        // Travelers keep their player's id, so a chip that was on a bag (or at the plate as the batter)
        // slides straight into its trot with no blink.
        for t in travelers {
            chips.append(FieldChip(id: t.id, player: t.player,
                                   frac: Self.legFrac(t.leg), base: nil, scoring: true))
        }
        return chips
    }

    /// Where a trotting runner's chip sits for a given leg: home plate before he's off, on a bag for
    /// 0/1/2, at the plate itself for leg 3 (where a runner holds for a Safe/Out call, or touches down
    /// before scoring), and past the plate toward the dugout for leg 4+ (a scored run gliding off to fade).
    static func legFrac(_ leg: Int) -> CGPoint {
        if leg < 0 { return homePlate }
        if leg < 3 { return basePositions[leg] }
        if leg == 3 { return homePlate }
        return scoringSpot
    }

    private var emptyBases: [Int] {
        (0..<3).filter { game.runner(onBase: $0) == nil }
    }

    /// Changes whenever the on-field arrangement changes — the runners, the batter, and each trotting
    /// traveler's leg. A single value-based animation on this drives every slide/arrival/fade (and its
    /// reverse on Undo) robustly, whatever triggered the state change.
    private var fieldToken: String {
        let bases = (0..<3).map { game.runner(onBase: $0)?.name ?? "-" }.joined(separator: "|")
        let batter = game.currentBatterLine?.player?.name ?? "-"
        let trot = travelers.map { "\($0.player.name):\($0.leg)" }.joined(separator: ",")
        return bases + "/" + batter + "/" + trot
    }

    var body: some View {
        GeometryReader { geo in
            // Draw the art at the FULL width of whatever space we're given, so its left and right
            // edges touch the screen. Height follows the art's aspect ratio; the space around it in
            // the container just shows through (and the point of the diamond can clip if it's tall).
            let width = geo.size.width
            let height = width / Self.aspect
            ZStack {
                Image("BaseballDiamondCustomZoom")
                    .resizable()
                    .scaledToFit()

                // Invisible tap targets on empty bags (place a runner via the editor).
                ForEach(emptyBases, id: \.self) { base in
                    emptyBaseTarget(base)
                        .position(x: Self.basePositions[base].x * width,
                                  y: Self.basePositions[base].y * height)
                }

                // Player chips — keyed by player, so moves slide and exits fade.
                ForEach(fieldChips) { chip in
                    chipView(chip, width: width, height: height)
                        .position(x: chip.frac.x * width, y: chip.frac.y * height)
                        .zIndex(dragging?.base == chip.base ? 10 : 1)
                        .transition(.opacity)
                }

                // The pitcher, just below the mound (not a baserunner, so it doesn't animate with the token).
                if let pitcher = game.activePitcher {
                    nameChip(pitcher.shortName, background: .orange)
                        .position(x: Self.moundLabel.x * width, y: Self.moundLabel.y * height)
                }

                // Safe/Out buttons docked to each runner awaiting a call.
                ForEach(resolvingBases, id: \.self) { base in
                    resolveButtons(base, width: width, height: height).zIndex(30)
                }
            }
            .animation(.easeInOut(duration: 0.32), value: fieldToken)
            .frame(width: width, height: height)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    // MARK: - Chips

    /// The name chip used on the field. Runners are yellow, the batter blue, the pitcher orange.
    private func nameChip(_ name: String, background: Color, foreground: Color = .black) -> some View {
        Text(name)
            .font(.caption2.bold())
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(.black.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            .fixedSize()
    }

    /// A player chip. The batter is blue and static; a runner is yellow, tap-to-edit, and drag-to-
    /// advance. The view's SHAPE is identical for both so a batter-becomes-runner move animates
    /// cleanly (only the color and the enabled gestures differ). All gestures off while resolving.
    private func chipView(_ chip: FieldChip, width: CGFloat, height: CGFloat) -> some View {
        let base = chip.base
        let isDragging = base != nil && dragging?.base == base
        let dragEnabled = base != nil && !resolving
        // The batter is blue; runners (on a base or scoring) are yellow.
        let isRunner = base != nil || chip.scoring
        return nameChip(chip.player.shortName,
                        background: isRunner ? .yellow : .blue,
                        foreground: isRunner ? .black : .white)
            .opacity(isDragging ? 0.85 : 1)
            .offset(isDragging ? dragging!.translation : .zero)
            .onTapGesture { if let base, !resolving { onTapBase(base) } }
            .gesture(dragGesture(from: base ?? 0, width: width, height: height),
                     including: dragEnabled ? .all : .subviews)
    }

    private func emptyBaseTarget(_ base: Int) -> some View {
        Button { if !resolving { onTapBase(base) } } label: {
            Color.clear.frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dragGesture(from base: Int, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in dragging = RunnerDrag(base: base, translation: value.translation) }
            .onEnded { value in
                dragging = nil
                let start = Self.basePositions[base]
                let drop = CGPoint(x: start.x * width + value.translation.width,
                                   y: start.y * height + value.translation.height)
                if let target = Self.nearestForwardBase(from: base, drop: drop, width: width, height: height) {
                    onDragRunner(base, target)
                }
            }
    }

    /// The forward base (a base ahead of `base`, or home) nearest the drop point — or nil if the drop
    /// wasn't close enough to any of them, which just puts the runner back.
    private static func nearestForwardBase(from base: Int, drop: CGPoint,
                                           width: CGFloat, height: CGFloat) -> Int? {
        var candidates: [(index: Int, point: CGPoint)] = []
        var i = base + 1
        while i <= 2 {
            candidates.append((i, point(basePositions[i], width, height)))
            i += 1
        }
        candidates.append((3, point(homePlate, width, height)))   // 3 = home (a run)

        let hitRadius: CGFloat = 70
        return candidates
            .map { (index: $0.index, dist: hypot(drop.x - $0.point.x, drop.y - $0.point.y)) }
            .filter { $0.dist <= hitRadius }
            .min { $0.dist < $1.dist }?
            .index
    }

    private static func point(_ frac: CGPoint, _ width: CGFloat, _ height: CGFloat) -> CGPoint {
        CGPoint(x: frac.x * width, y: frac.y * height)
    }

    // MARK: - Safe/Out resolution buttons

    /// Where each base's Safe/Out pair sits relative to the bag, as (dx, dy) fractions. Pushed out
    /// into the open grass — up-and-right for 1st, straight up for 2nd, up-and-left for 3rd — so the
    /// pairs clear the chips and each other even with runners on the corners or the 1st/2nd combo.
    private static let resolveOffset: [(dx: CGFloat, dy: CGFloat)] = [
        (0.10, -0.13),   // 1st → toward right field
        (0.0,  -0.17),   // 2nd → straight up into center
        (-0.23, -0.02),  // 3rd → out to the runner's LEFT at his level, clear of his name plate
    ]

    private func resolveButtons(_ base: Int, width: CGFloat, height: CGFloat) -> some View {
        let anchor = Self.resolveAnchor(base)
        return HStack(spacing: 6) {
            resolveButton("Out", .red) { onResolve(base, false) }
            resolveButton("Safe", .green) { onResolve(base, true) }
        }
        .position(x: anchor.x * width, y: anchor.y * height)
    }

    /// Where a base's Safe/Out pair sits, as fractions of the artwork. Bases 0/1/2 push out into the
    /// grass off their bag; base 3 is the play at the plate — parked just to the RIGHT of the runner
    /// holding at home, in the open first-base-side infield, clear of the pitcher and the runner (both
    /// of which sit center or left).
    private static func resolveAnchor(_ base: Int) -> CGPoint {
        guard (0..<3).contains(base) else {
            return CGPoint(x: homePlate.x + 0.185, y: homePlate.y - 0.075)
        }
        let frac = basePositions[base], off = resolveOffset[base]
        return CGPoint(x: frac.x + off.dx, y: frac.y + off.dy)
    }

    private func resolveButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// The runner being dragged: which base he started on, and the finger's translation so far.
private struct RunnerDrag {
    let base: Int
    var translation: CGSize
}
