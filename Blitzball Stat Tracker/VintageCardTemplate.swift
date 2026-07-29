//
//  VintageCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #3 — "Vintage." Aged-paper stock, a thick green frame with a fine black inner rule
//  around the portrait, the jersey number top-left, the team logo top-right, and a gold swallowtail
//  banner across the base. The player name is set in DS Accent ON that banner — each glyph is placed
//  and rotated along the banner's arc so the name follows the curve.
//
//  The banner is the hand-drawn "Ribbon" image asset. That art is opaque white with black line work,
//  so RibbonArt turns it into a silhouette + line layer at runtime (see below) — which keeps the PNG
//  the single source of truth: redraw it and the card picks up the new shape automatically.
//
//  Everything is laid out in a fixed 320×480 design space (see CardDesignSpace) and then scaled to
//  whatever the card is actually drawn at, so the hand-placed coordinates below hold at any size.
//

import SwiftUI
import UIKit

private enum VintagePalette {
    /// From the mockup.
    static let green     = Color(red: 0.184, green: 0.620, blue: 0.267)   // #2f9e44
    static let gold      = Color(red: 0.796, green: 0.616, blue: 0.188)   // #cb9d30
    /// Shading derived from the gold, for the ribbon's folds and roll.
    static let goldDark  = Color(red: 0.478, green: 0.353, blue: 0.086)
    static let goldLight = Color(red: 0.902, green: 0.749, blue: 0.353)
    static let ink       = Color(red: 0.08,  green: 0.08,  blue: 0.08)
    static let cream     = Color(red: 0.93,  green: 0.90,  blue: 0.80)
    /// Player name on the ribbon, and the jersey number.
    static let maroon    = Color(red: 0.490, green: 0.141, blue: 0.094)   // #7d2418
}

// MARK: - Banner artwork

/// Turns the hand-drawn "Ribbon" asset into two layers the card can actually use.
///
/// The art arrives as opaque white with black line work — no transparency at all — so dropping it
/// straight onto the card would paint a white box over the photo. Instead we flood-fill inward from
/// the border, stopping at the ink: whatever the fill can't reach IS the banner. That yields
///
///   * `silhouette` — the banner's whole footprint, used as a mask for the gold gradient, and
///   * `lines`      — just the drawn line work, laid back over the top.
///
/// Doing this at runtime (once, cached) rather than shipping pre-cut assets means the PNG stays the
/// only thing to edit — redraw the ribbon and both layers regenerate to match.
enum RibbonArt {
    private static let layers: (silhouette: UIImage, lines: UIImage)? = build()

    static var silhouette: UIImage? { layers?.silhouette }
    static var lines: UIImage? { layers?.lines }

    /// Height ÷ width of the source art, so the banner is never placed at a distorted aspect.
    static var aspectRatio: CGFloat {
        guard let image = layers?.silhouette, image.size.width > 0 else { return 362.0 / 965.0 }
        return image.size.height / image.size.width
    }

