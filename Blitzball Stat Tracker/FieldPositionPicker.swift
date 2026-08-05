//
//  FieldPositionPicker.swift
//  Blitzball Stat Tracker
//
//  The nine defensive spots laid over the park art, each a tappable puck. Shown INLINE on the live
//  game's field during a batted ball's location step (not a separate sheet) so the scorer taps where
//  the ball went on the field they're already looking at.
//
//  Positions are fractions of the drawn image (same technique as `BaseballField`) so they stay glued
//  to the field at any size. For now the puck shows the position's abbreviation; a later game mode
//  swaps in the assigned fielder's name.
//

import SwiftUI

struct FieldPositionPicker: View {
    let onSelect: (FieldPosition) -> Void

    /// Where each fielder stands, as a fraction of the artwork's width/height. Tuned to the
    /// `BaseballDiamondCustomZoom` asset; adjust these together with the art.
    private static let spots: [FieldPosition: CGPoint] = [
        .pitcher:     CGPoint(x: 0.496, y: 0.700),
        .catcher:     CGPoint(x: 0.496, y: 0.905),
        .firstBase:   CGPoint(x: 0.660, y: 0.600),
        .secondBase:  CGPoint(x: 0.585, y: 0.420),
        .thirdBase:   CGPoint(x: 0.345, y: 0.600),
        .shortstop:   CGPoint(x: 0.405, y: 0.420),
        .leftField:   CGPoint(x: 0.270, y: 0.255),
        .centerField: CGPoint(x: 0.496, y: 0.165),
        .rightField:  CGPoint(x: 0.720, y: 0.255),
    ]

    var body: some View {
        // The image sizes itself (scaledToFit within the available width); the overlay's
        // GeometryReader then reports that exact drawn size, so puck fractions line up with the art.
        Image("BaseballDiamondCustomZoom")
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    ForEach(FieldPosition.byNumber, id: \.self) { pos in
                        let spot = Self.spots[pos] ?? CGPoint(x: 0.5, y: 0.5)
                        puck(pos)
                            .position(x: spot.x * geo.size.width,
                                      y: spot.y * geo.size.height)
                    }
                }
            }
    }

    private func puck(_ pos: FieldPosition) -> some View {
        Button { onSelect(pos) } label: {
            Text(pos.abbreviation)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }
}
