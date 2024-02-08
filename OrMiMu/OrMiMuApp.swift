//
//  OrMiMuApp.swift
//  OrMiMu
//
//  Created by Manuel Galindo on 7/02/24.
//

import SwiftUI
import SwiftData

@main
struct OrMiMuApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MusicPath.self,
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
