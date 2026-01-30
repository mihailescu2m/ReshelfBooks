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
    @State private var showingDatabaseError = false
    @State private var databaseErrorMessage = ""

    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Book.self,
            Shelf.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error for debugging
            logger.critical("Failed to create ModelContainer: \(error.localizedDescription)")

            // Create an in-memory container as fallback so the app can at least launch
            // User will be notified about the error
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                // We'll show the error alert after the app launches
            } catch {
                // This should never happen with in-memory storage, but if it does, we have no choice
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
                .alert("Database Error", isPresented: $showingDatabaseError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(databaseErrorMessage)
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
