//
//  RootView.swift
//  Blitzball Stat Tracker
//
//  The very top of the view tree. It shows the splash first, then reveals the app.
//

import SwiftUI
import SwiftData

struct RootView: View {
    // Owned here (not in MainMenuView) so "Back to Main Menu" can ask us to replay the splash.
    @State private var router = Router()
    // Tracks whether the splash is still covering the app. Starts true (splash visible).
    @State private var showSplash = true

    var body: some View {
        // ZStack layers views front-to-back. The menu sits underneath the whole time; the splash
        // lies on top and, when removed, fades away to reveal the app beneath.
        ZStack {
            MainMenuView(router: router)

            if showSplash {
                SplashView()
                    .transition(.opacity)   // fades in/out
                    .zIndex(1)
            }
        }
        // The whole app runs dark so system chrome (nav titles, back buttons, pickers, menus,
        // status bar) is light and reads on the blue gradient. Our explicit gradient/cards/text
        // are unaffected.
        .preferredColorScheme(.dark)
        // Initial launch splash.
        .task { await playSplash() }
        // Replay the splash whenever a deep screen asks (e.g. "Back to Main Menu" after a game).
        .onChange(of: router.splashRequestID) {
            withAnimation(.easeInOut(duration: 0.3)) { showSplash = true }
            Task { await playSplash() }
        }
    }

    /// Hold the splash for ~2s, then fade it out.
    private func playSplash() async {
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Player.self, inMemory: true)
}
