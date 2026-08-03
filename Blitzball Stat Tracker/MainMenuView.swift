//
//  MainMenuView.swift
//  Blitzball Stat Tracker
//
//  The hub shown after the splash. Owns the navigation stack; each card pushes a feature.
//  Custom branded header + dark menu cards on the blue gradient (with a faint logo watermark).
//

import SwiftUI
import SwiftData

struct MainMenuView: View {
    // Provided by RootView (which owns it) so it can also drive the splash replay.
    let router: Router

    var body: some View {
        // A local bindable handle so we can bind the stack to the router's season path.
        @Bindable var router = router

        // This NavigationStack is the ONE stack for the whole menu area. The Season area is
        // value-based (via `path`) so it can pop several levels at once; other features are links.
        NavigationStack(path: $router.seasonPath) {
            // The scrolling menu on top, the fixed-height leaders ticker pinned below. The ticker's
            // animation lives in a UIKit layer (see MarqueeText), so it can't disturb this layout.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        LeaderboardCard()

                        // Full-width feature cards.
                        NavigationLink(value: SeasonRoute.menu) {
                            MenuCard(title: "Season",
                                     subtitle: "Run a league season week by week",
                                     systemImage: "calendar")
                        }
                        NavigationLink(destination: ExhibitionView()) {
                            MenuCard(title: "Exhibition",
                                     subtitle: "Track stats for a single game",
                                     systemImage: "baseball.fill")
                        }
                        NavigationLink(destination: TournamentModeView()) {
                            MenuCard(title: "Tournament",
                                     subtitle: "Run a single-elimination bracket",
                                     systemImage: "trophy.fill")
                        }

                        // Players + Teams as a side-by-side pair.
                        HStack(spacing: 16) {
                            NavigationLink(destination: PlayersView()) {
                                MenuCard(title: "Players", systemImage: "figure.baseball", compact: true)
                            }
                            NavigationLink(destination: TeamsView()) {
                                MenuCard(title: "Teams", systemImage: "person.3.fill", compact: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                LeaderTicker()
            }
            // One handler renders every Season screen, at any depth in the season stack.
            .navigationDestination(for: SeasonRoute.self) { route in
                switch route {
                case .menu:              SeasonModeView()
                case .newSeason:         NewSeasonView()
                case .resume:            ResumeSeasonView()
                case .games(let season): SeasonGamesView(season: season)
                }
            }
            .toolbar(.hidden, for: .navigationBar)   // custom header instead of the system bar
            .blitzballBackground(watermark: true)
        }
        // Changing this id rebuilds the stack → pops back to the menu when a deep screen calls
        // router.popToRoot(). Shared via environment so those screens can trigger it.
        .id(router.resetID)
        .environment(router)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Stat Tracker")
                .font(Theme.screenTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Welcome")
                .font(Theme.screenSubtitle)
                .foregroundStyle(.white.opacity(0.65))
            Text(AppVersion.display)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

/// The running app's version, read from the bundle so it can never drift from what actually shipped
/// — useful for telling at a glance whether a device has a build that includes a given fix.
enum AppVersion {
    /// Marketing version + build, e.g. "Version 1.0 (2)".
    static var display: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}

// MARK: - Leaderboard

/// All-time, league-wide leaders shown on the Main Menu: best team (by record), best batter (OPS),
/// best pitcher (ERA). No minimum PA/IP — but a player must have actually batted/pitched to appear.
private struct LeaderboardCard: View {
    @Query private var teams: [Team]
    @Query private var players: [Player]
    @Query private var games: [Game]

    var body: some View {
        // Compute each leader tuple ONCE per render. Reading the computed properties inline (the
        // previous shape) called them twice each — once for the nil-check, once inside the *Text
        // helpers — and each call redoes the full map+filter+sort over every team/player, which
        // in turn decodes each stat line's JSON blob. Halving those calls halves the work.
        let team = topTeam
        let batter = topBatter
        let pitcher = topPitcher

        return VStack(alignment: .leading, spacing: 14) {
            Text("Leaderboard")
                .font(Theme.cardTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            if team == nil && batter == nil && pitcher == nil {
                Text("Play some games and your league leaders show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                entry(icon: "trophy.fill",     label: "Top Team",    value: text(team: team))
                entry(icon: "figure.baseball", label: "Top Batter",  value: text(batter: batter))
                entry(icon: "baseball.fill",   label: "Top Pitcher", value: text(pitcher: pitcher))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private func entry(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    // MARK: Leaders

    /// The team with the best record, or nil if nobody has finished a game yet.
    ///
    /// Spelled out as a loop rather than a map/filter/sorted/first chain. The element here is a
    /// tuple containing another tuple, and passing that through four generic calls in one expression
    /// is something the Swift type-checker is unusually slow at — it was the single most expensive
    /// expression in this file. Annotating each step makes them independent, cheap problems.
    private var topTeam: (team: Team, record: (wins: Int, losses: Int))? {
        var standings: [(team: Team, record: (wins: Int, losses: Int))] = []
        for team in teams {
            let record: (wins: Int, losses: Int) = team.record(from: games)
            guard record.wins + record.losses > 0 else { continue }   // must have a decided game
            standings.append((team: team, record: record))
        }
        standings.sort { lhs, rhs in
            lhs.record.wins != rhs.record.wins
                ? lhs.record.wins > rhs.record.wins
                : lhs.record.losses < rhs.record.losses
        }
        return standings.first
    }

    private var topBatter: (player: Player, stats: BattingStats)? {
        players
            .map { (player: $0, stats: $0.careerBatting) }
            .filter { $0.stats.atBats > 0 }
            .sorted { $0.stats.onBasePlusSlugging > $1.stats.onBasePlusSlugging }
            .first
    }

    private var topPitcher: (player: Player, stats: PitchingStats)? {
        players
            .map { (player: $0, stats: $0.careerPitching) }
            .filter { $0.stats.outsRecorded > 0 }
            .sorted { $0.stats.earnedRunAverage < $1.stats.earnedRunAverage }
            .first
    }

    // Formatters take the pre-computed tuple (rather than reading `topTeam` etc. again) so `body`
    // stays the single site that touches the expensive leader computations.

    private func text(team: (team: Team, record: (wins: Int, losses: Int))?) -> String {
        guard let t = team else { return "—" }
        let w = t.record.wins, l = t.record.losses
        return "\(t.team.name) · \(w) Win\(w == 1 ? "" : "s")  \(l) Loss\(l == 1 ? "" : "es")"
    }

    private func text(batter: (player: Player, stats: BattingStats)?) -> String {
        guard let b = batter else { return "—" }
        return "\(b.player.name) · \(StatFormat.rate(b.stats.battingAverage)) AVG  \(StatFormat.rate(b.stats.onBasePlusSlugging)) OPS"
    }

    private func text(pitcher: (player: Player, stats: PitchingStats)?) -> String {
        guard let p = pitcher else { return "—" }
        return "\(p.player.name) · \(StatFormat.ratio(p.stats.earnedRunAverage)) ERA"
    }
}

#Preview {
    MainMenuView(router: Router())
        .modelContainer(for: Player.self, inMemory: true)
}