    private static func build() -> (silhouette: UIImage, lines: UIImage)? {
        guard let source = UIImage(named: "Ribbon")?.cgImage else { return nil }
        let width = source.width, height = source.height
        let count = width * height

        var pixels = [UInt8](repeating: 0, count: count * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Dark == line. Keeping this as a 0…255 coverage rather than a hard yes/no preserves the
        // art's antialiasing, so the finished banner doesn't get jagged edges.
        var coverage = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            let luminance = (0.299 * Double(pixels[i * 4])
                             + 0.587 * Double(pixels[i * 4 + 1])
                             + 0.114 * Double(pixels[i * 4 + 2])) / 255
            coverage[i] = UInt8(max(0, min(1, 1 - luminance)) * 255)
        }

        // Flood fill from every border pixel, passing only through near-white pixels.
        var outside = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        func flood(_ i: Int) {
            if !outside[i] && coverage[i] < 128 { outside[i] = true; stack.append(i) }
        }
        for x in 0..<width { flood(x); flood((height - 1) * width + x) }
        for y in 0..<height { flood(y * width); flood(y * width + width - 1) }
        while let i = stack.popLast() {
            let x = i % width, y = i / width
            if x > 0 { flood(i - 1) }
            if x < width - 1 { flood(i + 1) }
            if y > 0 { flood(i - width) }
            if y < height - 1 { flood(i + width) }
        }

        // Both layers are premultiplied: white-on-alpha for the mask, black-on-alpha for the lines.
        var silhouette = [UInt8](repeating: 0, count: count * 4)
        var lines = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let ink = coverage[i]
            // Inside the banner it's fully opaque; outside, an antialiased edge pixel still
            // contributes its ink coverage so the silhouette ends flush with the drawn outline.
            let alpha = outside[i] ? ink : 255
            silhouette[i * 4] = alpha; silhouette[i * 4 + 1] = alpha
            silhouette[i * 4 + 2] = alpha; silhouette[i * 4 + 3] = alpha
            lines[i * 4 + 3] = ink
        }

        func image(from bytes: [UInt8]) -> UIImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let cgImage = CGImage(
                    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
                  ) else { return nil }
            return UIImage(cgImage: cgImage)
        }
        guard let silhouetteImage = image(from: silhouette), let linesImage = image(from: lines) else {
            return nil
        }
        return (silhouetteImage, linesImage)
    }
}

// MARK: - Ribbon geometry

/// A smooth curve through hand-placed key points — the line the player name is set along.
///
/// The key points are joined with a Catmull-Rom spline (converted to cubic Béziers) rather than one
/// big Bézier — that way each crest and trough sits exactly where it's placed, and the tangents stay
/// gentle instead of whipping at the ends.
///
/// Points are sampled once at init so we can convert a distance-along-the-ribbon into a point +
/// tangent angle — that arc-length lookup is what makes evenly spaced letters possible.
private struct RibbonCurve {
    private struct Segment { let p0, p1, p2, p3: CGPoint }

    private let segments: [Segment]
    private let samples: [(u: CGFloat, point: CGPoint, length: CGFloat)]
    /// Total arc length of the curve.
    let length: CGFloat

