import Foundation
import SwiftData

/// A player in your league.
///
/// The `@Model` macro is SwiftData's magic word: it turns this ordinary class into something
/// that gets saved to the device's database automatically. Every property below becomes a
/// column that persists between app launches — no save button, no file handling on your part.
///
/// (This class replaces the template's throwaway `Item`.)
@Model
final class Player {

    /// The player's name. `@Attribute(.unique)`-free for now, so duplicates are allowed —
    /// two "Mike"s on different teams is fine.
    var name: String

    /// Optional jersey number. `Int?` (the `?`) means "an Int OR nothing" — a player might
    /// not have a number yet. This is a Swift *optional*.
    var jerseyNumber: Int?

    // A player's career batting/pitching aren't stored — they're COMPUTED by summing this
    // player's finished-game stat lines (see Player+Career.swift). "Games are the source."

    /// The teams this player belongs to. Many-to-many: a player can be on multiple teams
    /// (e.g. across seasons/leagues), and each team has many players. `Team.players` is the
    /// other side of this relationship. Defaults to empty, so the initializer below ignores it.
    @Relationship(inverse: \Team.players) var teams: [Team] = []

    /// Every per-game stat line for this player. (Inverse of `GameStatLine.player`.) A player's
    /// career stats will be the sum of these once we wire the rollup.
    var gameStatLines: [GameStatLine] = []

    /// When this player was added. Handy for sorting the list by "newest first" later.
    var dateAdded: Date

    /// An initializer describes how to make a new Player. The defaults mean you can create one
    /// with just `Player(name: "Mike")` and everything else starts empty/zeroed.
    init(
        name: String,
        jerseyNumber: Int? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.jerseyNumber = jerseyNumber
        self.dateAdded = dateAdded
    }
}
