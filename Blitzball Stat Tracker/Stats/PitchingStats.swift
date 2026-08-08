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
    /// Batters faced — every plate appearance completed against this pitcher (BF). Always ≥ at-bats
    /// against, since it also counts walks, HBP, and sacrifices.
    public var battersFaced: Int
    /// Stolen bases allowed while this pitcher was on the mound (SB).
    public var stolenBasesAllowed: Int
    /// Runners caught stealing while this pitcher was on the mound (CS).
    public var caughtStealing: Int
    /// Runners picked off while this pitcher was on the mound (PIK).
    public var pickoffs: Int
    /// Wild pitches charged to this pitcher (WP).
    public var wildPitches: Int
    /// Total strikes thrown (TS) — called/swinging strikes, fouls, and balls put in play. Only
    /// accrues when Record Balls and Strikes is on; 0 otherwise.
    public var totalStrikes: Int
    /// Total balls thrown (TB). Only accrues when Record Balls and Strikes is on; 0 otherwise.
    public var totalBalls: Int
    /// Batters hit by a pitch (HBP allowed). Each is one pitch, so it feeds Total Pitches.
    public var hitBatters: Int
    /// Saves recorded. A counting stat we track and total (not used by ERA/WHIP/etc.).
    public var saves: Int
    /// Quality starts (6+ IP with 3 or fewer earned runs). A counting stat we track and total.
    public var qualityStarts: Int
    /// Blown saves (a lead the pitcher was protecting was lost). A counting stat we track and total.
    public var blownSaves: Int

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
        battersFaced: Int = 0,
        stolenBasesAllowed: Int = 0,
        caughtStealing: Int = 0,
        pickoffs: Int = 0,
        wildPitches: Int = 0,
        totalStrikes: Int = 0,
        totalBalls: Int = 0,
        hitBatters: Int = 0,
        saves: Int = 0,
        qualityStarts: Int = 0,
        blownSaves: Int = 0
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
        self.battersFaced = battersFaced
        self.stolenBasesAllowed = stolenBasesAllowed
        self.caughtStealing = caughtStealing
        self.pickoffs = pickoffs
        self.wildPitches = wildPitches
        self.totalStrikes = totalStrikes
        self.totalBalls = totalBalls
        self.hitBatters = hitBatters
        self.saves = saves
        self.qualityStarts = qualityStarts
        self.blownSaves = blownSaves
    }

    // MARK: - Derived building blocks

    /// Innings pitched as a true number (e.g. 16 outs == 5.333… innings).
    public var inningsPitched: Double {
        Double(outsRecorded) / 3.0
    }

    /// Total pitches thrown (#P): every ball and strike, plus each hit-by-pitch (a pitch that's
    /// neither a ball nor a strike). Only meaningful when Record Balls and Strikes is on, since TS/TB
    /// only accrue then.
    public var totalPitches: Int {
        totalStrikes + totalBalls + hitBatters
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
            battersFaced: lhs.battersFaced + rhs.battersFaced,
            stolenBasesAllowed: lhs.stolenBasesAllowed + rhs.stolenBasesAllowed,
            caughtStealing: lhs.caughtStealing + rhs.caughtStealing,
            pickoffs: lhs.pickoffs + rhs.pickoffs,
            wildPitches: lhs.wildPitches + rhs.wildPitches,
            totalStrikes: lhs.totalStrikes + rhs.totalStrikes,
            totalBalls: lhs.totalBalls + rhs.totalBalls,
            hitBatters: lhs.hitBatters + rhs.hitBatters,
            saves: lhs.saves + rhs.saves,
            qualityStarts: lhs.qualityStarts + rhs.qualityStarts,
            blownSaves: lhs.blownSaves + rhs.blownSaves
        )
    }

    /// Subtract one line from another, flooring at zero — used to UNAPPLY a play's credit
    /// when it is re-classified or moved to another player. A play that was actually applied can
    /// never underflow; the floor is there so a bug can't produce negative stats.
    public static func - (lhs: PitchingStats, rhs: PitchingStats) -> PitchingStats {
        PitchingStats(
            outsRecorded: max(0, lhs.outsRecorded - rhs.outsRecorded),
            earnedRuns: max(0, lhs.earnedRuns - rhs.earnedRuns),
            runsAllowed: max(0, lhs.runsAllowed - rhs.runsAllowed),
            hitsAllowed: max(0, lhs.hitsAllowed - rhs.hitsAllowed),
            homeRunsAllowed: max(0, lhs.homeRunsAllowed - rhs.homeRunsAllowed),
            walksAllowed: max(0, lhs.walksAllowed - rhs.walksAllowed),
            strikeouts: max(0, lhs.strikeouts - rhs.strikeouts),
            strikeoutsLooking: max(0, lhs.strikeoutsLooking - rhs.strikeoutsLooking),
            atBatsAgainst: max(0, lhs.atBatsAgainst - rhs.atBatsAgainst),
            battersFaced: max(0, lhs.battersFaced - rhs.battersFaced),
            stolenBasesAllowed: max(0, lhs.stolenBasesAllowed - rhs.stolenBasesAllowed),
            caughtStealing: max(0, lhs.caughtStealing - rhs.caughtStealing),
            pickoffs: max(0, lhs.pickoffs - rhs.pickoffs),
            wildPitches: max(0, lhs.wildPitches - rhs.wildPitches),
            totalStrikes: max(0, lhs.totalStrikes - rhs.totalStrikes),
            totalBalls: max(0, lhs.totalBalls - rhs.totalBalls),
            hitBatters: max(0, lhs.hitBatters - rhs.hitBatters),
            saves: max(0, lhs.saves - rhs.saves),
            qualityStarts: max(0, lhs.qualityStarts - rhs.qualityStarts),
            blownSaves: max(0, lhs.blownSaves - rhs.blownSaves)
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
        case walksAllowed, strikeouts, strikeoutsLooking, atBatsAgainst, saves, qualityStarts, blownSaves
        case battersFaced, stolenBasesAllowed, caughtStealing, pickoffs, wildPitches
        case totalStrikes, totalBalls, hitBatters
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
        battersFaced = try c.decodeIfPresent(Int.self, forKey: .battersFaced) ?? 0
        stolenBasesAllowed = try c.decodeIfPresent(Int.self, forKey: .stolenBasesAllowed) ?? 0
        caughtStealing = try c.decodeIfPresent(Int.self, forKey: .caughtStealing) ?? 0
        pickoffs = try c.decodeIfPresent(Int.self, forKey: .pickoffs) ?? 0
        wildPitches = try c.decodeIfPresent(Int.self, forKey: .wildPitches) ?? 0
        totalStrikes = try c.decodeIfPresent(Int.self, forKey: .totalStrikes) ?? 0
        totalBalls = try c.decodeIfPresent(Int.self, forKey: .totalBalls) ?? 0
        hitBatters = try c.decodeIfPresent(Int.self, forKey: .hitBatters) ?? 0
        saves = try c.decodeIfPresent(Int.self, forKey: .saves) ?? 0
        qualityStarts = try c.decodeIfPresent(Int.self, forKey: .qualityStarts) ?? 0
        blownSaves = try c.decodeIfPresent(Int.self, forKey: .blownSaves) ?? 0
    }
}