    /// `keyPoints` are passed through in order; the curve is extrapolated one point past each end so
    /// the first and last segments curve as naturally as the middle ones.
    init(keyPoints: [CGPoint]) {
        precondition(keyPoints.count >= 2, "a ribbon needs at least two key points")
        var pts = keyPoints
        let head = CGPoint(x: 2 * pts[0].x - pts[1].x, y: 2 * pts[0].y - pts[1].y)
        let tail = CGPoint(x: 2 * pts[pts.count - 1].x - pts[pts.count - 2].x,
                           y: 2 * pts[pts.count - 1].y - pts[pts.count - 2].y)
        pts = [head] + pts + [tail]

        var built: [Segment] = []
        for i in 1..<(pts.count - 2) {
            let p0 = pts[i], p3 = pts[i + 1]
            let p1 = CGPoint(x: p0.x + (pts[i + 1].x - pts[i - 1].x) / 6,
                             y: p0.y + (pts[i + 1].y - pts[i - 1].y) / 6)
            let p2 = CGPoint(x: p3.x - (pts[i + 2].x - pts[i].x) / 6,
                             y: p3.y - (pts[i + 2].y - pts[i].y) / 6)
            built.append(Segment(p0: p0, p1: p1, p2: p2, p3: p3))
        }
        self.segments = built

        let steps = 400
        var acc: [(u: CGFloat, point: CGPoint, length: CGFloat)] = []
        acc.reserveCapacity(steps + 1)
        var running: CGFloat = 0
        var previous = Self.evaluate(0, built)
        acc.append((0, previous, 0))
        for i in 1...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let pt = Self.evaluate(u, built)
            running += hypot(pt.x - previous.x, pt.y - previous.y)
            acc.append((u, pt, running))
            previous = pt
        }
        self.samples = acc
        self.length = running
    }

    /// Splits the global parameter `u` (0…1 across the whole spine) into a segment and a local t.
    private static func locate(_ u: CGFloat, _ segments: [Segment]) -> (Segment, CGFloat) {
        let n = CGFloat(segments.count)
        let scaled = min(max(u, 0), 1) * n
        let index = min(Int(scaled), segments.count - 1)
        return (segments[index], scaled - CGFloat(index))
    }

    private static func evaluate(_ u: CGFloat, _ segments: [Segment]) -> CGPoint {
        let (s, t) = locate(u, segments)
        let v = 1 - t
        let a = v * v * v, b = 3 * v * v * t, c = 3 * v * t * t, d = t * t * t
        return CGPoint(x: a * s.p0.x + b * s.p1.x + c * s.p2.x + d * s.p3.x,
                       y: a * s.p0.y + b * s.p1.y + c * s.p2.y + d * s.p3.y)
    }

    func point(at u: CGFloat) -> CGPoint { Self.evaluate(u, segments) }

    /// The direction the ribbon is travelling at `u`. Only the direction matters, so the
    /// segment-count scale factor is left out.
    func tangent(at u: CGFloat) -> CGVector {
        let (s, t) = Self.locate(u, segments)
        let v = 1 - t
        let x = 3 * v * v * (s.p1.x - s.p0.x) + 6 * v * t * (s.p2.x - s.p1.x) + 3 * t * t * (s.p3.x - s.p2.x)
        let y = 3 * v * v * (s.p1.y - s.p0.y) + 6 * v * t * (s.p2.y - s.p1.y) + 3 * t * t * (s.p3.y - s.p2.y)
        return CGVector(dx: x, dy: y)
    }

    /// Converts a distance along the spine into a point and the tangent angle there.
    func position(atLength target: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        let clamped = min(max(target, 0), length)
        // Samples are monotonically increasing in length, so a binary search lands the segment.
        var lo = 0, hi = samples.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if samples[mid].length < clamped { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let span = b.length - a.length
        let f = span > 0 ? (clamped - a.length) / span : 0
        let u = a.u + (b.u - a.u) * f
        let d = tangent(at: u)
        return (point(at: u), atan2(d.dy, d.dx))
    }
}

// MARK: - Text on the ribbon

/// Draws `text` glyph-by-glyph along `curve`, each character rotated to the curve's tangent, with a
/// black outline behind it. Sized down automatically until the whole name fits the ribbon.
private struct CurvedText: View {
    let text: String
    let curve: RibbonCurve
    let fontName: String
    let maxFontSize: CGFloat
    let fill: Color
    let outlineWidth: CGFloat
    /// Extra space between letters, in points at the final size.
    var tracking: CGFloat = 1.5
    /// The stretch of the ribbon (as fractions of its arc length) the name is centered in — keeps
    /// the name off the steep folded tails at either end.
    var span: ClosedRange<CGFloat> = 0...1

