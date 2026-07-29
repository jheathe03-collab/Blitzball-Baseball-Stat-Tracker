//
//  TacoStyleCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #8 — "Taco Style." A yellow-bordered card over the TacoTime illustration, with a blue double-rule
//  frame around the photo (chamfered at the top-left), a "1st ROUND PICK" flash top-right, the
//  player name and number on a blue strip along the bottom, and the team badge in a pink circle
//  straddling the bottom-right corner.
//
//  The whole frame is the hand-drawn "TacoStyle" image asset. Like the Vintage card's ribbon, that
//  art is fully opaque, so TacoArt pulls it apart at runtime (see below) into a transparent frame
//  layer plus masks for the regions the card fills in itself. Nothing about the layout is hardcoded
//  to the art's current proportions — the regions are found structurally — so redrawing or
//  re-exporting the PNG at a different size just works.
//

import SwiftUI
import UIKit

/// Straight from the mockup's palette.
private enum TacoPalette {
    static let blue   = Color(red: 54 / 255, green: 57 / 255, blue: 154 / 255)    // #36399a
    static let pink   = Color(red: 239 / 255, green: 23 / 255, blue: 151 / 255)   // #ef1897
    static let yellow = Color(red: 254 / 255, green: 224 / 255, blue: 17 / 255)   // #fee012
    static let paper  = Color(red: 254 / 255, green: 255 / 255, blue: 250 / 255)  // #fefffa

