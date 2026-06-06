//
//  DismissWhenDeleted.swift
//  BookScan
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  Dismisses the enclosing view when a managed object it displays is deleted
//  (e.g. a family member deletes a book you currently have open). The caller must
//  still guard its content with `if !object.isDeleted` so the deleted object's
//  faulted relationships are never rendered before the dismiss lands.
//

import SwiftUI
import CoreData

private struct DismissWhenDeleted: ViewModifier {
    let object: NSManagedObject
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: object.isDeleted) { _, isDeleted in
            if isDeleted { dismiss() }
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
