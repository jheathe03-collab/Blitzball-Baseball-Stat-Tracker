//
//  AllStarCardTemplate.swift
//  Blitzball Stat Tracker
//
//  Template #4 — "All-Star," a 1990-Topps style card. Front: an orange-abstract background with bold
//  orange boxes for the top team-name/number bar and a vertical player-name column, a black-framed
//  photo, and small logo + ERA boxes in the photo's bottom corners. Back matches with a cream stat
//  panel over the orange background.
//

import SwiftUI
import UIKit

private enum OrangePalette {
    static let orange     = Color(red: 0.859, green: 0.361, blue: 0.294)  // #db5c4b — text blocks
    static let text       = Color(red: 0.949, green: 0.945, blue: 0.929)  // #f2f1ed — block text
    static let orangeDark = Color(red: 0.68, green: 0.20, blue: 0.10)
    static let orangeLite = Color(red: 0.97, green: 0.55, blue: 0.28)   // background fallback
    static let cream      = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let ink        = Color(red: 0.11, green: 0.11, blue: 0.11)
}

/// The card background: the "OrangeAbstract" image asset if present, else a plain orange fallback.
private struct OrangeAbstractBackground: View {
    var body: some View {
        GeometryReader { geo in
            if let ui = UIImage(named: "OrangeAbstract") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                OrangePalette.orangeLite
            }
        }
    }
}

// MARK: - Front

struct AllStarCardFront: View {
    let player: Player
    private var pitching: PitchingStats { player.careerPitching }

    var body: some View {
        ZStack {
            OrangeAbstractBackground()
            VStack(spacing: 0) {
                topBox
                HStack(spacing: 8) {
                    photoFrame.padding(.top, 6)   // small gap below the top box, over the photo only
                    nameColumn                    // extends up to touch the top box (connected)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OrangePalette.orangeDark, lineWidth: 2))
    }

    /// Bold orange bar across the top: team name + number.
    private var topBox: some View {
        HStack(spacing: 6) {
            Text((player.teams.first?.name ?? "").uppercased())
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 4)
            if let number = player.jerseyNumber {
                Text("#\(number)").monospacedDigit()
            }
        }
        .font(.headline.weight(.black))
        .foregroundStyle(OrangePalette.text)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(OrangePalette.orange)
        // Round the top corners; square the bottom-right so it connects to the name column below it.
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: 6,
                                                             bottomTrailing: 0, topTrailing: 6),
                                          style: .continuous))
    }

    /// Player photo in a thin black frame, with small logo + ERA boxes in the bottom corners.
    private var photoFrame: some View {
        PlayerPortrait(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black))
            .overlay(alignment: .bottomLeading) { logoBox.padding(6) }
            .overlay(alignment: .bottomTrailing) { eraBox.padding(6) }
    }

    /// Bold orange vertical column with the player name reading top-to-bottom.
    private var nameColumn: some View {
        Color.clear
            .frame(width: 50)
            .frame(maxHeight: .infinity)
            .overlay(verticalName)
            .background(OrangePalette.orange)
            // Square the top so it connects to the top box; round the bottom corners (card edge).
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 6,
                                                                 bottomTrailing: 6, topTrailing: 0),
                                              style: .continuous))
    }

    /// Player name rotated to fill a vertical column (rotate around top-leading + offset to reposition).
    private var verticalName: some View {
        GeometryReader { geo in
            Text(player.name.uppercased())
                .font(.system(size: 90, weight: .black))   // large; scales down to fill the column
                .foregroundStyle(OrangePalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.05)
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(.degrees(90), anchor: .topLeading)
                .offset(x: geo.size.width)
        }
    }

    private var logoBox: some View {
        TeamLogoView(team: player.teams.first, size: 42)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OrangePalette.cream))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.black, lineWidth: 1))
    }

    private var eraBox: some View {
        VStack(spacing: 0) {
            Text("ERA").font(.system(size: 7, weight: .bold)).foregroundStyle(OrangePalette.ink)
            Text(StatFormat.ratio(pitching.earnedRunAverage))
                .font(.caption.bold().monospacedDigit()).foregroundStyle(OrangePalette.ink)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OrangePalette.cream))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.black, lineWidth: 1))
    }
}

// MARK: - Back

struct AllStarCardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            OrangeAbstractBackground()
            content
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OrangePalette.cream))
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OrangePalette.orangeDark, lineWidth: 2))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name.uppercased())
                        .font(.headline.weight(.black))
                        .foregroundStyle(OrangePalette.orange)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption.bold()).foregroundStyle(OrangePalette.ink)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(OrangePalette.orangeDark)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(OrangePalette.orange).frame(height: 2)

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
            .foregroundStyle(OrangePalette.orange)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(OrangePalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(OrangePalette.orangeDark)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(OrangePalette.orange.opacity(0.3), lineWidth: 0.5))
            }
        }
    }
}