    var body: some View {
        Canvas { context, _ in
            let characters = Array(text)
            guard !characters.isEmpty else { return }

            // Measure once at a reference size, then solve for the size that fits — one pass, since
            // glyph advances scale linearly with point size.
            let reference: CGFloat = 100
            let referenceFont = Self.uiFont(fontName, size: reference)
            let referenceWidths = characters.map { character in
                NSAttributedString(string: String(character), attributes: [.font: referenceFont]).size().width
            }
            let referenceTotal = referenceWidths.reduce(0, +)
            guard referenceTotal > 0 else { return }

            let spanStart = curve.length * span.lowerBound
            let spanLength = curve.length * (span.upperBound - span.lowerBound)
            // Solve size * (referenceTotal / reference) + tracking * gaps == spanLength.
            let perPoint = referenceTotal / reference
            let gaps = CGFloat(characters.count - 1)
            let fitted = (spanLength - tracking * gaps) / perPoint
            let size = min(maxFontSize, max(10, fitted))
            let scale = size / reference

            let widths = referenceWidths.map { $0 * scale }
            let total = widths.reduce(0, +) + tracking * gaps

            let font = Font.custom(fontName, size: size)
            let outlineOffsets = Self.outlineOffsets(radius: outlineWidth)

            // Center the name within its span of the ribbon.
            var cursor = spanStart + (spanLength - total) / 2
            for (index, character) in characters.enumerated() {
                let width = widths[index]
                defer { cursor += width + tracking }
                guard !character.isWhitespace else { continue }

                let (point, angle) = curve.position(atLength: cursor + width / 2)
                var glyphContext = context
                glyphContext.translateBy(x: point.x, y: point.y)
                glyphContext.rotate(by: .radians(Double(angle)))

                let body = Text(String(character)).font(font)
                let outline = context.resolve(body.foregroundStyle(VintagePalette.ink))
                for offset in outlineOffsets {
                    glyphContext.draw(outline, at: offset, anchor: .center)
                }
                glyphContext.draw(context.resolve(body.foregroundStyle(fill)), at: .zero, anchor: .center)
            }
        }
        .frame(width: CardDesignSpace.width, height: CardDesignSpace.height)
    }

    /// Eight offsets around a circle — drawing the glyph at each fakes a stroke around it.
    private static func outlineOffsets(radius: CGFloat) -> [CGPoint] {
        guard radius > 0 else { return [] }
        return (0..<8).map { i in
            let angle = Double(i) / 8 * 2 * .pi
            return CGPoint(x: radius * CGFloat(cos(angle)), y: radius * CGFloat(sin(angle)))
        }
    }

    private static func uiFont(_ name: String, size: CGFloat) -> UIFont {
        CustomFont.ensureRegistered()
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .black)
    }
}

/// Straight (uncurved) text with the same faked black outline the ribbon's name gets — SwiftUI has
/// no text stroke, so the glyph is drawn eight times around a small circle behind the fill.
private struct OutlinedText: View {
    let text: String
    let font: Font
    let fill: Color
    var outlineWidth: CGFloat = 1.1

    private var offsets: [CGSize] {
        (0..<8).map { i in
            let angle = Double(i) / 8 * 2 * .pi
            return CGSize(width: outlineWidth * CGFloat(cos(angle)), height: outlineWidth * CGFloat(sin(angle)))
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(offsets.enumerated()), id: \.offset) { _, offset in
                Text(text).font(font).foregroundStyle(VintagePalette.ink).offset(offset)
            }
            Text(text).font(font).foregroundStyle(fill)
        }
    }
}

// MARK: - Shared front/back chrome

private enum VintageFrame {
    static let inset: CGFloat = 12
    static let radius: CGFloat = 18
    static let lineWidth: CGFloat = 7

    /// The rounded rect the green frame is stroked on.
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// Thick green band with the fine black rule on its inside edge.
    ///
    /// The rule is `shape` inset by exactly the band's width — the same curve `strokeBorder` uses for
    /// the band's inner edge, so the two meet everywhere. It is NOT a second rounded rect with a
    /// smaller corner radius: on a `.continuous` corner, shrinking the radius does not trace the same
    /// path as offsetting the curve inward, and the mismatch left a sliver of green showing between
    /// the rule and the photo at all four corners while looking perfect along the straight edges.
    static var overlay: some View {
        shape
            .strokeBorder(VintagePalette.green, lineWidth: lineWidth)
            .overlay(
                shape
                    .inset(by: lineWidth)
                    .strokeBorder(VintagePalette.ink.opacity(0.85), lineWidth: 1.5)
            )
            .padding(inset)
    }
}

// MARK: - Front

struct VintageCardFront: View {
    let player: Player

