//
//  CardArtTimingTests.swift
//  Blitzball Stat TrackerTests
//
//  Times the one-off artwork processing that RibbonArt/TacoArt do on first use. Both run lazily on
//  whichever thread first touches a card, so whatever these cost lands as a hitch the first time the
//  card or the template picker appears.
//

import XCTest
@testable import Blitzball_Stat_Tracker

final class CardArtTimingTests: XCTestCase {

    /// NOTE: run this with `SWIFT_OPTIMIZATION_LEVEL=-O` to get a number that means anything — this
    /// is pixel-bound work, and an unoptimised Debug build is ~30x slower than what actually ships.
    func testArtworkProcessingCost() {
        var elapsed: [String: Double] = [:]

        var start = Date()
        _ = RibbonArt.silhouette
        elapsed["RibbonArt (Vintage)"] = Date().timeIntervalSince(start)

        start = Date()
        let taco = TacoArt.layers
        elapsed["TacoArt (Taco Style)"] = Date().timeIntervalSince(start)

        // Also a guard that the artwork still resolves at all — a renamed asset or a redraw that
        // breaks the region detection would surface here rather than as a blank card.
        XCTAssertNotNil(RibbonArt.silhouette, "Vintage ribbon artwork failed to resolve")
        XCTAssertNotNil(taco, "Taco Style frame artwork failed to resolve")
        XCTAssertGreaterThan(taco?.photoWindowRect.width ?? 0, 0.3, "photo window looks wrong")
        XCTAssertGreaterThan(taco?.badgeRect.width ?? 0, 0.05, "team badge was not located")

        let report = elapsed.sorted { $0.value > $1.value }
            .map { String(format: "%-22@ %7.0f ms", $0.key as NSString, $0.value * 1000) }
            .joined(separator: "\n")
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: "/tmp/blitzcards"), withIntermediateDirectories: true)
        try? report.write(toFile: "/tmp/blitzcards/timing.txt", atomically: true, encoding: .utf8)
    }
}
