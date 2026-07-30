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

    // MARK: - Carousel

    /// Renders the card carousel headlessly so its layout can be reviewed without running the app.
    ///
    /// `ImageRenderer` draws a body exactly once, with no `onAppear` and no animation, so the views
    /// take preview-seam initialisers that seed their state directly. The carousel position is a
    /// `Double`, which means a fractional index renders a genuine mid-drag frame.
    @MainActor
    func testRenderCarousel() throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        // The container must stay alive for the whole test: the fixture's players are backed by it,
        // and letting it deallocate invalidates them out from under the renderer.
        let (container, players) = try Self.leagueFixture()
        defer { withExtendedLifetime(container) {} }
        let entries = CardCarouselEntry.build(from: players)
        XCTAssertEqual(entries.count, 11, "fixture should produce 9 rostered + 2 free agents")
        XCTAssertEqual(entries.last?.groupTitle, CardCarouselEntry.freeAgentsTitle,
                       "unrostered players must sort to the end")

        // The fan alone, at the positions worth eyeballing.
        render(fan(entries, at: 0.0), name: "carousel_first")     // clamped at the left end
        render(fan(entries, at: 4.0), name: "carousel_mid")       // a full symmetric fan
        render(fan(entries, at: 8.5), name: "carousel_between")   // mid-drag, crossing a team boundary
        render(fan(entries, at: Double(entries.count - 1)), name: "carousel_last")

        // The whole screen, chrome included — the one to review the design from.
        render(CardCarouselView(previewEntries: entries, previewIndex: 4.0)
                .frame(width: 393, height: 852),
               name: "carousel_screen")

        // The zoomed card with a frozen tilt, to judge the perspective and the shadow offset.
        render(ZStack {
                   Color.black.opacity(0.94)
                   ZoomedCardView(entry: entries[4],
                                  heroWidth: 300,
                                  onPage: { _ in false },
                                  onEdit: {},
                                  previewTilt: CGSize(width: 120, height: -60))
               }
               .frame(width: 393, height: 852),
               name: "carousel_zoomed_tilted")
    }

    @MainActor
    private func fan(_ entries: [CardEntry], at index: Double) -> some View {
        ZStack {
            Color.black.opacity(0.94)
            CardCarouselStack(entries: entries,
                              snappedItem: .constant(index),
                              draggingItem: .constant(index),
                              cardWidth: 244,
                              zoomedIndex: nil,
                              namespace: nil,
                              rasterizes: false,
                              onZoom: { _ in })
        }
        .frame(width: 393, height: 620)
    }

    /// Three teams of three, plus two unrostered players so the "Free Agents" group appears.
    /// Templates are spread across the roster deliberately — `.vintage` and `.tacoStyle` do the
    /// expensive pixel work, so they need to be in the deck for the render to be representative.
    @MainActor
    private static func leagueFixture() throws -> (ModelContainer, [Player]) {
        let container = try ModelContainer(
            for: Player.self, Team.self, Game.self, GameStatLine.self, Season.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let photo = samplePhoto()

        let roster: [(team: String, logo: String, players: [(String, Int, CardTemplateID)])] = [
            ("Hornets", "Hornets", [("Ava Delgado", 3, .vintage),
                                    ("Marcus Webb", 11, .tacoStyle),
                                    ("Ruth Okafor", 7, .classic)]),
            ("Peppers", "Peppers", [("Bo Tran", 21, .wood),
                                    ("Iris Nakamura", 9, .goldStandard),
                                    ("Sal Moreno", 44, .allStar)]),
            ("Sharks", "Sharks", [("Dee Whitfield", 2, .retroStripe),
                                  ("Kip Ferrara", 18, .neon90s),
                                  ("Tomas Reyes", 30, .classic)])
        ]

        var all: [Player] = []
        for entry in roster {
            let team = Team(name: entry.team, logoName: entry.logo)
            ctx.insert(team)
            for (name, number, template) in entry.players {
                let player = Player(name: name, jerseyNumber: number,
                                    cardTemplate: template.rawValue)
                ctx.insert(player)
                player.photoData = photo
                team.players.append(player)
                all.append(player)
            }
        }
        // No team — these must collect at the end of the deck.
        for (name, number) in [("Wendy Cruz", 5), ("Zeke Palmer", 13)] {
            let player = Player(name: name, jerseyNumber: number, cardTemplate: CardTemplateID.wood.rawValue)
            ctx.insert(player)
            all.append(player)
        }
        return (container, all)
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
