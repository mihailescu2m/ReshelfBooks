//
//  DismissWhenDeleted.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  Dismisses the enclosing view when a managed object it displays is deleted
//  (e.g. a family member deletes a book you currently have open). The caller must
//  still guard its content with `if !object.isGone` so the deleted object's
//  faulted relationships are never rendered before the dismiss lands.
//

import SwiftUI
import CoreData

extension NSManagedObject {
    /// True when the object no longer exists: marked for deletion locally, or already
    /// removed entirely. The second check matters for two cases `isDeleted` misses:
    /// a *remote* (CloudKit) deletion that has finished merging leaves the object
    /// unregistered with `isDeleted == false` and a nil context, and a failed save's
    /// rollback removes an unsaved insert the same way.
    var isGone: Bool {
        isDeleted || managedObjectContext == nil
    }
}

private struct DismissWhenDeleted: ViewModifier {
    let object: NSManagedObject
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: object.isGone) { _, isGone in
            if isGone { dismiss() }
        }
    }
}

extension View {
    /// Dismisses this view when `object` becomes deleted. Pair with an
    /// `if !object.isDeleted` guard around the content that touches the object.
    func dismissWhenDeleted(_ object: NSManagedObject) -> some View {
        modifier(DismissWhenDeleted(object: object))
    }
}
