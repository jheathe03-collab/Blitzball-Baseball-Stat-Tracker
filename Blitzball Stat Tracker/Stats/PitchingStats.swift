import Foundation

/// A player's pitching line for some span of games.
///
/// Same idea as `BattingStats`: store only raw counts, compute the rates.
///
/// One baseball subtlety we handle correctly: **innings are really thirds of an inning.**
/// "5.1 innings" means 5 innings and 1 out — NOT 5.1 in the decimal sense. To avoid that
/// trap, we store `outsRecorded` (an integer) and derive innings from it (3 outs = 1 inning).
public struct PitchingStats: Codable, Hashable, Sendable {

    // MARK: - Raw counting stats

    /// Total outs the pitcher recorded. 27 outs == 9 innings.
    public var outsRecorded: Int
    /// Earned runs allowed (runs that scored without the help of an error).
    public var earnedRuns: Int
    /// Total runs allowed (the box-score "R"). For now every run counts as earned, so this
    /// moves in lockstep with earnedRuns.
    public var runsAllowed: Int
    /// Hits allowed.
    public var hitsAllowed: Int
    /// Home runs allowed.
    public var homeRunsAllowed: Int
    /// Walks allowed.
    public var walksAllowed: Int
    /// Strikeouts recorded.
    public var strikeouts: Int
    /// Strikeouts LOOKING (called third strike) recorded by the pitcher — a subset of `strikeouts`.
    public var strikeoutsLooking: Int
    /// At-bats against (used for Batting Average Against).
    public var atBatsAgainst: Int
    /// Saves recorded. A counting stat we track and total (not used by ERA/WHIP/etc.).
    public var saves: Int
    /// Quality starts (6+ IP with 3 or fewer earned runs). A counting stat we track and total.
    public var qualityStarts: Int

    public init(
        outsRecorded: Int = 0,
        earnedRuns: Int = 0,
        runsAllowed: Int = 0,
        hitsAllowed: Int = 0,
        homeRunsAllowed: Int = 0,
        walksAllowed: Int = 0,
        strikeouts: Int = 0,
        strikeoutsLooking: Int = 0,
        atBatsAgainst: Int = 0,
        saves: Int = 0,
        qualityStarts: Int = 0
    ) {
        self.outsRecorded = outsRecorded
        self.earnedRuns = earnedRuns
        self.runsAllowed = runsAllowed
        self.hitsAllowed = hitsAllowed
        self.homeRunsAllowed = homeRunsAllowed
        self.walksAllowed = walksAllowed
        self.strikeouts = strikeouts
        self.strikeoutsLooking = strikeoutsLooking
        self.atBatsAgainst = atBatsAgainst
        self.saves = saves
        self.qualityStarts = qualityStarts
    }

    // MARK: - Derived building blocks

    /// Innings pitched as a true number (e.g. 16 outs == 5.333… innings).
    public var inningsPitched: Double {
        Double(outsRecorded) / 3.0
    }

    // MARK: - Computed rate stats

    /// ERA = 9 × Earned Runs / Innings Pitched. (Earned runs per 9 innings.)
    public var earnedRunAverage: Double {
        guard outsRecorded > 0 else { return 0 }
        return 9.0 * Double(earnedRuns) / inningsPitched
    }

    /// WHIP = (Walks + Hits) / Innings Pitched. (Baserunners allowed per inning.)
    public var walksAndHitsPerInning: Double {
        guard outsRecorded > 0 else { return 0 }
        return Double(walksAllowed + hitsAllowed) / inningsPitched
    }

    /// Strikeout-to-Walk ratio = Strikeouts / Walks.
    /// Undefined when there are no walks, so we return `nil` there — the UI can show "∞" or "—".
    /// (This is a good first taste of Swift *optionals*: a value that might be absent.)
    public var strikeoutToWalkRatio: Double? {
        guard walksAllowed > 0 else { return nil }
        return Double(strikeouts) / Double(walksAllowed)
    }

    /// Batting Average Against = Hits Allowed / At-Bats Against.
    public var battingAverageAgainst: Double {
        divide(hitsAllowed, by: atBatsAgainst)
    }
}

// MARK: - Combining lines

extension PitchingStats {
    /// Add two pitching lines together (e.g. total a pitcher's outings into a season).
    public static func + (lhs: PitchingStats, rhs: PitchingStats) -> PitchingStats {
        PitchingStats(
            outsRecorded: lhs.outsRecorded + rhs.outsRecorded,
            earnedRuns: lhs.earnedRuns + rhs.earnedRuns,
            runsAllowed: lhs.runsAllowed + rhs.runsAllowed,
            hitsAllowed: lhs.hitsAllowed + rhs.hitsAllowed,
            homeRunsAllowed: lhs.homeRunsAllowed + rhs.homeRunsAllowed,
            walksAllowed: lhs.walksAllowed + rhs.walksAllowed,
            strikeouts: lhs.strikeouts + rhs.strikeouts,
            strikeoutsLooking: lhs.strikeoutsLooking + rhs.strikeoutsLooking,
            atBatsAgainst: lhs.atBatsAgainst + rhs.atBatsAgainst,
            saves: lhs.saves + rhs.saves,
            qualityStarts: lhs.qualityStarts + rhs.qualityStarts
        )
    }
}

// MARK: - Lenient decoding (this is what makes adding a stat data-safe)

extension PitchingStats {
    // Blobs saved before a stat existed lack its key. Decoding each field with `decodeIfPresent`
    // (default 0) means old lines still load with all their real stats intact and any NEW stat at 0
    // — instead of the decode failing and zeroing the whole line. Encoding stays auto-synthesized.
    private enum CodingKeys: String, CodingKey {
        case outsRecorded, earnedRuns, runsAllowed, hitsAllowed, homeRunsAllowed
        case walksAllowed, strikeouts, strikeoutsLooking, atBatsAgainst, saves, qualityStarts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outsRecorded = try c.decodeIfPresent(Int.self, forKey: .outsRecorded) ?? 0
        earnedRuns = try c.decodeIfPresent(Int.self, forKey: .earnedRuns) ?? 0
        runsAllowed = try c.decodeIfPresent(Int.self, forKey: .runsAllowed) ?? 0
        hitsAllowed = try c.decodeIfPresent(Int.self, forKey: .hitsAllowed) ?? 0
        homeRunsAllowed = try c.decodeIfPresent(Int.self, forKey: .homeRunsAllowed) ?? 0
        walksAllowed = try c.decodeIfPresent(Int.self, forKey: .walksAllowed) ?? 0
        strikeouts = try c.decodeIfPresent(Int.self, forKey: .strikeouts) ?? 0
        strikeoutsLooking = try c.decodeIfPresent(Int.self, forKey: .strikeoutsLooking) ?? 0
        atBatsAgainst = try c.decodeIfPresent(Int.self, forKey: .atBatsAgainst) ?? 0
        saves = try c.decodeIfPresent(Int.self, forKey: .saves) ?? 0
        qualityStarts = try c.decodeIfPresent(Int.self, forKey: .qualityStarts) ?? 0
    }
}
