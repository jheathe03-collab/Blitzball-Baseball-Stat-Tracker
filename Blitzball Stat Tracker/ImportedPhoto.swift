//
//  ImportedPhoto.swift
//  Blitzball Stat Tracker
//
//  Defensive sanitizer for photo blobs coming in from archive files. Trusted internal writes (the
//  app's own PhotoCropView pipeline) don't need this — they always produce small, well-formed
//  JPEGs. It's the IMPORT boundary — where a user AirDrops / opens a JSON file authored on
//  another device (or hand-edited, or maliciously crafted) — that needs to refuse hostile blobs
//  before they land in a `Player.photoData` and blow up every subsequent card render.
//

import Foundation
import UIKit

enum ImportedPhoto {
    /// Reasonable ceiling for an app-generated photo blob. The crop pipeline produces JPEGs
    /// downscaled to 560px on the long edge at 0.85 quality, which lands around 30–80 KB in
    /// practice. 1 MB gives ~20× headroom for legitimate variance while still catching anything
    /// pathological (a 12MP raw photo would be tens of MB; a decompression bomb, larger).
    static let maxBytes = 1_000_000

    /// Returns the blob unchanged if it's safe to persist, or nil if it should be dropped. Two
    /// checks:
    ///   1. Size cap (see `maxBytes`) — protects against memory-bomb archives.
    ///   2. Decodability via `UIImage(data:)` — if the app can't decode it now, every future
    ///      card render would fail identically. Better to store nil (placeholder portrait) than
    ///      a broken blob that ships to the render path.
    static func sanitized(_ raw: Data?) -> Data? {
        guard let raw else { return nil }
        guard raw.count <= maxBytes else { return nil }
        guard UIImage(data: raw) != nil else { return nil }
        return raw
    }
}
