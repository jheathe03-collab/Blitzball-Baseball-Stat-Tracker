//
//  VintageCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #3 — "Vintage," a 1983-Topps-style card. Front: aged-paper background, the player photo
//  in a green frame, the blitzball logo top-right, a cream/green team-logo circle straddling the
//  bottom-left, the player name (green) + number (black), and the team name (yellow) on a crimson
//  bar. Back matches with the paper background + a green frame over the career stat table.
//

import SwiftUI
import UIKit

private enum VintagePalette {
    static let green   = Color(red: 0.20, green: 0.62, blue: 0.28)
    static let crimson = Color(red: 0.45, green: 0.09, blue: 0.14)
    static let yellow  = Color(red: 0.96, green: 0.80, blue: 0.20)
    static let cream   = Color(red: 0.93, green: 0.90, blue: 0.80)
    static let ink     = Color(red: 0.11, green: 0.11, blue: 0.11)
}

/// The card background: the "PaperTexture" image asset if present, else a plain cream fallback.
/// GeometryReader clamps the image so its pixel size can't drag the card's layout.
private struct PaperBackground: View {
    var body: some View {
        GeometryReader { geo in
            if let ui = UIImage(named: "PaperTexture") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                VintagePalette.cream
            }
        }
    }
}

// MARK: - Front

struct VintageCardFront: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }

    var body: some View {
        ZStack {
            PaperBackground()
            framedContent.padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VintagePalette.green, lineWidth: 2))
    }

    /// Photo + bottom info wrapped in ONE continuous green frame, with a green seam line (meeting the
    /// frame on both sides) that the team-logo circle straddles — like the real 1983 card.
    private var framedContent: some View {
        VStack(spacing: 0) {
            PlayerPortrait(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) { blitzLogo.padding(6) }
            Rectangle().fill(VintagePalette.green).frame(height: 3)   // seam, runs to both frame sides
            bottomSection
                .frame(height: 96)
                .overlay(alignment: .topLeading) { teamCircle.offset(x: 4, y: -33) }
        }
        // Clip the content to the frame shape so the photo and crimson fill right up to the green
        // frame (no paper gap), then stroke the same shape as the frame line.
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(VintagePalette.green, lineWidth: 3)
        )
    }

    private var blitzLogo: some View {
        Image("BlitzBalllogo").resizable().scaledToFit().frame(width: 40, height: 40)
    }

    private var teamCircle: some View {
        TeamLogoView(team: player.teams.first, size: 95)
            .padding(7)
            .background(Circle().fill(VintagePalette.cream))
            .overlay(Circle().stroke(VintagePalette.green, lineWidth: 2.5))
            .overlay(Circle().inset(by: 6).stroke(VintagePalette.ink.opacity(0.4), lineWidth: 1))
    }

    /// The whole bottom area is crimson: a cream name plate floats on the right, the team name sits
    /// in yellow at the bottom-right, and the team-logo circle straddles in from the top-left.
    private var bottomSection: some View {
        ZStack {
            VintagePalette.crimson
            VStack(spacing: 0) {
                HStack { Spacer(minLength: 0); nameBox }
                    .padding(.top, 8).padding(.trailing, 10)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Text((player.teams.first?.name ?? "").uppercased())
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(VintagePalette.yellow)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.trailing, 12).padding(.bottom, 8)
            }
        }
    }

    /// Cream name plate: player name (green) over number (black), right-aligned.
    private var nameBox: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(player.name.uppercased())
                .font(.subheadline.weight(.black))
                .foregroundStyle(VintagePalette.green)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let number = player.jerseyNumber {
                Text("#\(number)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(VintagePalette.ink)
            }
        }
        .frame(width: 150, alignment: .trailing)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(VintagePalette.cream))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(VintagePalette.green, lineWidth: 2.5))
    }
}

// MARK: - Back

struct VintageCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            PaperBackground()
            content
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VintagePalette.green, lineWidth: 3)
                        .padding(8)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VintagePalette.green, lineWidth: 2))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name.uppercased())
                        .font(.headline.weight(.black))
                        .foregroundStyle(VintagePalette.green)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption.bold()).foregroundStyle(VintagePalette.crimson)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(VintagePalette.ink)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(VintagePalette.crimson).frame(height: 2)

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
            .foregroundStyle(VintagePalette.crimson)
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
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(VintagePalette.green.opacity(0.35), lineWidth: 0.5))
            }
        }
    }
}
