//
//  RetroStripeCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #6 — "Retro Stripe," a 1986-Donruss style card. Front: a blue horizontal-stripe border,
//  the photo inset within it, a red team-name tab at the top-left, and the signature DIAGONAL name
//  band across the bottom (a tilted red bar carrying the player name, with a thin accent stripe just
//  under it), with the team logo sitting above it at the bottom-left. Back matches with a stat panel
//  on the striped background.
//

import SwiftUI
import UIKit

private enum RetroPalette {
    static let red    = Color(red: 0.80, green: 0.13, blue: 0.16)
    static let accent = Color(red: 0.42, green: 0.60, blue: 0.44)   // the thin stripe under the band
    static let navy   = Color(red: 0.13, green: 0.22, blue: 0.38)   // striped-border fallback
    static let cream  = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let ink    = Color(red: 0.11, green: 0.11, blue: 0.13)
}

/// The card background: the "BlueHorizontalStripe" image asset if present, else a striped fallback
/// drawn from thin navy lines so the look still holds.
private struct BlueStripeBackground: View {
    var body: some View {
        GeometryReader { geo in
            if let ui = UIImage(named: "BlueHorizontalStripe") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                ZStack {
                    RetroPalette.navy
                    VStack(spacing: 2) {
                        ForEach(0..<Int(geo.size.height / 4), id: \.self) { _ in
                            Rectangle().fill(.white.opacity(0.16)).frame(height: 2)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
    }
}

/// A rectangle whose BOTTOM edge is cut on a diagonal — used to end the photo exactly along the
/// name band's accent stripe. `bottomInset` is the distance from the bottom at the horizontal
/// centre; `tilt` matches the band's rotation so the two edges coincide.
private struct DiagonalBottomShape: Shape {
    var bottomInset: CGFloat
    var tilt: Double

    func path(in rect: CGRect) -> Path {
        let dy = CGFloat(tan(tilt * .pi / 180)) * (rect.width / 2)
        let centreY = rect.maxY - bottomInset
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: centreY + dy))   // right end of the cut
        p.addLine(to: CGPoint(x: rect.minX, y: centreY - dy))   // left end of the cut
        p.closeSubpath()
        return p
    }
}

// MARK: - Front

struct RetroStripeCardFront: View {
    let player: Player

    /// The band's tilt, shared by the bar, its text, and the photo's diagonal cut.
    private let tilt: Double = -4
    // Band geometry — the photo's cut is derived from these so it lands on the accent stripe.
    private let bandFrameHeight: CGFloat = 50
    private let bandBottomPadding: CGFloat = 26
    private let barHeight: CGFloat = 34
    private let accentHeight: CGFloat = 8

    /// Distance from the photo's bottom up to the accent stripe's lower edge (at the centre).
    private var photoCutInset: CGFloat {
        bandBottomPadding + (bandFrameHeight - (barHeight + accentHeight)) / 2
    }

    var body: some View {
        ZStack {
            BlueStripeBackground()
            photoArea
                .padding(13)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(RetroPalette.navy.opacity(0.5), lineWidth: 1))
    }

    private var photoArea: some View {
        let cut = DiagonalBottomShape(bottomInset: photoCutInset, tilt: tilt)
        return PlayerPortrait(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The photo ends on the diagonal, so below the accent stripe you see the striped border.
            .clipShape(cut)
            // Thin white border tracing the photo (including the diagonal cut).
            .overlay(cut.stroke(.white, lineWidth: 0.5))
            .overlay(alignment: .topLeading) { teamTab.padding(.leading, 6).padding(.top, 6) }
            .overlay(alignment: .bottom) { nameBand }
            // Sits just above the diagonal band.
            .overlay(alignment: .bottomLeading) { teamLogo.padding(.leading, 10).padding(.bottom, 74) }
    }

    /// Red tab at the top-left carrying the team name.
    private var teamTab: some View {
        Text((player.teams.first?.name ?? "").uppercased())
            .font(.custom("Futura-Bold", size: 12))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RetroPalette.red)
            .overlay(Rectangle().stroke(.white, lineWidth: 1.5))
            .frame(maxWidth: 150, alignment: .leading)
    }

    /// Just the icon — no plate behind it. A soft shadow keeps it readable over a light photo.
    private var teamLogo: some View {
        TeamLogoView(team: player.teams.first, size: 56)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }

    /// The signature diagonal band: a tilted red bar (with a thin accent stripe beneath) carrying the
    /// player's name. Both bar and text share the same rotation, and the bar is over-wide so its ends
    /// run past the card edges before being clipped.
    private var nameBand: some View {
        GeometryReader { geo in
            let barW = geo.size.width * 1.7
            ZStack {
                // Red bar with the thin accent stripe directly beneath it, tilted together.
                VStack(spacing: 0) {
                    Rectangle().fill(RetroPalette.red).frame(height: barHeight)
                    Rectangle().fill(RetroPalette.accent).frame(height: accentHeight)
                }
                .frame(width: barW)
                .rotationEffect(.degrees(tilt))

                // Name rides the same tilt; offset up by half the accent stripe so it centers on the red.
                HStack(spacing: 6) {
                    Text(player.name.uppercased())
                        .font(.custom("Futura-Bold", size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.4)
                    if let number = player.jerseyNumber {
                        Text("#\(number)")
                            .font(.custom("Futura-Bold", size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
                .frame(width: geo.size.width)
                .rotationEffect(.degrees(tilt))
                .offset(y: -accentHeight / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: bandFrameHeight)
        .padding(.bottom, bandBottomPadding)
    }
}

// MARK: - Back

struct RetroStripeCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            BlueStripeBackground()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(RetroPalette.cream))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(RetroPalette.ink.opacity(0.5), lineWidth: 1))
                .padding(13)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name.uppercased())
                        .font(.custom("Futura-Bold", size: 17))
                        .foregroundStyle(RetroPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption.bold()).foregroundStyle(RetroPalette.red)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(RetroPalette.ink)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(RetroPalette.red).frame(height: 2)

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
         ("K", "\(batting.strikeouts)"), ("SB", "\(batting.stolenBases)"), ("CS", "\(batting.caughtStealing)"),
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
            .font(.caption.weight(.black))
            .foregroundStyle(RetroPalette.red)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(RetroPalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(RetroPalette.navy)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(RetroPalette.navy.opacity(0.25), lineWidth: 0.5))
            }
        }
    }
}
