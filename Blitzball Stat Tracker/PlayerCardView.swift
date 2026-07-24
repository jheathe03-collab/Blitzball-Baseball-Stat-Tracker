//
//  PlayerCardView.swift
//  Blitzball Stat Tracker
//
//  A player's "baseball card": a flip card (see FlipCard) styled after a classic 1991-Topps layout —
//  a cream border, a thin blue+red double frame, the player's photo, a corner team logo, batting
//  average up top, a team-name banner, and a bottom number/name strip. The back matches with the same
//  cream/framed look over a full career stat table. All drawn natively in SwiftUI — the only imported
//  image is the optional player photo.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - Palette (classic cardboard look)

private enum CardPalette {
    static let cream     = Color(red: 0.94, green: 0.92, blue: 0.85)
    static let frameBlue = Color(red: 0.11, green: 0.23, blue: 0.55)
    static let frameRed  = Color(red: 0.74, green: 0.15, blue: 0.17)
    static let navy      = Color(red: 0.09, green: 0.16, blue: 0.38)
    static let gold      = Color(red: 0.85, green: 0.66, blue: 0.22)
    static let ink       = Color(red: 0.12, green: 0.14, blue: 0.22)
}

// MARK: - Full-screen presentation

struct PlayerCardView: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            GeometryReader { geo in
                // Card height-to-width ratio (real card is 1.4; taller reads more rectangular).
                let ratio: CGFloat = 1.5
                // Make the card NARROWER (0.72 of width) so it reads rectangular and always keeps
                // side margins; also cap the height so it never runs past the controls below.
                let cardW = min(geo.size.width * 0.72, (geo.size.height - 220) / ratio)
                let cardH = cardW * ratio
                VStack(spacing: 18) {
                    FlipCard {
                        CardFront(player: player)
                    } back: {
                        CardBack(player: player)
                    }
                    .frame(width: cardW, height: cardH)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 10)

                    Text("Tap the card to flip")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(player.photoData == nil ? "Add Photo" : "Change Photo",
                              systemImage: "photo.badge.plus")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let thumb = TeamLogo.squareThumbnail(from: data) else { return }
        player.photoData = thumb
        photoItem = nil
    }
}

// MARK: - Shared vintage frame (cream border + blue/red double line)

private struct VintageCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    Rectangle().stroke(CardPalette.frameBlue, lineWidth: 3)
                    Rectangle().inset(by: 3).stroke(CardPalette.frameRed, lineWidth: 2)
                }
            )
            .padding(14)                          // cream border thickness
            .background(CardPalette.cream)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func vintageCard() -> some View { modifier(VintageCard()) }
}

/// A ribbon banner for the team name: a "flag" chevron point on the LEFT, squared off on the RIGHT.
private struct BannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(rect.height * 0.7, rect.width * 0.14)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))       // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))    // top-right
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))    // bottom-right (squared)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))    // bottom-left
        p.addLine(to: CGPoint(x: rect.minX + notch, y: rect.midY))  // left chevron point
        p.closeSubpath()
        return p
    }
}

// MARK: - Player portrait (fills its area)

private struct PlayerPortrait: View {
    let player: Player

    var body: some View {
        if let data = player.photoData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                CardPalette.frameBlue.opacity(0.12)
                Image(systemName: "person.fill")
                    .resizable().scaledToFit()
                    .padding(44)
                    .foregroundStyle(CardPalette.frameBlue.opacity(0.4))
            }
        }
    }
}

// MARK: - Front face

private struct CardFront: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }

    var body: some View {
        VStack(spacing: 0) {
            photoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            nameStrip
        }
        .vintageCard()
    }

    private var photoArea: some View {
        ZStack { PlayerPortrait(player: player) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) { teamLogoBadge.padding(8) }
            .overlay(alignment: .topTrailing) { avgBadge.padding(8) }
            .overlay(alignment: .bottomTrailing) { teamBanner.padding(.bottom, 6).padding(.trailing, 8) }
    }

    private var nameStrip: some View {
        HStack {
            if let number = player.jerseyNumber {
                Text("#\(number)").font(.subheadline.weight(.black).monospacedDigit())
            }
            Spacer()
            Text(player.name.uppercased())
                .font(.subheadline.weight(.black))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [CardPalette.navy, CardPalette.frameBlue],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    private var teamLogoBadge: some View {
        TeamLogoView(team: player.teams.first, size: 54)
            .padding(5)
            .background(Circle().fill(.white.opacity(0.92)))
            .overlay(Circle().stroke(CardPalette.frameBlue, lineWidth: 2))
    }

    private var avgBadge: some View {
        VStack(spacing: 0) {
            Text("AVG").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            Text(StatFormat.rate(batting.battingAverage))
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(CardPalette.frameBlue))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CardPalette.gold, lineWidth: 1.5))
    }

    @ViewBuilder
    private var teamBanner: some View {
        if let team = player.teams.first {
            Text(team.name.uppercased())
                .font(.system(.subheadline, design: .serif).weight(.black))
                .italic()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.leading, 28).padding(.trailing, 16).padding(.vertical, 6)
                .background(BannerShape().fill(CardPalette.navy))
                .overlay(BannerShape().stroke(CardPalette.gold, lineWidth: 2))
        }
    }
}

// MARK: - Back face (matches the front's cream/framed look)

private struct CardBack: View {
    let player: Player
    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        content.vintageCard()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoView(team: player.teams.first, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name.uppercased())
                        .font(.headline.weight(.black))
                        .foregroundStyle(CardPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let team = player.teams.first {
                            Text(team.name).font(.caption).foregroundStyle(CardPalette.frameBlue)
                        }
                        if let number = player.jerseyNumber {
                            Text("#\(number)").font(.caption.bold()).foregroundStyle(CardPalette.frameRed)
                        }
                    }
                }
                Spacer()
            }
            Rectangle().fill(CardPalette.frameRed).frame(height: 2)

            sectionLabel("Batting — Career")
            statGrid(battingStats)

            if pitching.outsRecorded > 0 {
                sectionLabel("Pitching — Career")
                statGrid(pitchingStats)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
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
            .foregroundStyle(CardPalette.frameRed)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 0) {
                    Text(stat.1).font(.caption.bold().monospacedDigit()).foregroundStyle(CardPalette.ink)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(CardPalette.frameBlue)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(CardPalette.frameBlue.opacity(0.3), lineWidth: 0.5))
            }
        }
    }
}