    /// Where the banner art sits in design space — sized and placed to clear the green frame's inner
    /// rule on all three sides, so the whole swallowtail reads without touching the frame.
    private static let bannerRect: CGRect = {
        // The framed opening runs from `inset + lineWidth` to the mirror of that on the far side.
        let opening = VintageFrame.inset + VintageFrame.lineWidth
        let width = CardDesignSpace.width - opening * 2 - 8
        let height = width * RibbonArt.aspectRatio
        return CGRect(x: (CardDesignSpace.width - width) / 2,
                      y: CardDesignSpace.height - opening - height - 4,
                      width: width, height: height)
    }()

    /// The centerline of the banner's main body, as fractions of the art's own width and height.
    /// Measured off the PNG by flood-filling it and taking the vertical midpoint of the largest
    /// enclosed region per column — so if the art is redrawn with the same broad shape, these still
    /// hold. This is the line the player's name is set along.
    private static let bannerCenterline: [CGPoint] = [
        CGPoint(x: 0.166, y: 0.431),
        CGPoint(x: 0.249, y: 0.367),
        CGPoint(x: 0.332, y: 0.318),
        CGPoint(x: 0.415, y: 0.293),
        CGPoint(x: 0.497, y: 0.285),   // the crown of the arc
        CGPoint(x: 0.580, y: 0.293),
        CGPoint(x: 0.663, y: 0.320),
        CGPoint(x: 0.746, y: 0.367),
        CGPoint(x: 0.829, y: 0.425),
    ]

    private static let nameCurve = RibbonCurve(
        keyPoints: bannerCenterline.map {
            CGPoint(x: bannerRect.minX + $0.x * bannerRect.width,
                    y: bannerRect.minY + $0.y * bannerRect.height)
        }
    )

    var body: some View {
        CardDesignSpace.scaled {
            ZStack(alignment: .topLeading) {
                PaperBackground()
                portrait
                VintageFrame.overlay
                jerseyNumber
                teamLogo
                ribbon
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var portrait: some View {
        PlayerPortrait(player: player)
            .frame(width: CardDesignSpace.width - VintageFrame.inset * 2,
                   height: CardDesignSpace.height - VintageFrame.inset * 2)
            // Clipped with the frame's OUTER radius: the portrait fills the whole framed area and
            // the green band sits on top of it, so a tighter radius would let the photo's corners
            // poke out past the band.
            .clipShape(VintageFrame.shape)
            .offset(x: VintageFrame.inset, y: VintageFrame.inset)
    }

    private var teamLogo: some View {
        TeamLogoView(team: player.teams.first, size: 38)
            .offset(x: 250, y: 30)
    }

    /// Jersey number in the top-left, matching the ribbon name's face and color.
    @ViewBuilder
    private var jerseyNumber: some View {
        if let number = player.jerseyNumber {
            OutlinedText(
                text: "\(number)",
                font: CustomFont.dsaccent(38),
                fill: VintagePalette.maroon,
                outlineWidth: 1.3
            )
            // Left-aligned in a fixed box so one- and two-digit numbers start at the same margin
            // instead of a single digit drifting inward.
            .frame(width: 120, alignment: .leading)
            .position(x: 26 + 60, y: 52)
        }
    }

    /// The banner: a gold gradient poured into the artwork's silhouette, the drawn line work laid
    /// back over it, then the player's name along the body's arc.
    @ViewBuilder
    private var ribbon: some View {
        if let silhouette = RibbonArt.silhouette, let lines = RibbonArt.lines {
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(
                        colors: [VintagePalette.goldLight, VintagePalette.gold,
                                 VintagePalette.gold, VintagePalette.goldDark],
                        startPoint: .top, endPoint: .bottom
                    )
                    .mask(
                        Image(uiImage: silhouette)
                            .resizable()
                            .interpolation(.high)
                    )
                    // The line layer is a mask, so the drawn outline can be any colour — it's set to
                    // the frame's green so the two pieces of chrome match.
                    VintagePalette.maroon
                        .mask(
                            Image(uiImage: lines)
                                .resizable()
                                .interpolation(.high)
                        )
                }
                .frame(width: Self.bannerRect.width, height: Self.bannerRect.height)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                // `.position` (not `.offset`) on purpose: it stays greedy and takes the size it's
                // offered, whereas a fixed `.frame` + `.offset` would report the banner's own width
                // as the ZStack's width. Anything wider than 320 there silently pushes the whole
                // design off-centre inside CardDesignSpace — which is exactly how the frame ended
                // 6pt proud on each side, with the portrait no longer meeting it.
                .position(x: Self.bannerRect.midX, y: Self.bannerRect.midY)

                CurvedText(
                    text: player.name.uppercased(),
                    curve: Self.nameCurve,
                    fontName: CustomFont.dsaccent,
                    maxFontSize: 28,
                    fill: VintagePalette.maroon,
                    outlineWidth: 1.0,
                    span: 0.04...0.96
                )
            }
        }
    }
}

// MARK: - Back

struct VintageCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        CardDesignSpace.scaled {
            ZStack(alignment: .topLeading) {
                PaperBackground()
                content
                    .padding(VintageFrame.inset + VintageFrame.lineWidth + 8)
                    .frame(width: CardDesignSpace.width, height: CardDesignSpace.height, alignment: .top)
                VintageFrame.overlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            nameplate

            sectionLabel("Batting — Career")
            statGrid(battingStats)

            if pitching.outsRecorded > 0 {
                sectionLabel("Pitching — Career")
                statGrid(pitchingStats)
            }
            Spacer(minLength: 0)
        }
    }

