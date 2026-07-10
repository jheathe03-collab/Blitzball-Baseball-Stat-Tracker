import Foundation

/// Baseball has its own display conventions, and they matter for the app to "feel right":
///   • Rate stats like AVG/OBP/SLG/OPS/BAA show 3 decimals with NO leading zero: `.312`, `1.021`
///   • ERA and WHIP show 2 decimals WITH the leading zero: `3.45`, `0.98`
///
/// Keeping this formatting in one place (separate from the math) means the UI just asks for a
/// nicely-formatted string and never re-implements these rules.
public enum StatFormat {

    /// Format a rate stat the "baseball way": 3 decimals, and drop the leading zero if < 1.
    /// `0.312 -> ".312"`, `1.0213 -> "1.021"`.
    public static func rate(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        let text = String(format: "%.3f", rounded)
        if rounded < 1 && text.hasPrefix("0") {
            return String(text.dropFirst()) // "0.312" -> ".312"
        }
        return text
    }

    /// Format ERA/WHIP-style numbers: 2 decimals, keep the leading zero. `3.4 -> "3.40"`.
    public static func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Format a K/BB ratio, which may be undefined (nil) when there are no walks.
    /// `nil -> "∞"`.
    public static func ratio(_ value: Double?) -> String {
        guard let value else { return "∞" }
        return ratio(value)
    }

    /// Format a fraction as a percentage: `0.104 -> "10.4%"`.
    public static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