    /// Lit top-left to deep bottom-right, both ends derived from the mockup's pink so the badge
    /// still reads as the same colour as the drawing it sits on.
    static let badgeFill = LinearGradient(
        colors: [
            Color(red: 250 / 255, green: 108 / 255, blue: 190 / 255),
            pink,
            Color(red: 168 / 255, green: 12 / 255, blue: 104 / 255),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Frame artwork

/// Takes the flat "TacoStyle" PNG apart into the pieces the card needs.
///
/// Two problems to solve. First, the art is fully opaque, so laying it over the card would hide the
/// paper texture and the photo. Second, the mockup asks for regions of it to be *filled* — the
/// channel between the two blue rules and the name strip along the bottom — which the drawing leaves
/// blank.
///
/// Both are handled by reading the pixels once, at first use:
///
///   * `frame` — the art with the blank paper knocked out to transparent. Each pixel is un-mixed
///     against the palette rather than thresholded, so antialiased edges keep their
///     true colour and stay smooth instead of fringing white.
///   * `photoWindow` / `blueFills` — masks for the enclosed blank regions, found by flood-filling
///     and then identifying them by how they nest, NOT by hardcoded coordinates: the photo window is
///     the largest enclosed region, the channel is the smallest region whose box contains it, and
///     the name strip is the region sitting below it. Re-export the art at any size and this still
///     resolves correctly.
///
/// It also reports the regions as fractions of the image, which is how the card positions the text
/// that sits on top of them.
enum TacoArt {
    struct Layers {
        /// The drawn frame — yellow border, blue rules, pink badge — on a transparent ground.
        let frame: UIImage
        /// Mask for the photo opening.
        let photoWindow: UIImage
        /// Mask for the areas the mockup asks to be filled with #36399a.
        let blueFills: UIImage
        /// Mask for every enclosed blank area — where the paper stock shows.
        let paperWindows: UIImage
        /// The colour of the artwork's outermost band, used as the card's ground. The frame's edge
        /// pixels are antialiased, so whatever sits behind them shows faintly along the card's rim;
        /// making that the border's own colour means the bleed is invisible instead of a pale line.
        let borderColour: Color

        /// All as fractions of the artwork, so they map onto the card whatever its size.
        let photoWindowRect: CGRect
        let nameStripRect: CGRect
        let badgeRect: CGRect
        let aspectRatio: CGFloat
    }

    static let layers: Layers? = build()

    /// Solid colours in the drawing. Anything else is treated as a blend of one of these and paper.
    private static let palette: [(r: Double, g: Double, b: Double)] = [
        (254, 224, 17),    // yellow
        (54, 57, 154),     // blue
        (239, 23, 151),    // pink
        (0, 0, 0),         // outline
    ]
    private static let paperWhite = (r: 254.0, g: 255.0, b: 250.0)

    /// Each palette colour with its paper→colour vector pre-solved. Hoisting this out of the pixel
    /// loop matters: `build` runs it a couple of million times.
    private struct PaletteAxis {
        let r, g, b: Double
        let vr, vg, vb: Double
        let inverseLengthSquared: Double
    }
    private static let paletteAxes: [PaletteAxis] = palette.map { colour in
        let vr = colour.r - paperWhite.r
        let vg = colour.g - paperWhite.g
        let vb = colour.b - paperWhite.b
        return PaletteAxis(r: colour.r, g: colour.g, b: colour.b, vr: vr, vg: vg, vb: vb,
                           inverseLengthSquared: 1 / (vr * vr + vg * vg + vb * vb))
    }

    private static func build() -> Layers? {
        guard let source = UIImage(named: "TacoStyle")?.cgImage else { return nil }
        let sourceWidth = source.width, sourceHeight = source.height

        var raw = [UInt8](repeating: 0, count: sourceWidth * sourceHeight * 4)
        guard let context = CGContext(
            data: &raw, width: sourceWidth, height: sourceHeight, bitsPerComponent: 8,
            bytesPerRow: sourceWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))

        // 0. Reshape the drawing to the card's aspect before anything else looks at it, so every
        //    region and rect below is measured against art that already fits.
        let art = fitToCardAspect(pixels: raw, width: sourceWidth, height: sourceHeight)
        let pixels = art.pixels, width = art.width, height = art.height
        let count = width * height

        // 1. Un-mix every pixel against the palette to get the transparent frame layer, and note
        //    which pixels are blank while we're already reading them.
        //
        //    Each pixel is treated as `palette colour × a + paper × (1 − a)`: project it onto every
        //    paper→colour line and keep whichever it sits closest to. That's what lets a half-covered
        //    edge pixel come back as "the real blue, 50% opaque" rather than a washed-out blue-white
        //    that would show as a pale fringe once the paper behind it changes.
        //
        //    This is the hot loop of the whole file — a couple of million pixels — so it's written
        //    straight against buffer pointers with the palette maths pre-solved above.
        var frameBytes = [UInt8](repeating: 0, count: count * 4)
        var blank = [Bool](repeating: false, count: count)
        let axes = paletteAxes
        let paper = paperWhite
        pixels.withUnsafeBufferPointer { source in
            frameBytes.withUnsafeMutableBufferPointer { frame in
                blank.withUnsafeMutableBufferPointer { isBlank in
                    for i in 0..<count {
                        let byte = i * 4
                        let red = Int(source[byte]), green = Int(source[byte + 1]), blue = Int(source[byte + 2])

                        let high = max(red, max(green, blue)), low = min(red, min(green, blue))
                        isBlank[i] = low > 200 && (high - low) < 26

                        let dr = Double(red) - paper.r
                        let dg = Double(green) - paper.g
                        let db = Double(blue) - paper.b
                        var bestResidual = Double.greatestFiniteMagnitude
                        var alpha = 0.0
                        var colour = axes[0]
                        for axis in axes {
                            var t = (dr * axis.vr + dg * axis.vg + db * axis.vb) * axis.inverseLengthSquared
                            if t < 0 { t = 0 } else if t > 1 { t = 1 }
                            let er = dr - t * axis.vr, eg = dg - t * axis.vg, eb = db - t * axis.vb
                            let residual = er * er + eg * eg + eb * eb
                            if residual < bestResidual {
                                bestResidual = residual
                                alpha = t
                                colour = axis
                            }
                        }
                        // Premultiplied.
                        frame[byte] = UInt8(colour.r * alpha)
                        frame[byte + 1] = UInt8(colour.g * alpha)
                        frame[byte + 2] = UInt8(colour.b * alpha)
                        frame[byte + 3] = UInt8(alpha * 255)
                    }
                }
            }
        }
        let regions = components(of: blank, width: width, height: height)
            .filter { Double($0.area) / Double(count) > 0.005 }
        let interior = regions.filter { !$0.touchesBorder }
        guard let window = interior.max(by: { $0.area < $1.area }) else { return nil }

        // The channel is the tightest region that still encloses the photo window; the name strip is
        // the biggest region sitting below it. Everything else is left transparent, showing paper.
        let channel = interior
            .filter { $0.id != window.id && $0.box.contains(window.box) }
            .min(by: { $0.box.width * $0.box.height < $1.box.width * $1.box.height })
        let strip = interior
            .filter { $0.id != window.id && $0.id != channel?.id && $0.box.minY >= window.box.maxY }
            .max(by: { $0.area < $1.area })

        // 3. Turn those regions into masks, grown slightly so the fills tuck under the drawn rules
        //    rather than stopping exactly at them and leaving a hairline of paper showing.
        let grow = max(2, width / 300)
        let windowMask = mask(for: [window.id], labels: regions, width: width, height: height, grow: grow)
        let fillMask = mask(for: [channel?.id, strip?.id].compactMap { $0 },
                            labels: regions, width: width, height: height, grow: grow)
        // Paper shows in every enclosed blank area — but NOT in anything open to the card's rim,
        // which is what would bleed past the border.
        let paperMask = mask(for: interior.map(\.id), labels: regions,
                             width: width, height: height, grow: grow)

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
        guard let frameImage = image(from: frameBytes),
              let windowImage = image(from: windowMask),
              let fillImage = image(from: fillMask),
              let paperImage = image(from: paperMask) else { return nil }

        // The dominant drawn colour around the outer rim — the border band.
        var rimTally: [UInt32: Int] = [:]
        let rim = max(1, height / 50)
        for y in 0..<height {
            let vertical = y < rim || y >= height - rim
            for x in 0..<width where vertical || x < rim || x >= width - rim {
                let i = (y * width + x) * 4
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                // Skip the paper and the outline so the band's own colour wins.
                if Int(r) + Int(g) + Int(b) < 200 { continue }
                if min(r, min(g, b)) > 200 && Int(max(r, max(g, b))) - Int(min(r, min(g, b))) < 26 { continue }
                rimTally[UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b), default: 0] += 1
            }
        }
        let rimColour = rimTally.max(by: { $0.value < $1.value })?.key ?? 0xFEE011
        let border = Color(red: Double((rimColour >> 16) & 255) / 255,
                           green: Double((rimColour >> 8) & 255) / 255,
                           blue: Double(rimColour & 255) / 255)

        // 4. The pink badge, located by colour rather than by region.
        var badgeMinX = width, badgeMinY = height, badgeMaxX = 0, badgeMaxY = 0, sawBadge = false
        pixels.withUnsafeBufferPointer { source in
            for i in 0..<count {
                let byte = i * 4
                let r = Int(source[byte]), g = Int(source[byte + 1]), b = Int(source[byte + 2])
                guard r > 190, g < 100, b > 100, b < 190 else { continue }
                let x = i % width, y = i / width
                badgeMinX = min(badgeMinX, x); badgeMaxX = max(badgeMaxX, x)
                badgeMinY = min(badgeMinY, y); badgeMaxY = max(badgeMaxY, y)
                sawBadge = true
            }
        }
        let badge = sawBadge
            ? CGRect(x: badgeMinX, y: badgeMinY, width: badgeMaxX - badgeMinX, height: badgeMaxY - badgeMinY)
            : .zero

        func normalise(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX / CGFloat(width), y: box.minY / CGFloat(height),
                   width: box.width / CGFloat(width), height: box.height / CGFloat(height))
        }
        return Layers(
            frame: frameImage,
            photoWindow: windowImage,
            blueFills: fillImage,
            paperWindows: paperImage,
            borderColour: border,
            photoWindowRect: normalise(window.box),
            nameStripRect: normalise(strip?.box ?? .zero),
            badgeRect: normalise(badge),
            aspectRatio: CGFloat(height) / CGFloat(width)
        )
    }

