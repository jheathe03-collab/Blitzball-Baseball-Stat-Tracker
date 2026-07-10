//
//  RootView.swift
//  Blitzball Stat Tracker
//
//  The very top of the view tree. It shows the splash first, then reveals the app.
//

import SwiftUI
import SwiftData

struct RootView: View {
    // Tracks whether the splash is still covering the app. Starts true (splash visible).
    @State private var showSplash = true

    var body: some View {
        // ZStack layers views front-to-back. ContentView sits underneath the whole time;
        // the splash lies on top and, when removed, fades away to reveal the app beneath.
        ZStack {
            MainMenuView()

            if showSplash {
                SplashView()
                    // `.transition(.opacity)` describes HOW the splash leaves: by fading out.
                    .transition(.opacity)
                    // Sits above ContentView.
                    .zIndex(1)
            }
        }
        // `.task` runs once when RootView appears. It's the modern way to do timed/async work.
        .task {
            // Wait ~2 seconds while the splash animates and the user takes it in.
            try? await Task.sleep(for: .seconds(2))
            // Flip the flag inside `withAnimation` so the splash fades (0.5s) instead of vanishing.
            withAnimation(.easeInOut(duration: 0.5)) {
                showSplash = false
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Player.self, inMemory: true)
}
