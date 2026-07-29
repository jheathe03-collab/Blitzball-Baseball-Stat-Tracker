//
//  CustomFont.swift
//  Blitzball Stat Tracker
//
//  Bundled custom fonts for the card templates.
//
//  The project generates its Info.plist (GENERATE_INFOPLIST_FILE = YES), so there's no plist to add
//  a `UIAppFonts` array to. Instead we register the bundled font file with CoreText the first time
//  it's used — one call, cached, and it works in the app and in the render-preview tests alike.
//

import SwiftUI
import CoreText

enum CustomFont {
    /// PostScript name inside "Fake Serif.ttf" (free for personal + commercial use).
    static let fakeSerif = "Fake Serif"
    static let dsaccent = "DSAccent"
    /// PostScript name inside "funkymuskrat.ttf" (the file name and the font name differ).
    static let funkyMuskrat = "FunkyMuskrat"
    /// PostScript name inside "tacobellold.ttf" (again, file name ≠ font name).
    static let tacoBellOld = "TacoBellOld"

    /// A quirky serif display face — used by the Neon 90s card.
    static func fakeSerif(_ size: CGFloat) -> Font {
        registerBundledFonts
        return .custom(fakeSerif, size: size)
    }

    /// old school Cal Ripken font style
    static func dsaccent(_ size: CGFloat) -> Font {
        registerBundledFonts
        return .custom(dsaccent, size: size)
    }

    /// Chunky hand-lettered display face — used by the Vintage card's team name.
    static func funkyMuskrat(_ size: CGFloat) -> Font {
        registerBundledFonts
        return .custom(funkyMuskrat, size: size)
    }

    /// The blocky Taco Bell display face — used by the Taco Style card.
    static func tacoBellOld(_ size: CGFloat) -> Font {
        registerBundledFonts
        return .custom(tacoBellOld, size: size)
    }

    /// Force registration without asking for a `Font` — needed when a view measures/draws with
    /// UIFont/CoreText directly (e.g. the Vintage card's text-on-a-curve).
    static func ensureRegistered() { registerBundledFonts }

    /// Runs exactly once (static `let` is lazy + thread-safe in Swift).
    private static let registerBundledFonts: Void = {
        for name in ["Fake Serif", "DSAccent", "funkymuskrat", "tacobellold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