    /// Reshapes the artwork to exactly the card's aspect ratio without distorting anything in it.
    ///
    /// Padding a drawing out to 2:3 in an image editor leaves letterbox bars — ours came back solid
    /// black — and recolouring them wouldn't help either, since the border would then be far thicker
    /// top and bottom than at the sides. Stretching the whole image to fit is no good either: the
    /// round badge would go oval.
    ///
    /// So: trim any uniform bars off the ends, then find the longest run of vertically identical
    /// rows — the straight stretch of border and photo window running down the middle — and add or
    /// remove rows only there. Every drawn feature keeps its proportions and the card simply gets a
    /// taller window. It's all measured from the art, so a redraw re-derives it.
    private static func fitToCardAspect(pixels: [UInt8], width: Int, height: Int)
        -> (pixels: [UInt8], width: Int, height: Int) {

        func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
        func isDark(_ i: Int) -> Bool {
            Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) <= 120
        }
        func isBlank(_ i: Int) -> Bool {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            return min(r, min(g, b)) > 200 && max(r, max(g, b)) - min(r, min(g, b)) < 26
        }
        func matches(_ i: Int, _ j: Int) -> Bool {
            abs(Int(pixels[i]) - Int(pixels[j])) < 22
                && abs(Int(pixels[i + 1]) - Int(pixels[j + 1])) < 22
                && abs(Int(pixels[i + 2]) - Int(pixels[j + 2])) < 22
        }

