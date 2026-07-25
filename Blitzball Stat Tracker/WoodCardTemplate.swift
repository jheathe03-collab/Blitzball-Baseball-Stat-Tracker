//
//  WoodCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #2 — a 1987-Topps-style wood-grain card. Front: wood border, the photo in a
//  black-outline / white-inline frame, team logo in a circle (top-left), the blitzball logo in a
//  diamond (top-right), and red AVG + player-name boxes along the bottom. Back matches with a wood
//  border around a cream stat panel.
//

import SwiftUI
import UIKit

private enum WoodPalette {
    static let wood     = Color(red: 0.82, green: 0.64, blue: 0.40)
    static let woodDark = Color(red: 0.64, green: 0.47, blue: 0.25)
    static let red      = Color(red: 0.80, green: 0.12, blue: 0.14)
    static let cream    = Color(red: 0.96, green: 0.95, blue: 0.90)
    static let ink      = Color(red: 0.12, green: 0.10, blue: 0.08)

    /// Vertical tonal bands fake a wood grain.
    static var grain: LinearGradient {
        LinearGradient(stops: [
            .init(color: wood, location: 0.0),
            .init(color: woodDark, location: 0.13),
            .init(color: wood, location: 0.26),
            .init(color: woodDark, location: 0.42),
            .init(color: wood, location: 0.57),
            .init(color: woodDark, location: 0.73),
            .init(color: wood, location: 0.87),
            .init(color: woodDark, location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// A rhombus (rotated-square) used for the blitzball logo badge.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// A single diagonal line across a box's top-left corner (bottom-left → top-right).
private struct CornerDiagonal: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// The card background: the real "WoodGrain" image asset if it's been added, otherwise a faked
/// wood-tone gradient so the layout still looks right.
private struct WoodBackground: View {
    var body: some View {
        // GeometryReader gives the image a definite box to fill+clip, so the large JPEG can't drag
        // the card's layout toward its own aspect ratio (same fix as the player portrait).
        GeometryReader { geo in
            if let ui = UIImage(named: "WoodGrain") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                WoodPalette.grain
            }
        }
    }
}

// MARK: - Front

struct WoodCardFront: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }

    var body: some View {
        ZStack {
            WoodBackground()
            photoFrame
                .overlay(alignment: .topLeading) { cornerBadge }
                .overlay(alignment: .topTrailing) { blitzDiamond.padding(7) }
                .overlay(alignment: .bottomLeading) { avgBox.padding([.leading, .bottom], 10) }
                .overlay(alignment: .bottomTrailing) { nameBox.padding(.trailing, 10).padding(.bottom, -6) }
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WoodPalette.woodDark, lineWidth: 1))
    }

    /// Photo with a white inner line inside a black outer line (nested rounded backgrounds).
    private var photoFrame: some View {
        PlayerPortrait(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white))
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black))
    }

    private var teamCircle: some View {
        TeamLogoView(team: player.teams.first, size: 42)
            .padding(4)
            .background(Circle().fill(.white))
            .overlay(Circle().stroke(.black, lineWidth: 1.5))
    }

    private var blitzDiamond: some View {
        ZStack {
            Diamond().fill(.white)
            Diamond().stroke(.black, lineWidth: 1.5)
            Image("BlitzBalllogo").resizable().scaledToFit().frame(width: 22, height: 22)
        }
        .frame(width: 46, height: 46)
    }

    /// Team logo in a circle sitting over a diagonal cut at the photo's top-left corner.
    private var cornerBadge: some View {
        ZStack {
            CornerDiagonal().stroke(.black, lineWidth: 2).frame(width: 50, height: 50)
            teamCircle
        }
        .padding(5)
    }

    private var avgBox: some View {
        VStack(spacing: 0) {
            Text(StatFormat.rate(batting.battingAverage))
                .font(.subheadline.weight(.black).monospacedDigit())
            Text("AVG").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(WoodPalette.red))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1))
    }

    private var nameBox: some View {
        Text(player.name.uppercased())
            .font(.subheadline.weight(.black))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(WoodPalette.red))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1))
    }
}

// MARK: - Back

struct WoodCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            WoodBackground()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WoodPalette.cream))
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WoodPalette.woodDark, lineWidth: 1))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name.uppercased())
                        .font(.headline.weight(.black))
                        .foregroundStyle(WoodPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption).foregroundStyle(WoodPalette.woodDark)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(WoodPalette.red)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(WoodPalette.red).frame(height: 2)

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
            .font(.caption.weight(.black))
            .foregroundStyle(WoodPalette.red)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption2.bold().monospacedDigit()).foregroundStyle(WoodPalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(WoodPalette.woodDark)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(WoodPalette.woodDark.opacity(0.4), lineWidth: 0.5))
            }
        }
    }
}
