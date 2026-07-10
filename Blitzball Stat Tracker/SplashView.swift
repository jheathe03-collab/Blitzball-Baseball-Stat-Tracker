//
//  SplashView.swift
//  Blitzball Stat Tracker
//
//  The animated launch splash: brand gradient + logo that springs in, then the app takes over.
//

import SwiftUI

struct SplashView: View {
    // A single piece of view-local state that drives the whole animation. It starts false
    // (logo small + invisible) and we flip it to true when the view appears, which animates
    // everything to its final look.
    @State private var animateIn = false

    var body: some View {
        ZStack {
            // The brand gradient background, top-to-bottom. `.ignoresSafeArea()` lets it run
            // edge to edge, under the notch and home indicator.
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.84, blue: 0.30), // golden yellow (top)
                    Color(red: 0.97, green: 0.55, blue: 0.11)  // orange (bottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // The logo. `.resizable()` + `.scaledToFit()` let it shrink to our frame while
                // keeping its proportions.
                Image("BlitzballLogoHQ")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    // These two modifiers are what "animate": when `animateIn` flips to true,
                    // the logo grows from 60% to full size and fades from invisible to solid.
                    .scaleEffect(animateIn ? 1.0 : 0.6)
                    .opacity(animateIn ? 1.0 : 0.0)

                Text("BlitzBall Stat Tracker")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .opacity(animateIn ? 1.0 : 0.0)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        // `.onAppear` runs the moment the view shows up. Wrapping the state change in
        // `withAnimation` tells SwiftUI: don't snap to the new values — glide there.
        // `.spring` gives that lively little bounce as the logo settles.
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                animateIn = true
            }
        }
    }
}

#Preview {
    SplashView()
}
