//
//  BracketView.swift
//  Blitzball Stat Tracker
//
//  Draws a single-elimination bracket: match boxes laid out round-by-round with elbow connector
//  lines, scrollable both ways. Shows seeds, byes, scores, and the winner; playable matches are
//  highlighted and tappable.
//

import SwiftUI
import SwiftData

private let boxWidth: CGFloat = 168
private let boxHeight: CGFloat = 52
private let hGap: CGFloat = 44
private let vGap: CGFloat = 16
private let topInset: CGFloat = 8

struct BracketView: View {
    let rounds: Int
    let matches: [BracketDisplayMatch]
    var onTap: (PersistentIdentifier) -> Void = { _ in }

    private var byRound: [[BracketDisplayMatch]] {
        (0..<rounds).map { r in matches.filter { $0.round == r }.sorted { $0.indexInRound < $1.indexInRound } }
    }
    private var firstRoundCount: Int { byRound.first?.count ?? 0 }

    private var centers: [Int: CGPoint] {
        var result: [Int: CGPoint] = [:]
        let slotUnit = boxHeight + vGap
        let rounds = byRound
        for (r, roundMatches) in rounds.enumerated() {
            for (m, match) in roundMatches.enumerated() {
                let x = CGFloat(r) * (boxWidth + hGap) + boxWidth / 2
                let y: CGFloat
                if r == 0 {
                    y = CGFloat(m) * slotUnit + boxHeight / 2 + topInset
                } else {
                    let c1 = result[rounds[r - 1][m * 2].id]?.y ?? 0
                    let c2 = result[rounds[r - 1][m * 2 + 1].id]?.y ?? 0
                    y = (c1 + c2) / 2
                }
                result[match.id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private var canvasSize: CGSize {
        let width = CGFloat(rounds) * (boxWidth + hGap) - hGap
        let height = CGFloat(firstRoundCount) * (boxHeight + vGap) + topInset
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    var body: some View {
        if matches.isEmpty {
            Text("Add at least two teams to see the bracket.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    connectors
                    ForEach(matches) { match in
                        MatchBox(match: match, onTap: onTap)
                            .frame(width: boxWidth, height: boxHeight)
                            .position(centers[match.id] ?? .zero)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .padding(8)
            }
        }
    }

    private var connectors: some View {
        let centers = self.centers
        let rounds = byRound
        return Canvas { context, _ in
            guard self.rounds > 1 else { return }
            for r in 1..<self.rounds {
                for (m, parent) in rounds[r].enumerated() {
                    guard let pc = centers[parent.id] else { continue }
                    let parentLeft = CGPoint(x: pc.x - boxWidth / 2, y: pc.y)
                    for childIndex in [m * 2, m * 2 + 1] where childIndex < rounds[r - 1].count {
                        guard let cc = centers[rounds[r - 1][childIndex].id] else { continue }
                        let childRight = CGPoint(x: cc.x + boxWidth / 2, y: cc.y)
                        let midX = (childRight.x + parentLeft.x) / 2
                        var path = Path()
                        path.move(to: childRight)
                        path.addLine(to: CGPoint(x: midX, y: childRight.y))
                        path.addLine(to: CGPoint(x: midX, y: parentLeft.y))
                        path.addLine(to: parentLeft)
                        context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
                    }
                }
            }
        }
    }
}

private struct MatchBox: View {
    let match: BracketDisplayMatch
    let onTap: (PersistentIdentifier) -> Void

    var body: some View {
        let box = VStack(spacing: 0) {
            slotRow(match.top)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            slotRow(match.bottom)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(match.isPlayable ? Color.accentColor : .white.opacity(0.18),
                        lineWidth: match.isPlayable ? 1.8 : 1)
        )

        if let id = match.gameID {
            Button { onTap(id) } label: { box }
                .buttonStyle(.plain)
        } else {
            box
        }
    }

    private func slotRow(_ slot: BracketDisplaySlot) -> some View {
        HStack(spacing: 6) {
            if let seed = slot.seed {
                Text("\(seed)").font(.caption2).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45)).frame(width: 16, alignment: .trailing)
            } else {
                Text("").frame(width: 16)
            }

            if let name = slot.name {
                Text(name)
                    .font(.caption).fontWeight(slot.isWinner ? .bold : .regular)
                    .foregroundStyle(.white.opacity(slot.isWinner ? 1 : 0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if slot.isBye {
                Text("Bye").font(.caption).italic().foregroundStyle(.white.opacity(0.4))
            } else {
                Text("—").font(.caption).foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 0)

            if let score = slot.score {
                Text("\(score)").font(.caption).monospacedDigit()
                    .fontWeight(slot.isWinner ? .bold : .regular)
                    .foregroundStyle(.white.opacity(slot.isWinner ? 1 : 0.6))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: (boxHeight - 1) / 2)
    }
}
