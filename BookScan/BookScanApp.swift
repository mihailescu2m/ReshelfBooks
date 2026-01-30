//
//  BookScanApp.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "App")

@main
struct BookScanApp: App {
    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Book.self,
            Shelf.self,
        ])

        // CloudKit sync enabled for multi-device support
        // Requires iCloud capability in Xcode: Signing & Capabilities → iCloud → CloudKit
        // Container: iCloud.memeka.BookScan
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.memeka.BookScan")
        )

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.info("ModelContainer created successfully")
        } catch {
            // Log the error for debugging
            logger.critical("Failed to create ModelContainer: \(error.localizedDescription)")

            // Create an in-memory container as fallback so the app can at least launch
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                logger.warning("ModelContainer created in-memory only (data will not persist)")
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    createLendingShelfIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Creates the special "Lent" shelf if it doesn't already exist
    private func createLendingShelfIfNeeded() {
        let context = sharedModelContainer.mainContext

        // Check if lending shelf already exists
        let descriptor = FetchDescriptor<Shelf>(predicate: #Predicate { $0.isLendingShelf == true })

        do {
            let existingLendingShelves = try context.fetch(descriptor)
            if existingLendingShelves.isEmpty {
                // Create the lending shelf
                let lendingShelf = Shelf(name: "Lent", sortOrder: Int.max, isLendingShelf: true)
                context.insert(lendingShelf)
                try context.save()
                logger.info("Created lending shelf")
            }
        } catch {
            logger.error("Error checking/creating lending shelf: \(error.localizedDescription)")
        }
    }
}
