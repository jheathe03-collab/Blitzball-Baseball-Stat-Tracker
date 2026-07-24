//
//  PlayerCardView.swift
//  Blitzball Stat Tracker
//
//  A player's "baseball card": a flip card (see FlipCard) whose front shows their portrait, identity
//  and hero stats, and whose back shows a full career stat table. The card frame is drawn natively in
//  SwiftUI (red/blue angular "sport" look) — no image asset — so there's nothing external to license.
//  The only imported image is the optional player photo.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - Palette (sampled from the sport-template reference)

private enum CardPalette {
    static let navy    = Color(red: 0.09, green: 0.14, blue: 0.34)
    static let blue    = Color(red: 0.15, green: 0.34, blue: 0.82)
    static let magenta = Color(red: 0.85, green: 0.20, blue: 0.46)
    static let red     = Color(red: 0.80, green: 0.12, blue: 0.15)
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
                // Fill most of the width, keeping the 2.5:3.5 card ratio; leave ~150pt below for the
                // "tap to flip" hint + photo button.
                let cardW = min(geo.size.width * 0.92, (geo.size.height - 150) / 1.4)
                let cardH = cardW * 1.4
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

// MARK: - Card frame (native SwiftUI "sport" styling)

private struct CardFrame: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [CardPalette.navy, CardPalette.blue],
                           startPoint: .topTrailing, endPoint: .bottomLeading)

            // A couple of angular accent slashes for the sport look (low opacity).
            Slash().fill(CardPalette.blue.opacity(0.55))
                .frame(width: 90).rotationEffect(.degrees(18))
                .offset(x: 60, y: -40)
            Slash().fill(CardPalette.magenta.opacity(0.5))
                .frame(width: 26).rotationEffect(.degrees(18))
                .offset(x: 8, y: 20)

            // Bold red accent stripe down the left edge, with a thin magenta companion line.
            HStack(spacing: 3) {
                Rectangle().fill(CardPalette.red).frame(width: 12)
                Rectangle().fill(CardPalette.magenta).frame(width: 3)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white, lineWidth: 3)
        )
    }
}

/// A leaning parallelogram used for the angular accent slashes.
private struct Slash: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let slant = rect.width * 0.6
        p.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Player portrait

private struct PlayerPortrait: View {
    let player: Player

    var body: some View {
        ZStack {
            if let data = player.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.08))
                Image(systemName: "person.fill")
                    .resizable().scaledToFit()
                    .padding(28)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CardPalette.magenta.opacity(0.8), lineWidth: 2)
        )
    }
}

// MARK: - Front face

private struct CardFront: View {
    let player: Player

    private var batting: BattingStats { player.careerBatting }

    var body: some View {
        ZStack {
            CardFrame()
            VStack(spacing: 10) {
                HStack {
                    TeamLogoView(team: player.teams.first, size: 30)
                    Spacer()
                    if let number = player.jerseyNumber {
                        Text("#\(number)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }

                PlayerPortrait(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 2) {
                    Text(player.name)
                        .font(Theme.screenSubtitle)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let stance = player.battingStance {
                        Text(stance == "LH" ? "Bats: Left" : "Bats: Right")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                HStack(spacing: 6) {
                    heroStat("AVG", StatFormat.rate(batting.battingAverage))
                    heroStat("HR", "\(batting.homeRuns)")
                    heroStat("RBI", "\(batting.rbi)")
                    heroStat("OPS", StatFormat.rate(batting.onBasePlusSlugging))
                }
            }
            .padding(16)
            .padding(.leading, 6)   // clear the red stripe
        }
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Back face

private struct CardBack: View {
    let player: Player

    private var batting: BattingStats { player.careerBatting }
    private var pitching: PitchingStats { player.careerPitching }
    private var games: Int { player.finalStatLines.count }

    var body: some View {
        ZStack {
            CardFrame()
            VStack(alignment: .leading, spacing: 8) {
                Text(player.name)
                    .font(Theme.screenSubtitle)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)

                sectionLabel("Batting — Career")
                statGrid(battingStats)

                if pitching.outsRecorded > 0 {
                    sectionLabel("Pitching — Career")
                    statGrid(pitchingStats)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .padding(.leading, 6)
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
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(CardPalette.magenta)
            .padding(.top, 2)
    }

    private func statGrid(_ stats: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 1) {
                    Text(stat.1).font(.caption2.bold().monospacedDigit()).foregroundStyle(.white)
                    Text(stat.0).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
