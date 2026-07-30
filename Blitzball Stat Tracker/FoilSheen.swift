//
//  FoilSheen.swift
//  Blitzball Stat Tracker
//
//  The holographic-card hook. Nothing in the app uses it yet — every shipping template is matte —
//  but the plumbing lives here so that a future foil design (the plan: a holographic card only the
//  league MVP gets) is a one-line change rather than a retrofit through the carousel.
//

import SwiftUI

extension CardTemplateID {
    /// Whether this template's card has a holographic finish — a sheen that rakes across the art as
    /// the card is tilted.
    ///
    /// Written as an exhaustive switch rather than `return false` on purpose: adding a new template
    /// case makes this a compile error, which forces whoever adds a design to decide whether it's
    /// foil instead of silently inheriting "no".
    var hasFoilFinish: Bool {
        switch self {
        case .classic, .wood, .vintage, .allStar,
             .goldStandard, .retroStripe, .neon90s, .tacoStyle:
            return false
        }
    }
}

/// A raking specular band that slides across the card as it's tilted, the way light moves over a
/// foil-stamped card when you turn it in your hand.
///
/// Driven by the live tilt angles rather than by time — a sheen that animates on its own reads as a
/// screen effect, whereas one that tracks the tilt reads as a property of the card itself.
struct FoilSheen: View {
    /// Tilt around the vertical axis, in degrees (the left/right lean).
    let yAngle: Double
    /// Tilt around the horizontal axis, in degrees (the top/bottom lean).
    let xAngle: Double
    /// The tilt angle at which the sheen reaches the end of its travel.
    var maxAngle: Double = 22

    var body: some View {
        let horizontal = clamped(yAngle)
        let vertical = clamped(xAngle)
        LinearGradient(
            colors: [.clear,
                     .white.opacity(0.50),
                     .cyan.opacity(0.35),
                     .pink.opacity(0.35),
                     .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .offset(x: CGFloat(horizontal) * 190, y: CGFloat(vertical) * 90)
        // Additive, so the sheen brightens the artwork underneath instead of tinting over it.
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Normalises an angle to -1…1 so the offsets above are in "fractions of full travel".
    private func clamped(_ angle: Double) -> Double {
        max(-1, min(1, angle / maxAngle))
    }
}
