//
//  Theme.swift
//  Blitzball Stat Tracker
//
//  App-wide look: the league's blue gradient, the dark "card" style, brand fonts, and a one-line
//  modifier to put the gradient (optionally with a faint logo watermark) behind any screen.
//

import SwiftUI

enum Theme {
    /// The solid brand background. Replaces the old top-to-bottom gradient behind app screens: the
    /// gradient faded to a pale mint at the bottom, which washed out white text (e.g. the Teams
    /// "Game History" footer). A single on-brand navy keeps white readable everywhere. Tweak this
    /// one value to recolor every screen at once.
    static let brandBackground = Color(red: 0.19, green: 0.25, blue: 0.40)

    /// The brand gradient — still used behind the splash screen. (App screens now use the solid
    /// `brandBackground` above for readability.)
    static let brandGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.16, green: 0.23, blue: 0.42), location: 0.00), // deep navy
            .init(color: Color(red: 0.30, green: 0.44, blue: 0.66), location: 0.35), // mid blue
            .init(color: Color(red: 0.55, green: 0.68, blue: 0.78), location: 0.70), // light blue
            .init(color: Color(red: 0.80, green: 0.87, blue: 0.82), location: 1.00)  // pale mint
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Solid dark card fill used for menu cards, list rows, and buttons.
    static let cardFill = Color.black.opacity(0.9)
    static let cardCornerRadius: CGFloat = 22

    /// A solid dark background for busy screens (e.g. the live game) where the gradient's light
    /// bottom hurts readability. On-brand dark navy rather than pure black.
    static let darkBackground = Color(red: 0.09, green: 0.11, blue: 0.17)

    // Brand typography (system fonts — condensed/rounded widths, no custom-font registration needed).
    static let screenTitle = Font.system(.largeTitle, weight: .heavy).width(.condensed)
    static let screenSubtitle = Font.system(.title3, weight: .semibold).width(.condensed)
    static let cardTitle = Font.system(.headline, design: .rounded)
}

extension View {
    /// A solid dark background (no gradient) for screens where readability beats the gradient look.
    func blitzDarkBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.darkBackground.ignoresSafeArea())
    }

    /// Puts the solid brand background (optionally with a faint centered logo watermark) behind a
    /// screen and makes its List/Form/scroll content transparent so the background shows through.
    func blitzballBackground(watermark: Bool = false) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Theme.brandBackground
                    if watermark {
                        Image("BlitzBalllogo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 520)
                            .opacity(0.40)
                            .allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
            }
    }
}
