//
//  BaseballField.swift
//  Blitzball Stat Tracker
//
//  The live game's field: the custom park art running full width behind the scoring controls, with
//  a tappable chip on each base.
//
//  Base positions are FRACTIONS of the artwork rather than fixed points, so the chips stay glued to
//  the bags at any size — and because the chips live inside the same frame as the image, they scale
//  with it even when the art is overscaled to bleed off the screen edges.
//

import SwiftUI

struct BaseballField: View {
    @Bindable var game: Game
    /// Tapped base index: 0 = first, 1 = second, 2 = third.
    var onTapBase: (Int) -> Void

    /// Where each base sits in `BaseballDiamondCustomZoom`, as a fraction of its width/height.
    /// Measured off the artwork — update these together with the asset.
    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.631, y: 0.653),   // 1st
        CGPoint(x: 0.495, y: 0.488),   // 2nd
        CGPoint(x: 0.372, y: 0.654),   // 3rd
    ]
    private static let homePlate = CGPoint(x: 0.496, y: 0.854)
    /// Just below the pitcher's rubber — clear of the 1st/3rd base line so it reads as the mound.
    private static let moundLabel = CGPoint(x: 0.496, y: 0.72)

    private static let aspect: CGFloat = 2857.0 / 2325.0

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

                ForEach(0..<3, id: \.self) { base in
                    baseChip(base)
                        .position(x: Self.basePositions[base].x * width,
                                  y: Self.basePositions[base].y * height)
                }

                // The pitcher, just below the mound.
                if let pitcher = game.activePitcher {
                    nameChip(pitcher.shortName, background: .orange)
                        .position(x: Self.moundLabel.x * width, y: Self.moundLabel.y * height)
                }

                // The batter at the plate.
                if let batter = game.currentBatterLine?.player {
                    nameChip(batter.shortName, background: .blue, foreground: .white)
                        .position(x: Self.homePlate.x * width, y: Self.homePlate.y * height)
                }
            }
            .frame(width: width, height: height)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    // MARK: - Base chips

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

    private func baseChip(_ base: Int) -> some View {
        let runner = game.runner(onBase: base)
        return Button { onTapBase(base) } label: {
            if let runner {
                nameChip(runner.shortName, background: .yellow)
            } else {
                // Empty: nothing drawn on the bag, but still an invisible tap target so you can
                // place a runner. `contentShape` makes the clear area register taps.
                Color.clear
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}
