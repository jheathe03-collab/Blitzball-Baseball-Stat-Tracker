//
//  Blitzball_Stat_TrackerApp.swift
//  Blitzball Stat Tracker
//
//  Created by James Heatherly on 7/9/26.
//

import SwiftUI
import SwiftData

@main
struct Blitzball_Stat_TrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Player.self,
            Team.self,
            Game.self,
            GameStatLine.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
