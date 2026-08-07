//
//  ChallengesView.swift
//  Blitzball Stat Tracker
//
//  A read-only recap of manager challenges for the game being tracked — reached from the live game
//  menu's "View Challenges" (shown only when challenges are enabled). Since the scoring redesign there
//  was nowhere to see how many remain; this also logs who challenged, when, and how it turned out.
//

import SwiftUI

struct ChallengesView: View {
    @Bindable var game: Game
    @Environment(\.dismiss) private var dismiss

    /// The log newest-first, so the most recent challenge reads at the top.
    private var history: [ChallengeCall] { game.challengeCalls.reversed() }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Remaining").foregroundStyle(.white)) {
                    teamSummary(isHome: false)   // away
                    teamSummary(isHome: true)    // home
                }
                .blitzCardRow()

                Section(header: Text("History").foregroundStyle(.white)) {
                    if history.isEmpty {
                        Text("No challenges called yet.")
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        ForEach(history) { call in
                            historyRow(call)
                        }
                    }
                }
                .blitzCardRow()
            }
            .blitzListStyle()
            .blitzDarkBackground()
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Remaining, per team

    private func teamSummary(isHome: Bool) -> some View {
        let remaining = game.challengesRemaining(isHome: isHome)
        let cap = game.settings.challenges
        let upheld = game.challengesWon(isHome: isHome)
        let lost = game.challengesUsed(isHome: isHome)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(teamName(isHome)).font(.headline)
                Spacer()
                Text("\(remaining) of \(cap) left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(remaining == 0 ? .red : .white)
            }
            Text("\(upheld) upheld · \(lost) lost")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 2)
    }

    // MARK: - History row

    private func historyRow(_ call: ChallengeCall) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(teamName(call.isHome)).font(.subheadline.weight(.semibold))
                Text("\(halfLabel(call)) · \(call.upheld ? "call overturned" : "call stood")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            outcomeBadge(upheld: call.upheld)
        }
        .padding(.vertical, 2)
    }

    private func outcomeBadge(upheld: Bool) -> some View {
        Text(upheld ? "Overturned" : "Stood")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(upheld ? Color.green : Color.red, in: Capsule())
    }

    // MARK: - Labels

    private func teamName(_ isHome: Bool) -> String {
        (isHome ? game.homeTeam?.name : game.awayTeam?.name) ?? (isHome ? "Home" : "Away")
    }

    /// "Top 3" / "Bottom 3" — when in the game the challenge was called.
    private func halfLabel(_ call: ChallengeCall) -> String {
        "\(call.isTopInning ? "Top" : "Bottom") \(call.inning)"
    }
}