        var left = 0, right = width - 1, top = 0, bottom = height - 1
        func rowIsAll(_ y: Int, _ test: (Int) -> Bool) -> Bool {
            for x in left...right where !test(offset(x, y)) { return false }
            return true
        }
        func columnIsAll(_ x: Int, _ test: (Int) -> Bool) -> Bool {
            for y in top...bottom where !test(offset(x, y)) { return false }
            return true
        }
        // First the exporter's letterbox fill, then the blank paper margin around the drawing — so
        // the outermost drawn thing, the yellow border, runs right to the edge of the card instead
        // of floating inside a pale surround that reads as a mis-crop.
        for test in [isDark, isBlank] {
            while top < bottom && rowIsAll(top, test) { top += 1 }
            while bottom > top && rowIsAll(bottom, test) { bottom -= 1 }
            while left < right && columnIsAll(left, test) { left += 1 }
            while right > left && columnIsAll(right, test) { right -= 1 }
        }
        // Then the keyline drawn around the outside of the border, so the card's rim is clean colour
        // rather than a hard black line.
        //
        // Measured, not assumed: walk in from each edge until the artwork settles into the colour it
        // holds a little deeper in — the border band itself — and drop however many rows that took.
        // That covers the line AND its antialiased fringe, and stays correct whatever colour the
        // border or the keyline happen to be. A darkness test can't do this: the outermost fringe row
        // is a pale blend, so it reads as "not dark" and the trim stops before it starts.
        func settleDepth(limit: Int, _ pixelAt: (Int) -> Int) -> Int {
            guard limit > 4 else { return 0 }
            let reference = pixelAt(limit)
            var depth = 0
            while depth < limit && !matches(pixelAt(depth), reference) { depth += 1 }
            return depth == limit ? 0 : depth   // never settled — leave the edge alone
        }
        /// Sampled at three points along the edge, taking the deepest, so one stray feature sitting
        /// against the border can't make the keyline look thinner than it is.
        func edgeDepth(limit: Int, _ pixelAt: (Int, Int) -> Int) -> Int {
            [0.25, 0.5, 0.75]
                .map { fraction in settleDepth(limit: limit) { pixelAt($0, Int(fraction * 1000)) } }
                .max() ?? 0
        }
        // The probe has to come to rest INSIDE the border band — deep enough to clear the keyline,
        // shallow enough not to punch through the band into whatever it encloses, or the "settled"
        // colour would be the wrong one and this would eat the border itself.
        let probe = max(4, min(right - left, bottom - top) / 60)
        let along = { (fraction: Int, from: Int, to: Int) in from + (to - from) * fraction / 1000 }

        let topDepth = edgeDepth(limit: probe) { d, f in offset(along(f, left, right), top + d) }
        let bottomDepth = edgeDepth(limit: probe) { d, f in offset(along(f, left, right), bottom - d) }
        let leftDepth = edgeDepth(limit: probe) { d, f in offset(left + d, along(f, top, bottom)) }
        let rightDepth = edgeDepth(limit: probe) { d, f in offset(right - d, along(f, top, bottom)) }
        top += topDepth; bottom -= bottomDepth; left += leftDepth; right -= rightDepth

        let contentWidth = right - left + 1
        let contentHeight = bottom - top + 1
        let target = Int((CGFloat(contentWidth) * CardMetrics.ratio).rounded())
        let extra = target - contentHeight

