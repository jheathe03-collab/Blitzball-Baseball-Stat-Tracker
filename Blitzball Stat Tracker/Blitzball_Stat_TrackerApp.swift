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
            Tournament.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: modelConfiguration)
        } catch {
            // NEVER silently wipe the store on failure — that's how a schema mismatch turns into
            // 'every player, team, game, and season vanished with no warning'. Instead:
            //   1. Copy the three store files (.sqlite / -wal / -shm) to a timestamped folder
            //      under the app's Documents directory, so nothing is truly lost.
            //   2. Crash with a descriptive message so the failure is loud and the recovery path
            //      (the backup folder) is visible.
            //
            // NOTE: this catch also implicitly protects future schema changes. Any renamed or
            // retyped @Model field STILL needs a proper VersionedSchema + MigrationPlan (Xcode
            // won't infer a rename), but if migration ever fails again the user's data is safe
            // in the backup folder instead of gone.
            let backup = Self.backupStoreFiles(at: modelConfiguration.url)
            fatalError("""
                SwiftData could not open the on-disk store: \(error)

                Your data has been backed up to:
                  \(backup?.path ?? "<backup could not be written — see console>")

                To recover: resolve the schema mismatch (usually by adding a VersionedSchema \
                migration stage for the changed @Model field), delete the app to clear the broken \
                store, then reinstall — SwiftData will start fresh and you can restore the backup \
                files into Application Support if needed.
                """)
        }
    }()

    /// Copy the SwiftData store's three files to a timestamped folder in Documents. Returns the
    /// backup folder URL, or nil if Documents wasn't reachable. Best-effort: individual file
    /// copies are `try?` so partial success still returns a folder.
    private static func backupStoreFiles(at storeURL: URL) -> URL? {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        // Colons aren't legal in file names on some filesystems, so replace them in the ISO stamp.
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = docs.appendingPathComponent("blitzball-store-backup-\(stamp)")
        guard (try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = backupDir.appendingPathComponent(src.lastPathComponent)
            try? fm.copyItem(at: src, to: dst)
        }
        return backupDir
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
