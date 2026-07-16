//
//  Blitzball_Stat_TrackerApp.swift
//  Blitzball Stat Tracker
//
//  Created by James Heatherly on 7/9/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct Blitzball_Stat_TrackerApp: App {
    init() {
        // Make every nav bar transparent so the blue gradient shows behind the title. In dark mode
        // (set on RootView) the title/back render light automatically.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Player.self,
            Team.self,
            Game.self,
            GameStatLine.self,
            Season.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: modelConfiguration)
        } catch {
            // LAST-RESORT dev safety net: if the on-disk store can't load (an incompatible schema
            // change), reset it and retry rather than hard-crashing on launch. ⚠️ Wipes local data.
            let storeURL = modelConfiguration.url
            let fileManager = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                try? fileManager.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            do {
                return try ModelContainer(for: schema, configurations: modelConfiguration)
            } catch {
                fatalError("Could not create ModelContainer after resetting the store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