        /// Two rows count as the same if only a sliver of pixels differ — enough slack for the
        /// antialiasing along a diagonal not to break an otherwise straight run.
        func rowsMatch(_ a: Int, _ b: Int) -> Bool {
            var mismatches = 0
            let allowed = max(2, contentWidth / 200)
            for x in left...right {
                let i = offset(x, a), j = offset(x, b)
                if abs(Int(pixels[i]) - Int(pixels[j])) > 12
                    || abs(Int(pixels[i + 1]) - Int(pixels[j + 1])) > 12
                    || abs(Int(pixels[i + 2]) - Int(pixels[j + 2])) > 12 {
                    mismatches += 1
                    if mismatches > allowed { return false }
                }
            }
            return true
        }
        var bestStart = top, bestLength = 1, runStart = top
        if bottom > top {
            for y in (top + 1)...bottom {
                if rowsMatch(y, y - 1) {
                    if y - runStart + 1 > bestLength {
                        bestLength = y - runStart + 1
                        bestStart = runStart
                    }
                } else {
                    runStart = y
                }
            }
        }

        // Copy out, row by row, through whichever mapping applies.
        let stretchable = extra != 0 && bestLength > 8 && bestLength + extra > 0
        let outputHeight = stretchable ? target : contentHeight
        let rowBytes = contentWidth * 4
        var output = [UInt8](repeating: 0, count: rowBytes * outputHeight)
        let runStartInContent = bestStart - top
        let newRunLength = bestLength + extra

        for y in 0..<outputHeight {
            var sourceRow = y
            if stretchable {
                if y < runStartInContent {
                    sourceRow = y
                } else if y < runStartInContent + newRunLength {
                    // Walk the run at a different rate: rows get repeated (or skipped) here only.
                    sourceRow = runStartInContent + (y - runStartInContent) * bestLength / newRunLength
                } else {
                    sourceRow = y - extra
                }
            }
            sourceRow = min(max(sourceRow, 0), contentHeight - 1) + top
            let from = offset(left, sourceRow)
            let to = y * rowBytes
            output[to..<(to + rowBytes)] = pixels[from..<(from + rowBytes)]
        }
        return (output, contentWidth, outputHeight)
    }

    private struct Region {
        let id: Int
        let area: Int
        let box: CGRect
        let touchesBorder: Bool
        let labels: [Int]
    }

    /// 4-connected flood fill over `mask`, returning one region per connected blob.
    ///
    /// Every pixel of the artwork passes through here, so the fill runs against buffer pointers and
    /// reuses one pre-sized stack across blobs rather than growing a fresh array for each.
    private static func components(of mask: [Bool], width: Int, height: Int) -> [Region] {
        let count = width * height
        var labels = [Int](repeating: 0, count: count)
        var found: [Region] = []
        var next = 1
        var stack = [Int]()
        stack.reserveCapacity(count / 2)

        mask.withUnsafeBufferPointer { isBlank in
        labels.withUnsafeMutableBufferPointer { label in
        for start in 0..<count where isBlank[start] && label[start] == 0 {
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            label[start] = next
            var area = 0, minX = width, minY = height, maxX = 0, maxY = 0, border = false
            while let i = stack.popLast() {
                area += 1
                let x = i % width, y = i / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { border = true }
                if x > 0, isBlank[i - 1], label[i - 1] == 0 { label[i - 1] = next; stack.append(i - 1) }
                if x < width - 1, isBlank[i + 1], label[i + 1] == 0 { label[i + 1] = next; stack.append(i + 1) }
                if y > 0, isBlank[i - width], label[i - width] == 0 { label[i - width] = next; stack.append(i - width) }
                if y < height - 1, isBlank[i + width], label[i + width] == 0 { label[i + width] = next; stack.append(i + width) }
            }
            found.append(Region(
                id: next, area: area,
                box: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                touchesBorder: border, labels: []
            ))
            next += 1
        }
        }
        }
        // Every region shares one label buffer; stash it on each so masks can be cut from it.
        return found.map { Region(id: $0.id, area: $0.area, box: $0.box, touchesBorder: $0.touchesBorder, labels: labels) }
    }

    /// A white-on-transparent mask covering the given regions, dilated by `grow` pixels.
    private static func mask(for ids: [Int], labels regions: [Region],
                             width: Int, height: Int, grow: Int) -> [UInt8] {
        let count = width * height
        var bytes = [UInt8](repeating: 0, count: count * 4)
        guard let buffer = regions.first?.labels, !ids.isEmpty else { return bytes }
        let wanted = Set(ids)
        var hit = [Bool](repeating: false, count: count)
        for i in 0..<count where wanted.contains(buffer[i]) { hit[i] = true }

        // Separable dilation, one pass per axis. Rather than painting a window around every hit —
        // which rewrites the same pixels `grow` times over — each pass walks the line once carrying
        // "how many more pixels stay lit", which touches each pixel exactly once.
        var grown = hit
        grown.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let row = y * width
                var carry = 0
                for x in 0..<width {
                    if buffer[row + x] { carry = grow } else if carry > 0 { carry -= 1 }
                    if carry > 0 { buffer[row + x] = true }
                }
                carry = 0
                for x in stride(from: width - 1, through: 0, by: -1) {
                    if hit[row + x] { carry = grow } else if carry > 0 { carry -= 1 }
                    if carry > 0 { buffer[row + x] = true }
                }
            }
        }
        let afterRows = grown
        grown.withUnsafeMutableBufferPointer { buffer in
            for x in 0..<width {
                var carry = 0
                for y in 0..<height {
                    if buffer[y * width + x] { carry = grow } else if carry > 0 { carry -= 1 }
                    if carry > 0 { buffer[y * width + x] = true }
                }
                carry = 0
                for y in stride(from: height - 1, through: 0, by: -1) {
                    if afterRows[y * width + x] { carry = grow } else if carry > 0 { carry -= 1 }
                    if carry > 0 { buffer[y * width + x] = true }
                }
            }
        }
        bytes.withUnsafeMutableBufferPointer { out in
            for i in 0..<count where grown[i] {
                out[i * 4] = 255; out[i * 4 + 1] = 255; out[i * 4 + 2] = 255; out[i * 4 + 3] = 255
            }
        }
        return bytes
    }

}

