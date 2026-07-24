//
//  FlipCard.swift
//  Blitzball Stat Tracker
//
//  A reusable two-sided flip card: tap to rotate front↔back around the Y axis. Technique per
//  https://swdevnotes.com/swift/2021/flip-card-in-swiftui/ — each face rotates with the same angle,
//  and a 90° opacity threshold hides the "wrong" face through the midpoint so you never see mirrored
//  or backwards content. The back is pre-offset by 180° so its text reads correctly when face-up.
//

import SwiftUI

struct FlipCard<Front: View, Back: View>: View {
    @State private var flipped = false
    let front: Front
    let back: Back

    init(@ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.front = front()
        self.back = back()
    }

    private var angle: Double { flipped ? 180 : 0 }

    var body: some View {
        ZStack {
            front.modifier(CardFace(angle: angle, isBack: false))
            back.modifier(CardFace(angle: angle, isBack: true))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.5)) { flipped.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to flip the card")
    }
}

/// Rotates one face by the shared angle and shows it only on its half of the flip (front while
/// angle < 90°, back once past 90°). Conforms to `Animatable` so `angle` animates continuously —
/// that's what lets the opacity swap land exactly at the 90° edge-on midpoint.
private struct CardFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let visible = isBack ? angle >= 90 : angle < 90
        return content
            .opacity(visible ? 1 : 0)
            .rotation3DEffect(.degrees(isBack ? angle + 180 : angle),
                              axis: (x: 0, y: 1, z: 0),
                              perspective: 0.3)
    }
}
