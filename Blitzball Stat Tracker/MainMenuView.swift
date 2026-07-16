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
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        header

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
                        NavigationLink(destination: TournamentBracketView()) {
                            MenuCard(title: "Tournament Bracket",
                                     subtitle: "Run a tournament bracket",
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
                    // Fill at least the screen height so the block centers vertically (still
                    // scrolls if it ever overflows on a small device).
                    .frame(minHeight: geo.size.height)
                }
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
            Text("Blitzball Stat Tracker")
                .font(Theme.screenTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Main Menu")
                .font(Theme.screenSubtitle)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

#Preview {
    MainMenuView(router: Router())
        .modelContainer(for: Player.self, inMemory: true)
}
