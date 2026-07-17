//
//  LeaderTickerView.swift
//  Blitzball Stat Tracker
//
//  A continuously-scrolling "ticker" bar pinned to the bottom of the Main Menu, showing the
//  all-time Top-3 for the counting stats that DON'T already appear in the Leaderboard card
//  (Runs, RBIs, Singles, Doubles, Triples, Walks, HBP, Ks, Kʟ).
//
//  The marquee uses the seamless two-copy technique: render the text twice, measure one copy, and
//  animate the offset by one copy's width forever — so it loops with no visible jump.
//

import SwiftUI
import SwiftData

// MARK: - The data + bar

struct LeaderTicker: View {
    @Query private var players: [Player]

    var body: some View {
        let text = tickerText
        if !text.isEmpty {
            MarqueeText(text: text)
                .foregroundStyle(.white)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.85))
                .overlay(alignment: .top) {
                    Rectangle().frame(height: 0.5).foregroundStyle(.white.opacity(0.12))
                }
                .id(text)   // rebuild the marquee cleanly if the leaders change
        }
    }

    /// Build "LEAGUE LEADERS  (Runs) - A - 3, B - 2, C - 1  •  (RBIs) - …" from career totals.
    /// Only categories with at least one non-zero leader are included.
    private var tickerText: String {
        let entries = players.map { (name: $0.name, stats: $0.careerBatting) }

        // label → how to pull that counting stat out of a BattingStats line.
        let categories: [(String, (BattingStats) -> Int)] = [
            ("Runs",    { $0.runsScored }),
            ("RBIs",    { $0.rbi }),
            ("Singles", { $0.singles }),
            ("Doubles", { $0.doubles }),
            ("Triples", { $0.triples }),
            ("Walks",   { $0.walks }),
            ("HBP",     { $0.hitByPitch }),
            ("Ks",      { $0.strikeouts }),
            ("Kʟ",      { $0.strikeoutsLooking }),
        ]

        let parts: [String] = categories.compactMap { label, stat in
            let ranked = entries
                .map { (name: $0.name, value: stat($0.stats)) }
                .filter { $0.value > 0 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
                .prefix(3)
            guard !ranked.isEmpty else { return nil }
            let names = ranked.map { "\($0.name) - \($0.value)" }.joined(separator: ", ")
            return "(\(label)) - \(names)"
        }

        guard !parts.isEmpty else { return "" }
        return "LEAGUE LEADERS      " + parts.joined(separator: "      •      ")
    }
}

// MARK: - Reusable seamless marquee

/// A continuously scrolling marquee. Implemented in UIKit on purpose: a SwiftUI
/// `TimelineView`/`repeatForever` marquee, as a sibling of the menu's `ScrollView`, corrupts the
/// ScrollView's rendering on this OS. Here the scroll is a `CABasicAnimation` on a `CALayer`, which
/// runs on the render server entirely outside SwiftUI — so it can never disturb the menu layout.
struct MarqueeText: UIViewRepresentable {
    let text: String
    var uiFont: UIFont = .systemFont(ofSize: 13, weight: .semibold)
    var color: UIColor = .white
    var speed: CGFloat = 45      // points per second
    var spacing: CGFloat = 64    // gap between the two copies

    func makeUIView(context: Context) -> MarqueeUIView { MarqueeUIView() }

    func updateUIView(_ view: MarqueeUIView, context: Context) {
        view.configure(text: text, font: uiFont, color: color, speed: speed, spacing: spacing)
    }
}

/// Two copies of the label scrolling left forever; when copy #1 has moved one full "cycle" (its
/// width + gap), copy #2 sits exactly where #1 began — so the loop is seamless.
final class MarqueeUIView: UIView {
    private let content = UIView()
    private let labelA = UILabel()
    private let labelB = UILabel()
    private var speed: CGFloat = 45
    private var spacing: CGFloat = 64
    private var textWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(content)
        [labelA, labelB].forEach { content.addSubview($0); $0.numberOfLines = 1 }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, color: UIColor, speed: CGFloat, spacing: CGFloat) {
        self.speed = speed
        self.spacing = spacing
        for label in [labelA, labelB] {
            label.text = text
            label.font = font
            label.textColor = color
        }
        textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        labelA.frame = CGRect(x: 0, y: 0, width: textWidth, height: h)
        labelB.frame = CGRect(x: textWidth + spacing, y: 0, width: textWidth, height: h)
        content.frame = CGRect(x: 0, y: 0, width: (textWidth + spacing) * 2, height: h)
        startScrolling()
    }

    private func startScrolling() {
        content.layer.removeAnimation(forKey: "marquee")
        guard textWidth > 0, bounds.height > 0 else { return }
        let cycle = textWidth + spacing
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -cycle
        anim.duration = CFTimeInterval(cycle / max(speed, 1))
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        content.layer.add(anim, forKey: "marquee")
    }
}
