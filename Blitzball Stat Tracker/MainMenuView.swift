//
//  MainMenuView.swift
//  Blitzball Stat Tracker
//
//  The hub shown after the splash. Owns the navigation stack; each row pushes a feature.
//

import SwiftUI
import SwiftData

struct MainMenuView: View {
    // Owns the navigation path so deep screens can pop back to the menu (shared via environment).
    @State private var router = Router()

    var body: some View {
        // This NavigationStack is the ONE stack for the whole menu area. Every feature we
        // push (Players, Teams, ...) rides on top of it — which is why those screens don't
        // declare their own stacks.
        NavigationStack {
            List {
                // A little branding at the top. `.listRowBackground(.clear)` hides the usual
                // row background so the logo floats.
                Section {
                    HStack {
                        Spacer()
                        Image("BlitzballLogoHQ")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 64)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // The four features. Each NavigationLink pairs a destination screen with the
                // row the user taps.
                Section {
                    NavigationLink(destination: ExhibitionView()) {
                        MenuRow(title: "Exhibition",
                                subtitle: "Track stats for a single game",
                                systemImage: "baseball.fill",
                                tint: .orange)
                    }
                    NavigationLink(destination: TournamentBracketView()) {
                        MenuRow(title: "Tournament Bracket",
                                subtitle: "Run a bracket across a season",
                                systemImage: "trophy.fill",
                                tint: .yellow)
                    }
                    NavigationLink(destination: PlayersView()) {
                        MenuRow(title: "Players",
                                subtitle: "Add players and track their stats",
                                systemImage: "person.fill",
                                tint: .blue)
                    }
                    NavigationLink(destination: TeamsView()) {
                        MenuRow(title: "Teams",
                                subtitle: "Build teams from your players",
                                systemImage: "person.3.fill",
                                tint: .green)
                    }
                }
            }
            .navigationTitle("Main Menu")
        }
        // Changing this id rebuilds the stack → pops back to the menu when a deep screen calls
        // router.popToRoot(). Shared via environment so those screens can trigger it.
        .id(router.resetID)
        .environment(router)
    }
}

/// One menu row: a colored icon tile, a title, and a short description.
private struct MenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MainMenuView()
        .modelContainer(for: Player.self, inMemory: true)
}
