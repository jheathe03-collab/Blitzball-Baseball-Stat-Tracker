//
//  Neon90sCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #7 — "Neon 90s." Front: a painted Retro80s background, a yellow "90s" tag top-left, the
//  photo panel, a vertical cyan team-name column down the right, a cyan player-name bar under the
//  photo, and yellow ERA / AVG badges hanging at the bottom-left. Display type is the bundled
//  "Fake Serif" face (see CustomFont); the stat badges use Apple SD Gothic Neo.
//

import SwiftUI
import UIKit

private enum NeonPalette {
    static let cyan    = Color(red: 0.000, green: 0.949, blue: 0.953)  // #00f2f3
    static let magenta = Color(red: 0.953, green: 0.376, blue: 0.988)  // #f360fc
    static let yellow  = Color(red: 0.992, green: 1.000, blue: 0.000)  // #fdff00
    static let panel   = Color(red: 0.96, green: 0.96, blue: 0.94)     // photo-panel / stat text bg
    static let ink     = Color(red: 0.10, green: 0.10, blue: 0.12)

    /// Cyan fading to white — used behind the name bar and team column. Weighted so cyan holds the
    /// first third (keeps the yellow display type legible) before washing out to white.
    static let cyanFade = LinearGradient(
        stops: [.init(color: cyan, location: 0.00),
                .init(color: cyan, location: 0.32),
                .init(color: .white, location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// A slighter yellow→white fade for the ERA / AVG / HR badges. Weighted so the yellow holds
    /// under the cyan labels (top-left) and only lifts toward the bottom-right.
    static let yellowFade = LinearGradient(
        stops: [.init(color: yellow, location: 0.00),
                .init(color: yellow, location: 0.50),
                .init(color: .white, location: 1.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The card background: the "Retro80s" image asset if present, else a magenta wash.
private struct Retro80sBackground: View {
    var body: some View {
        GeometryReader { geo in
            if let ui = UIImage(named: "Retro80s") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                LinearGradient(colors: [NeonPalette.magenta, .purple],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

// MARK: - Front

struct Neon90sCardFront: View {
    let player: Player

    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }

    private let columnWidth: CGFloat = 52
    private let nameBarHeight: CGFloat = 40
    private let badgeZoneHeight: CGFloat = 54   // room under the name bar for the ERA/AVG badges

    var body: some View {
        ZStack {
            Retro80sBackground()

            // spacing 0 everywhere so the name bar and team column butt right up against the photo.
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    photoPanel
                    nameBar
                }
                // Badges hang directly off the name bar's bottom edge.
                .overlay(alignment: .bottomLeading) {
                    statBadges.offset(x: 6, y: badgeZoneHeight - 2)
                }
                teamColumn
                    // HR diamond tucks under the column's bottom-right corner.
                    .overlay(alignment: .bottomTrailing) {
                        hrDiamond.offset(x: 2, y: 60)
                    }
            }
            .padding(14)
            .padding(.top, 12)                    // room for the "90s" tag straddling the corner
            .padding(.bottom, badgeZoneHeight)    // room for the hanging badges
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Yellow diamond (rotated square) carrying the home-run total; the text stays upright.
    private var hrDiamond: some View {
        ZStack {
            Rectangle()
                .fill(NeonPalette.yellowFade)
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(45))
            VStack(spacing: -3) {
                Text("HR")
                    .font(.custom("AppleSDGothicNeo-Bold", size: 12))
                    .foregroundStyle(NeonPalette.cyan)
                Text("\(batting.homeRuns)")
                    .font(.custom("AppleSDGothicNeo-Bold", size: 18))
                    .foregroundStyle(NeonPalette.ink)
            }
        }
        .frame(width: 80, height: 80)
    }

    private var photoPanel: some View {
        PlayerPortrait(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NeonPalette.panel)
            .overlay(alignment: .bottomLeading) {
                TeamLogoView(team: player.teams.first, size: 44)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(8)
            }
            .overlay(Rectangle().stroke(NeonPalette.magenta, lineWidth: 2))
            // The "90s" tag straddles the photo's top-left corner.
            .overlay(alignment: .topLeading) {
                Text("90s")
                    .font(CustomFont.fakeSerif(38))
                    .foregroundStyle(NeonPalette.yellow)
                    .shadow(color: NeonPalette.magenta, radius: 0, x: 1.5, y: 1.5)
                    .rotationEffect(.degrees(-11))
                    .offset(x: -6, y: -18)
            }
    }

    /// Cyan bar under the photo carrying the player's name.
    private var nameBar: some View {
        HStack(spacing: 6) {
            Text(player.name)
                .font(CustomFont.fakeSerif(34))
                .foregroundStyle(NeonPalette.yellow)
                .shadow(color: NeonPalette.magenta, radius: 0, x: 1.5, y: 1.5)
                .lineLimit(1).minimumScaleFactor(0.4)
            Spacer(minLength: 0)
            if let number = player.jerseyNumber {
                Text("#\(number)")
                    .font(.custom("AppleSDGothicNeo-Bold", size: 13))
                    .foregroundStyle(NeonPalette.magenta)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: nameBarHeight)
        .frame(maxWidth: .infinity)
        .background(NeonPalette.cyanFade)
        .overlay(Rectangle().stroke(NeonPalette.magenta, lineWidth: 2))
    }

    /// Vertical cyan column down the right side with the team name reading top-to-bottom.
    private var teamColumn: some View {
        Color.clear
            .frame(width: columnWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                GeometryReader { geo in
                    Text(player.teams.first?.name ?? "")
                        .font(CustomFont.fakeSerif(48))
                        .foregroundStyle(NeonPalette.yellow)
                        .shadow(color: NeonPalette.magenta, radius: 0, x: 1.5, y: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.25)
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(90), anchor: .topLeading)
                        .offset(x: geo.size.width)
                }
            }
            .background(NeonPalette.cyanFade)
            .overlay(Rectangle().stroke(NeonPalette.magenta, lineWidth: 2))
    }

    /// Yellow ERA square with the AVG circle overlapping it, hanging below the name bar.
    private var statBadges: some View {
        HStack(alignment: .top, spacing: -14) {
            VStack(spacing: -2) {
                Text("ERA")
                    .font(.custom("AppleSDGothicNeo-Bold", size: 11))
                    .foregroundStyle(NeonPalette.cyan)
                Text(StatFormat.ratio(pitching.earnedRunAverage))
                    .font(.custom("AppleSDGothicNeo-Bold", size: 15))
                    .foregroundStyle(NeonPalette.ink)
            }
            .frame(width: 58, height: 44)
            .background(NeonPalette.yellowFade)

            VStack(spacing: -2) {
                Text("AVG")
                    .font(.custom("AppleSDGothicNeo-Bold", size: 11))
                    .foregroundStyle(NeonPalette.cyan)
                Text(StatFormat.rate(batting.battingAverage))
                    .font(.custom("AppleSDGothicNeo-Bold", size: 15))
                    .foregroundStyle(NeonPalette.ink)
            }
            .frame(width: 58, height: 58)
            .background(Circle().fill(NeonPalette.yellowFade))
            .offset(y: 12)   // circle sits slightly lower than the ERA square
        }
    }
}

// MARK: - Back

struct Neon90sCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            Retro80sBackground()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(NeonPalette.panel)
                .overlay(Rectangle().stroke(NeonPalette.magenta, lineWidth: 2))
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name)
                        .font(CustomFont.fakeSerif(22))
                        .foregroundStyle(NeonPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name)
                                .font(.custom("AppleSDGothicNeo-Bold", size: 12))
                                .foregroundStyle(NeonPalette.magenta)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)")
                                .font(.custom("AppleSDGothicNeo-Bold", size: 12))
                                .foregroundStyle(NeonPalette.ink)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(NeonPalette.cyan).frame(height: 3)

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
            .font(.custom("AppleSDGothicNeo-Bold", size: 12))
            .foregroundStyle(NeonPalette.magenta)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1)
                        .font(.custom("AppleSDGothicNeo-Bold", size: 13))
                        .foregroundStyle(NeonPalette.ink)
                    Text(stat.0)
                        .font(.custom("AppleSDGothicNeo-Bold", size: 9))
                        .foregroundStyle(NeonPalette.magenta)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(NeonPalette.cyan.opacity(0.22))
            }
        }
    }
}
