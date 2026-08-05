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

    /// Optional batting stance: "LH" or "RH".
    var battingStance: String?

    /// Compact form for tight spots like the base chips on the field: "James Heatherly" reads as
    /// "J.Heatherly". A one-word name is left alone.
    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1, let initial = parts.first?.first else { return name }
        return "\(initial).\(parts.dropFirst().joined(separator: " "))"
    }

    /// Optional imported portrait photo for the player's baseball card, stored as a small square
    /// thumbnail (see TeamLogo.squareThumbnail). nil = no photo yet.
    var photoData: Data?

    /// Which baseball-card template this player's card uses (CardTemplateID rawValue). nil = the
    /// default "Classic" template.
    var cardTemplate: String?

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
        battingStance: String? = nil,
        photoData: Data? = nil,
        cardTemplate: String? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.jerseyNumber = jerseyNumber
        self.battingStance = battingStance
        self.photoData = photoData
        self.cardTemplate = cardTemplate
        self.dateAdded = dateAdded
    }
}
