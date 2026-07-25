//
//  CardRenderPreview.swift
//  Blitzball Stat TrackerTests
//
//  A dev-only harness: renders a card template's front/back to images (via ImageRenderer) using
//  sample data and attaches them to the test result, so a design can be eyeballed from the exported
//  attachment without running the whole app.
//

import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import Blitzball_Stat_Tracker

final class CardRenderPreview: XCTestCase {

    @MainActor
    func testRenderCards() throws {
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

        attach(AllStarCardFront(player: player), name: "allstar_front")
        attach(AllStarCardBack(player: player), name: "allstar_back")
    }

    @MainActor
    private func attach<V: View>(_ view: V, name: String) {
        let framed = view.frame(width: CardMetrics.nativeWidth, height: CardMetrics.nativeHeight)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let ui = renderer.uiImage else { XCTFail("render failed for \(name)"); return }
        let attachment = XCTAttachment(image: ui)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A stand-in portrait so the photo area isn't just a placeholder.
    private static func samplePhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320)).image { c in
            UIColor(red: 0.28, green: 0.42, blue: 0.66, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
        }.jpegData(compressionQuality: 0.85)!
    }
}
