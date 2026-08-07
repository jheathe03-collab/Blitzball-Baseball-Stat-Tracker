//
//  GoldStandardCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #5 — "Gold Standard," a 2013-Topps style card. Front: light-gray paper background, the
//  photo in a frame whose BOTTOM EDGE SWEEPS IN A CURVE (not a plain rectangle), outlined by a thick
//  red border with a thin gold inner line, the blitzball logo top-left, the player name across the
//  bottom, and the team logo bottom-right. Back matches with a red/gold framed stat panel.
//

import SwiftUI
import UIKit

private enum GoldPalette {
    static let red   = Color(red: 0.839, green: 0.137, blue: 0.039)   // #d6230a — thick outer frame
    static let gold  = Color(red: 0.827, green: 0.686, blue: 0.216)   // #d3af37 — thin inner line
    static let paper = Color(red: 0.93, green: 0.93, blue: 0.92)      // fallback background
    static let ink   = Color(red: 0.10, green: 0.10, blue: 0.10)
}

/// The card background: the "LightGrayPaper" image asset if present, else a plain paper fallback.
private struct LightGrayPaperBackground: View {
    var body: some View {
        GeometryReader { geo in
            if let ui = UIImage(named: "LightGrayPaper") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                GoldPalette.paper
            }
        }
    }
}

/// The photo window: square-ish on three sides, but the BOTTOM edge sweeps as a curve — low on the
/// right, rising toward the left — the signature 2013-Topps swoosh.
private struct SwooshShape: Shape, InsettableShape {
    /// Where the bottom edge meets the LEFT side (fraction of height from the top).
    var leftY: CGFloat = 0.80
    /// Where the bottom edge meets the RIGHT side (fraction of height from the top).
    var rightY: CGFloat = 0.94
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let corner: CGFloat = 6
        let lY = r.minY + r.height * leftY
        let rY = r.minY + r.height * rightY
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + corner))
        p.addQuadCurve(to: CGPoint(x: r.minX + corner, y: r.minY),
                       control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + corner),
                       control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: rY))
        // The sweep: hugs low across the right, then arcs up steeply toward the left edge.
        p.addCurve(to: CGPoint(x: r.minX, y: lY),
                   control1: CGPoint(x: r.minX + r.width * 0.74, y: rY + r.height * 0.012),
                   control2: CGPoint(x: r.minX + r.width * 0.20, y: lY + r.height * 0.085))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

// MARK: - Front

struct GoldStandardCardFront: View {
    let player: Player

    var body: some View {
        ZStack {
            LightGrayPaperBackground()
            // The photo fills the whole framed area; its curved bottom carves out the paper space
            // where the name and team logo sit.
            photoWindow
                .overlay(alignment: .bottom) { bottomRow }
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(GoldPalette.red.opacity(0.35), lineWidth: 1))
    }

    /// Photo clipped to the swoosh, with a thick red outline and a thin gold line just inside it.
    private var photoWindow: some View {
        let shape = SwooshShape()
        return PlayerPortrait(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            // strokeBorder draws INSIDE the edge, so the thick red hugs the photo and the thin gold
            // sits just inside it (uniform, unlike padding a proportional shape).
            .overlay(shape.strokeBorder(GoldPalette.red, lineWidth: 5))
            .overlay(shape.inset(by: 6).strokeBorder(GoldPalette.gold, lineWidth: 1.5))
            .overlay(alignment: .topLeading) { blitzLogo.padding(8) }
    }

    private var blitzLogo: some View {
        Image("BlitzBalllogo")
            .resizable().scaledToFit()
            .frame(width: 38, height: 38)
    }

    /// Player name in the paper space carved out at the bottom-left; team logo bottom-right.
    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(player.name.uppercased())
                .font(.custom("Futura-Bold", size: 19))
                .foregroundStyle(GoldPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.4)
            Spacer(minLength: 4)
            TeamLogoView(team: player.teams.first, size: 58)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Back

struct GoldStandardCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            LightGrayPaperBackground()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(GoldPalette.gold, lineWidth: 1.5)
                        .padding(4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(GoldPalette.red, lineWidth: 4)
                )
                .padding(12)
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
                        .foregroundStyle(GoldPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption.bold()).foregroundStyle(GoldPalette.red)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(GoldPalette.ink)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(GoldPalette.red).frame(height: 2)

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
            .foregroundStyle(GoldPalette.red)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(GoldPalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(GoldPalette.red.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(GoldPalette.gold.opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}
