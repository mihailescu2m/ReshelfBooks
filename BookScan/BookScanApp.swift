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
                    ensureSingleLendingShelf()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Ensures exactly one "Lent" shelf exists.
    ///
    /// CloudKit-backed stores can't use `#Unique` constraints, so two devices (or a
    /// first launch racing the initial sync) can each create a lending shelf. When
    /// duplicates appear we merge them into the earliest-created shelf rather than
    /// leaving books split across copies.
    private func ensureSingleLendingShelf() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Shelf>(predicate: #Predicate { $0.isLendingShelf == true })

        do {
            let lendingShelves = try context.fetch(descriptor)

            // None yet — create the canonical lending shelf.
            guard let canonical = lendingShelves.min(by: { $0.dateCreated < $1.dateCreated }) else {
                let lendingShelf = Shelf(name: "Lent", sortOrder: Int.max, isLendingShelf: true)
                context.insert(lendingShelf)
                try context.save()
                logger.info("Created lending shelf")
                return
            }

            // Exactly one — nothing to do.
            guard lendingShelves.count > 1 else { return }

            // Merge duplicates: move their books onto the canonical shelf, then delete.
            let duplicates = lendingShelves.filter { $0 !== canonical }
            for duplicate in duplicates {
                for book in duplicate.books ?? [] {
                    book.shelf = canonical
                }
                for book in duplicate.previousBooks ?? [] {
                    book.previousShelf = canonical
                }
                context.delete(duplicate)
            }
            try context.save()
            logger.warning("Merged \(duplicates.count) duplicate lending shelf(es) into one")
        } catch {
            logger.error("Error ensuring lending shelf: \(error.localizedDescription)")
        }
    }
}
