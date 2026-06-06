//
//  BookScanApp.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

@main
struct BookScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(persistence)
                .task {
                    // Owner-only structural cleanup (dedup duplicate libraries / lending
                    // shelves) and refresh the shared-state used by the Library title.
                    persistence.bootstrap()
                }
        }
    }
}
