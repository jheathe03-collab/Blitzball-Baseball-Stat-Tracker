//
//  ContactTypeSheet.swift
//  Blitzball Stat Tracker
//
//  Step one of tagging a batted ball: HOW it was hit. A quick sheet after a 1B/2B/3B/HR/Out button;
//  once a type is chosen the sheet closes and the WHERE step happens inline on the live field (see
//  `FieldPositionPicker`), so the scorer taps the location on the field they're already looking at.
//
//  Besides the five contact types, the sheet carries the "result overrides" — choices that change
//  WHAT the play was rather than how it was hit, each keeping the same base the button implied:
//    • Actually an Out — flips a mistaken hit to an out (keeps asking the contact type).
//    • Sacrifice Fly — an out that scores the runner from third (offered only when possible).
//    • Error / Fielder's Choice — the batter reached the tapped base on a misplay; the location
//      step then identifies the FIELDER (the one charged the error, or who made the choice). These
//      replace the contact-type answer, so they pass no `BattedBallType`.
//
//  On selection it hands back (finalOutcome, type?); cancelling records nothing.
//

import SwiftUI

struct ContactTypeSheet: View {
    /// The button that was tapped (single/double/triple/homeRun/out). Never a walk/strikeout/HBP —
    /// those have no batted ball and never open this sheet.
    let sourceOutcome: PlateAppearanceOutcome
    /// Whether a sacrifice fly is possible right now (fewer than the inning's last out, and a runner
    /// on third to tag). Decided by the live screen from game state; gates the Sac Fly row.
    let allowsSacFly: Bool
    /// Whether a fielder's choice is possible — i.e. there's a runner on base for the defense to play
    /// on. Error needs no runner, so it's always offered; FC is hidden with the bases empty.
    let allowsFieldersChoice: Bool
    /// Called once a result is chosen. `type` is nil for the error / fielder's-choice paths, which
    /// describe the fielder via the location step instead of a contact type.
    let onSelect: (PlateAppearanceOutcome, BattedBallType?) -> Void
    @Environment(\.dismiss) private var dismiss

    // The play switched to an out — either it started as one, or the user tapped the Out escape.
    @State private var isOut: Bool

    init(sourceOutcome: PlateAppearanceOutcome,
         allowsSacFly: Bool,
         allowsFieldersChoice: Bool,
         onSelect: @escaping (PlateAppearanceOutcome, BattedBallType?) -> Void) {
        self.sourceOutcome = sourceOutcome
        self.allowsSacFly = allowsSacFly
        self.allowsFieldersChoice = allowsFieldersChoice
        self.onSelect = onSelect
        _isOut = State(initialValue: sourceOutcome.isOut)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("How was it hit?") {
                    ForEach(BattedBallType.menuOrder, id: \.self) { t in
                        row(t.label) {
                            onSelect(isOut ? .out : sourceOutcome, t)
                            dismiss()
                        }
                    }
                }

                // Reached on a misplay — only on a plain hit (the base you tapped is where the batter
                // ended up). The location step then names the fielder. Hidden once it's an out.
                // Fielder's choice needs a runner to play on, so it comes and goes with the bases.
                if !isOut, let errorOut = errorOutcome {
                    Section {
                        row("Error") { onSelect(errorOut, nil); dismiss() }
                        if let fcOut = fieldersChoiceOutcome, allowsFieldersChoice {
                            row("Fielder's Choice") { onSelect(fcOut, nil); dismiss() }
                        }
                    } footer: {
                        Text(reachedFooter)
                    }
                }

                // Sac fly — only when one can actually happen (fewer than the last out, runner on
                // third). Records the out, credits the RBI, and scores the runner from third.
                if allowsSacFly {
                    Section {
                        row("Sacrifice Fly") { onSelect(.sacrificeFly, .flyBall); dismiss() }
                    } footer: {
                        Text("The runner on third scores (RBI to the batter) and the batter is out — "
                            + "not charged an at-bat. Then pick where it was caught.")
                    }
                }

                // The Out escape — only on a play that isn't already an out.
                if !isOut {
                    Section {
                        Button(role: .destructive) {
                            isOut = true
                        } label: {
                            Label("Actually an Out", systemImage: "hand.raised.fill")
                        }
                    } footer: {
                        Text("Records an out instead of a \(sourceOutcome.playLabel.lowercased()). "
                            + "You'll still pick the contact type and where it was fielded.")
                    }
                }
            }
            .navigationTitle(contactTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Size the sheet to its content so the footers are never clipped. Sections come and go with
        // the play (out vs hit, sac-fly eligibility), so the height tracks what's actually shown; a
        // `.large` fallback lets the List scroll if very large Dynamic Type sizes overflow.
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
    }

    /// A plain tappable row: label on the left, disclosure chevron on the right.
    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Approximate content height in points, so the sheet opens exactly tall enough. Tuned to the
    /// default text size; the `.large` fallback handles anything larger.
    private var sheetHeight: CGFloat {
        let navBar: CGFloat = 44
        let typeSection: CGFloat = 38 /* header */ + 5 * 44 /* rows */
        let reachedRows: CGFloat = allowsFieldersChoice ? 2 : 1
        let reachedSection: CGFloat = (!isOut && errorOutcome != nil) ? (30 + reachedRows * 44 + 76) : 0
        let sacFlySection: CGFloat = allowsSacFly ? (30 + 44 + 58) : 0
        let outSection: CGFloat = isOut ? 0 : (30 + 44 + 76)
        let padding: CGFloat = 44
        return navBar + typeSection + reachedSection + sacFlySection + outSection + padding
    }

    /// "Single — Contact", or "Out — Contact" once the play is an out.
    private var contactTitle: String {
        "\(isOut ? "Out" : sourceOutcome.playLabel) — Contact"
    }

    // MARK: - Reached-on-misplay mapping

    /// The reached-on-error outcome for the base the button implied (nil when the source isn't a
    /// plain hit). Each lands the batter on the same base, credited no hit.
    private var errorOutcome: PlateAppearanceOutcome? {
        switch sourceOutcome {
        case .single: return .reachedOnError
        case .double: return .reachedOnTwoBaseError
        case .triple: return .reachedOnThreeBaseError
        default:      return nil
        }
    }

    /// The fielder's-choice outcome for the base the button implied.
    private var fieldersChoiceOutcome: PlateAppearanceOutcome? {
        switch sourceOutcome {
        case .single: return .fieldersChoice
        case .double: return .fieldersChoiceToSecond
        case .triple: return .fieldersChoiceToThird
        default:      return nil
        }
    }

    /// Footer under the reached-on-misplay section, worded for whichever rows are shown.
    private var reachedFooter: String {
        let base = "The batter reached \(baseWord) on a misplay — no hit."
        if allowsFieldersChoice {
            return base + " Next, tap the fielder who booted it (Error) or made the play "
                + "(Fielder's Choice)."
        }
        return base + " Next, tap the fielder who booted it."
    }

    /// "first" / "second" / "third" — the base the tapped button put the batter on.
    private var baseWord: String {
        switch sourceOutcome {
        case .double: return "second"
        case .triple: return "third"
        default:      return "first"
        }
    }
}
