//
//  SharingPresenter.swift
//  BookScan
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  Presents UICloudSharingController imperatively from the top-most view controller.
//  UICloudSharingController is designed to be presented directly as a modal; embedding
//  it inside a SwiftUI .sheet is unreliable, so we present it the UIKit way and keep a
//  self-retained coordinator alive for the controller's lifetime.
//
//  One control handles all three cases: owner inviting, owner managing, participant
//  viewing/leaving (the share is pre-created via PersistenceController.prepareShare).
//

import UIKit
import CloudKit

enum SharingPresenter {
    /// Retains the coordinator while the controller is on screen.
    private static var activeCoordinator: Coordinator?

    static func present(share: CKShare, container: CKContainer, persistence: PersistenceController) {
        guard let presenter = topViewController() else { return }

        let controller = UICloudSharingController(share: share, container: container)
        let coordinator = Coordinator(persistence: persistence)
        activeCoordinator = coordinator
        controller.delegate = coordinator
        controller.presentationController?.delegate = coordinator
        // Everyone who joins gets full read/write; no public link, no read-only.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]

        presenter.present(controller, animated: true)
    }

    /// Walks the key window's presentation chain to find the controller to present from.
    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private let persistence: PersistenceController

        init(persistence: PersistenceController) {
            self.persistence = persistence
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "BookScan Library"
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            persistence.refreshSharedState()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            persistence.refreshSharedState()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            persistence.refreshSharedState()
        }

        // Called when the sheet is swiped/closed without inviting anyone.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            persistence.removeUnusedShareIfNeeded()
            persistence.refreshSharedState()
            SharingPresenter.activeCoordinator = nil
        }
    }
}
