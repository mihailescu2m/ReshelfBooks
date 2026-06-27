//
//  AppDelegate.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  Minimal app delegate whose only job is to accept CloudKit share invitations
//  when a family member taps a share link. No UI, no other responsibilities.
//

import UIKit
import CloudKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    /// Called when the user accepts a share invitation (taps the link in Messages/Mail).
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PersistenceController.shared.acceptShare(cloudKitShareMetadata)
    }
}
