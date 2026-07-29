//
//  CardRenderPreview.swift
//  Blitzball Stat TrackerTests
//
//  A dev-only harness: renders a card template's front/back to images (via ImageRenderer) using
//  sample data. Each render is both attached to the test result AND written as a PNG to
//  `/tmp/blitzcards/`, so a design can be eyeballed straight from disk without running the app.
//

import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import Blitzball_Stat_Tracker

final class CardRenderPreview: XCTestCase {

    /// Where the PNGs land. The simulator writes straight through to the host filesystem.
    private static let outputDirectory = URL(fileURLWithPath: "/tmp/blitzcards", isDirectory: true)

    @MainActor
    func testRenderCards() throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        let container = try ModelContainer(
            for: Player.self, Team.self, Game.self, GameStatLine.self, Season.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let team = Team(name: "Blue Jays", logoName: "Sharks")
        let player = Player(name: "Fred McGriff", jerseyNumber: 27)
        team.players.append(player)
        ctx.insert(team)
        player.photoData = Self.samplePhoto()

        attach(TacoStyleCardFront(player: player), name: "taco_front")
        attach(TacoStyleCardBack(player: player), name: "taco_back")
        // Crops render bigger in a review pane than the tall 2:3 card does, so fine detail can
        // actually be judged.
        attachBand(TacoStyleCardFront(player: player), name: "taco_front_lower", from: 320, to: 480)
        attachBand(TacoStyleCardFront(player: player), name: "taco_front_upper", from: 0, to: 160)
    }

    @MainActor
    private func attach<V: View>(_ view: V, name: String) {
        let framed = view.frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
        render(framed, name: name)
    }

    /// Renders a horizontal band of the card (design-space y `from`…`to`) at full detail.
    @MainActor
    private func attachBand<V: View>(_ view: V, name: String, from: CGFloat, to: CGFloat) {
        let band = view
            .frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
            .offset(y: -from)
            .frame(width: CardMetrics.nativeWidth, height: to - from, alignment: .top)
            .clipped()
        render(band, name: name)
    }

    @MainActor
    private func render<V: View>(_ view: V, name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let ui = renderer.uiImage else { XCTFail("render failed for \(name)"); return }

        let attachment = XCTAttachment(image: ui)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let data = ui.pngData() else { XCTFail("png encode failed for \(name)"); return }
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        do { try data.write(to: url) } catch { XCTFail("write failed for \(name): \(error)") }
    }

    /// A stand-in portrait so the photo area isn't just a placeholder. Deliberately a pale sky over
    /// a dark field, so overlaid text can be judged against both a light and a dark backdrop.
    private static func samplePhoto() -> Data {
        let size = CGSize(width: 240, height: 320)
        return UIGraphicsImageRenderer(size: size).image { c in
            let colors = [UIColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1).cgColor,
                          UIColor(red: 0.30, green: 0.34, blue: 0.26, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            c.cgContext.drawLinearGradient(gradient, start: .zero,
                                           end: CGPoint(x: 0, y: size.height), options: [])
        }.jpegData(compressionQuality: 0.85)!
    }
}