    /// A straight gold plate echoing the front's ribbon.
    private var nameplate: some View {
        HStack(spacing: 8) {
            TeamLogoView(team: player.teams.first, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.name.uppercased())
                    .font(CustomFont.dsaccent(26))
                    .foregroundStyle(VintagePalette.maroon)
                    .lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 6) {
                    Text((player.teams.first?.name ?? "").uppercased())
                        .font(CustomFont.dsaccent(13))
                        .foregroundStyle(VintagePalette.ink)
                    if let number = player.jerseyNumber {
                        Text("#\(number)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(VintagePalette.ink.opacity(0.75))
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [VintagePalette.goldLight, VintagePalette.gold, VintagePalette.goldDark.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(VintagePalette.green, lineWidth: 2.5)
        )
    }

    private var battingStats: [(String, String)] {
        [("G", "\(games)"), ("AB", "\(batting.atBats)"), ("H", "\(batting.hits)"),
         ("2B", "\(batting.doubles)"), ("3B", "\(batting.triples)"), ("HR", "\(batting.homeRuns)"),
         ("RBI", "\(batting.rbi)"), ("R", "\(batting.runsScored)"), ("BB", "\(batting.walks)"),
         ("K", "\(batting.strikeouts)"), ("SB", "\(batting.stolenBases)"),
         ("AVG", StatFormat.rate(batting.battingAverage)),
         ("OBP", StatFormat.rate(batting.onBasePercentage)),
         ("SLG", StatFormat.rate(batting.sluggingPercentage)),
         ("OPS", StatFormat.rate(batting.onBasePlusSlugging))]
    }

    private var pitchingStats: [(String, String)] {
        [("IP", StatFormat.inningsPitched(outs: pitching.outsRecorded)),
         ("H", "\(pitching.hitsAllowed)"), ("R", "\(pitching.runsAllowed)"),
         ("ER", "\(pitching.earnedRuns)"), ("BB", "\(pitching.walksAllowed)"),
         ("K", "\(pitching.strikeouts)"), ("SV", "\(pitching.saves)"),
         ("ERA", StatFormat.ratio(pitching.earnedRunAverage))]
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CustomFont.dsaccent(13))
            .foregroundStyle(VintagePalette.green)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(VintagePalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(VintagePalette.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(VintagePalette.green.opacity(0.35), lineWidth: 0.5))
            }
        }
    }
}
