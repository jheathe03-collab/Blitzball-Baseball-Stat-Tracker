import Foundation

/// Pure ghost-runner base-advancement math. Bases are three slots (index 0/1/2 = 1st/2nd/3rd),
/// each holding an opaque runner **token** (`Int?`) or nil. The live game supplies each runner's
/// lineup index as its token, then maps the returned `scored` tokens back to players to credit
/// runs. Kept pure so it can be unit-tested.
public enum BaseRunning {

    /// A hit advances EVERY runner (and the batter, from home) by `baseCount` bases
    /// (single=1, double=2, triple=3, homeRun=4). Anyone reaching home (base 4+) scores.
    /// Returns the new base occupancy and the tokens that scored.
    public static func advanceOnHit(
        bases: [Int?],
        batter: Int,
        baseCount: Int
    ) -> (bases: [Int?], scored: [Int]) {
        var newBases: [Int?] = [nil, nil, nil]
        var scored: [Int] = []

        // Existing runners: base position is index + 1 (1st=1, 2nd=2, 3rd=3).
        for index in 0..<3 {
            guard let token = bases[index] else { continue }
            let newPosition = (index + 1) + baseCount
            if newPosition >= 4 {
                scored.append(token)
            } else {
                newBases[newPosition - 1] = token
            }
        }

        // The batter starts at home (position 0).
        let batterPosition = baseCount
        if batterPosition >= 4 {
            scored.append(batter)          // home run
        } else {
            newBases[batterPosition - 1] = batter
        }

        return (newBases, scored)
    }

    /// A walk/HBP puts the batter on 1st and pushes runners ONLY when forced. Bases loaded ⇒ the
    /// runner on 3rd is forced home and scores.
    public static func advanceOnWalk(
        bases: [Int?],
        batter: Int
    ) -> (bases: [Int?], scored: [Int]) {
        var newBases = bases
        var scored: [Int] = []

        if newBases[0] != nil {                 // 1st occupied → its runner is forced to 2nd
            if newBases[1] != nil {             // 2nd occupied → forced to 3rd
                if let onThird = newBases[2] {   // 3rd occupied → forced home (scores)
                    scored.append(onThird)
                }
                newBases[2] = newBases[1]
            }
            newBases[1] = newBases[0]
        }
        newBases[0] = batter

        return (newBases, scored)
    }
}
