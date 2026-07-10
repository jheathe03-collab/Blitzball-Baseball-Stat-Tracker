import Foundation

/// A player's batting line for some span of games (a game, a season, a career — whatever
/// you sum up).
///
/// The BIG IDEA: we only store the *raw counting stats* a scorekeeper actually writes down.
/// Every "rate" stat (AVG, OBP, SLG, OPS, ...) is a **computed property** — Swift recalculates
/// it every time you read it, so the derived numbers can never drift out of sync with the raw
/// data. This is exactly the "auto-populate" behavior you asked for.
///
/// `Codable` lets it save/load; `Hashable` lets SwiftUI tell instances apart; `Sendable` means
/// it's safe to pass between concurrent tasks (Swift 6 concurrency).
public struct BattingStats: Codable, Hashable, Sendable {

    // MARK: - Raw counting stats (the only things we store)

    /// Plate appearances: every time the batter completed a turn at the plate (includes walks, HBP, etc.).
    public var plateAppearances: Int
    /// At-bats: plate appearances that "count" toward average (excludes walks, HBP, sacrifices).
    public var atBats: Int
    /// Total hits (singles + doubles + triples + home runs).
    public var hits: Int
    /// Of those hits, how many were doubles.
    public var doubles: Int
    /// Of those hits, how many were triples.
    public var triples: Int
    /// Of those hits, how many were home runs.
    public var homeRuns: Int
    /// Runs batted in. A pure counting stat (not used by AVG/OBP/SLG) that we track and total.
    public var rbi: Int
    /// Walks (bases on balls).
    public var walks: Int
    /// Times hit by a pitch.
    public var hitByPitch: Int
    /// Strikeouts.
    public var strikeouts: Int
    /// Sacrifice flies (an out that scores a runner — doesn't count as an at-bat, but does affect OBP).
    public var sacrificeFlies: Int

    /// A memberwise initializer with sensible defaults, so you can create an empty line with
    /// `BattingStats()` and fill in only what you have.
    public init(
        plateAppearances: Int = 0,
        atBats: Int = 0,
        hits: Int = 0,
        doubles: Int = 0,
        triples: Int = 0,
        homeRuns: Int = 0,
        rbi: Int = 0,
        walks: Int = 0,
        hitByPitch: Int = 0,
        strikeouts: Int = 0,
        sacrificeFlies: Int = 0
    ) {
        self.plateAppearances = plateAppearances
        self.atBats = atBats
        self.hits = hits
        self.doubles = doubles
        self.triples = triples
        self.homeRuns = homeRuns
        self.rbi = rbi
        self.walks = walks
        self.hitByPitch = hitByPitch
        self.strikeouts = strikeouts
        self.sacrificeFlies = sacrificeFlies
    }

    // MARK: - Derived building blocks

    /// Singles aren't stored separately — they're whatever's left after the extra-base hits.
    public var singles: Int {
        hits - doubles - triples - homeRuns
    }

    /// Total bases: 1 per single, 2 per double, 3 per triple, 4 per home run.
    public var totalBases: Int {
        singles + (2 * doubles) + (3 * triples) + (4 * homeRuns)
    }

    // MARK: - Computed rate stats (these are what "auto-populate")

    /// Batting Average = Hits / At-Bats.
    public var battingAverage: Double {
        divide(hits, by: atBats)
    }

    /// On-Base Percentage = (H + BB + HBP) / (AB + BB + HBP + SF).
    public var onBasePercentage: Double {
        divide(hits + walks + hitByPitch,
               by: atBats + walks + hitByPitch + sacrificeFlies)
    }

    /// Slugging Percentage = Total Bases / At-Bats.
    public var sluggingPercentage: Double {
        divide(totalBases, by: atBats)
    }

    /// OPS = On-Base Percentage + Slugging Percentage.
    public var onBasePlusSlugging: Double {
        onBasePercentage + sluggingPercentage
    }

    /// Walk rate = Walks / Plate Appearances (a fraction, e.g. 0.10 == 10%).
    public var walkRate: Double {
        divide(walks, by: plateAppearances)
    }

    /// Strikeout rate = Strikeouts / Plate Appearances.
    public var strikeoutRate: Double {
        divide(strikeouts, by: plateAppearances)
    }
}

// MARK: - Combining lines

extension BattingStats {
    /// Add two batting lines together (e.g. to total a player's games into a season).
    /// This is what lets a season be "the sum of its games" for free.
    public static func + (lhs: BattingStats, rhs: BattingStats) -> BattingStats {
        BattingStats(
            plateAppearances: lhs.plateAppearances + rhs.plateAppearances,
            atBats: lhs.atBats + rhs.atBats,
            hits: lhs.hits + rhs.hits,
            doubles: lhs.doubles + rhs.doubles,
            triples: lhs.triples + rhs.triples,
            homeRuns: lhs.homeRuns + rhs.homeRuns,
            rbi: lhs.rbi + rhs.rbi,
            walks: lhs.walks + rhs.walks,
            hitByPitch: lhs.hitByPitch + rhs.hitByPitch,
            strikeouts: lhs.strikeouts + rhs.strikeouts,
            sacrificeFlies: lhs.sacrificeFlies + rhs.sacrificeFlies
        )
    }
}

/// A tiny helper: integer division that returns 0 instead of crashing when the denominator is 0.
/// (A brand-new player with 0 at-bats should show a .000 average, not blow up the app.)
func divide(_ numerator: Int, by denominator: Int) -> Double {
    guard denominator > 0 else { return 0 }
    return Double(numerator) / Double(denominator)
}