/// Scales a normalised rect from the artwork onto the card's design space.
private func onCard(_ normalised: CGRect) -> CGRect {
    CGRect(x: normalised.minX * CardDesignSpace.width,
           y: normalised.minY * CardDesignSpace.height,
           width: normalised.width * CardDesignSpace.width,
           height: normalised.height * CardDesignSpace.height)
}

// MARK: - Front

struct TacoStyleCardFront: View {
    let player: Player

    var body: some View {
        CardDesignSpace.scaled {
            ZStack(alignment: .topLeading) {
                if let art = TacoArt.layers {
                    // The border's own colour is the ground, so the frame's antialiased outer edge
                    // has nothing paler behind it to bleed through at the card's rim.
                    art.borderColour
                    PaperBackground(imageName: "TacoTime", fallback: TacoPalette.paper)
                        .mask(layer(art.paperWindows))

                    // Blue fills and the photo sit UNDER the frame, so the drawn rules cap them.
                    TacoPalette.blue.mask(layer(art.blueFills))
                    PlayerPortrait(player: player).mask(layer(art.photoWindow))
                    layer(art.frame)

                    roundPick(in: onCard(art.photoWindowRect))
                    nameplate(in: onCard(art.nameStripRect), clearing: onCard(art.badgeRect))
                    badge(in: onCard(art.badgeRect))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Every derived layer comes from the same source image, so stretching them all across the card
    /// keeps them in register — whatever the art's aspect ratio happens to be.
    private func layer(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: CardDesignSpace.width, height: CardDesignSpace.height)
    }

    /// "1st ROUND PICK", tucked into the photo window's top-right.
    private func roundPick(in window: CGRect) -> some View {
        VStack(alignment: .trailing, spacing: -2) {
            HStack(alignment: .top, spacing: 0) {
                Text("1").font(CustomFont.tacoBellOld(26))
                Text("st").font(CustomFont.tacoBellOld(13)).baselineOffset(8)
            }
            .foregroundStyle(TacoPalette.pink)

            Text("ROUND").font(CustomFont.tacoBellOld(9))
            Text("PICK").font(CustomFont.tacoBellOld(9))
        }
        .foregroundStyle(TacoPalette.blue)
        .frame(width: 90, alignment: .trailing)
        .position(x: window.maxX - 12 - 45, y: window.minY + 26)
    }

    /// Player name and number in yellow along the blue strip.
    ///
    /// The strip's box runs under the badge — the blank region it's measured from only stops where
    /// the circle bites into it at its widest — so the trailing inset is worked out from where the
    /// badge actually starts rather than being a fixed guess.
    private func nameplate(in strip: CGRect, clearing badge: CGRect) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(player.name.uppercased())
                .font(CustomFont.tacoBellOld(17))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Spacer(minLength: 0)
            if let number = player.jerseyNumber {
                Text("NO. \(number)")
                    .font(CustomFont.tacoBellOld(15))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(TacoPalette.yellow)
        .padding(.leading, 12)
        .padding(.trailing, max(12, strip.maxX - badge.minX + 10))
        .frame(width: strip.width, height: strip.height)
        .position(x: strip.midX, y: strip.midY)
    }

    /// Team logo over the team name, inside the pink circle.
    private func badge(in circle: CGRect) -> some View {
        ZStack {
            // An ellipse rather than a circle, and sized to the detected pink area exactly, so it
            // covers the drawn badge whatever shape the art reports — leaving its blue outline.
            Ellipse().fill(TacoPalette.badgeFill)

            VStack(spacing: 0) {
                TeamLogoView(team: player.teams.first, size: circle.height * 0.55)
                // The name sits below centre, where the circle has already narrowed — so it's held
                // to the chord width down there, not the circle's full diameter.
                Text((player.teams.first?.name ?? "").uppercased())
                    .font(CustomFont.tacoBellOld(10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: circle.width * 0.72)
            }
        }
        .frame(width: circle.width, height: circle.height)
        .position(x: circle.midX, y: circle.midY)
    }
}

// MARK: - Back

struct TacoStyleCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        CardDesignSpace.scaled {
            ZStack(alignment: .topLeading) {
                if let art = TacoArt.layers {
                    art.borderColour
                    // Plain paper on the reverse: the TacoTime illustration shows through the same
                    // opening the photo uses on the front, and behind a stat table it competes with
                    // the numbers.
                    PaperBackground(fallback: TacoPalette.paper)
                        .mask(layer(art.paperWindows))
                    TacoPalette.blue.mask(layer(art.blueFills))
                    layer(art.frame)

                    // The stat table fills the same opening the photo uses on the front.
                    stats
                        .frame(width: onCard(art.photoWindowRect).width - 20,
                               height: onCard(art.photoWindowRect).height - 20,
                               alignment: .top)
                        .position(x: onCard(art.photoWindowRect).midX,
                                  y: onCard(art.photoWindowRect).midY)
                    nameplate(in: onCard(art.nameStripRect))
                    badge(in: onCard(art.badgeRect))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func layer(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: CardDesignSpace.width, height: CardDesignSpace.height)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Batting — Career")
            statGrid(battingStats)

            if pitching.outsRecorded > 0 {
                sectionLabel("Pitching — Career")
                statGrid(pitchingStats)
            }
            Spacer(minLength: 0)
        }
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
            .font(CustomFont.tacoBellOld(11))
            .foregroundStyle(TacoPalette.pink)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(TacoPalette.blue)
                    Text(stat.0).font(.system(size: 8, weight: .bold)).foregroundStyle(TacoPalette.pink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3).fill(TacoPalette.blue.opacity(0.08)))
            }
        }
    }

    private func nameplate(in strip: CGRect) -> some View {
        Text(player.name.uppercased())
            .font(CustomFont.tacoBellOld(17))
            .foregroundStyle(TacoPalette.yellow)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.horizontal, 10)
            .frame(width: strip.width, height: strip.height, alignment: .leading)
            .position(x: strip.midX, y: strip.midY)
    }

    private func badge(in circle: CGRect) -> some View {
        ZStack {
            // An ellipse rather than a circle, and sized to the detected pink area exactly, so it
            // covers the drawn badge whatever shape the art reports — leaving its blue outline.
            Ellipse().fill(TacoPalette.badgeFill)

            VStack(spacing: 0) {
                TeamLogoView(team: player.teams.first, size: circle.height * 0.55)
                // The name sits below centre, where the circle has already narrowed — so it's held
                // to the chord width down there, not the circle's full diameter.
                Text((player.teams.first?.name ?? "").uppercased())
                    .font(CustomFont.tacoBellOld(10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: circle.width * 0.72)
            }
        }
        .frame(width: circle.width, height: circle.height)
        .position(x: circle.midX, y: circle.midY)
    }
}
