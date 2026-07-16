//
//  BlobCoder.swift
//  Blitzball Stat Tracker
//
//  Tiny JSON encode/decode helper for storing Codable value types (GameSettings, BattingStats,
//  PitchingStats) as `Data` blobs on our @Model objects.
//
//  WHY BLOBS: SwiftData treats a stored Codable struct as a "composite" attribute whose STRUCTURE
//  is part of the schema — so adding a field to it (a new rule, a new stat) changes the schema and
//  can fail to load the old store (data loss). Stored as `Data`, the schema is just "a blob" and
//  never changes, so we can add fields freely. The structs decode leniently (missing keys default),
//  so old blobs still load with the new fields zeroed out.
//

import Foundation

enum BlobCoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data) -> T? {
        try? decoder.decode(T.self, from: data)
    }
}
