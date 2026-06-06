//
//  NewShelfAlert.swift
//  BookScan
//
//  Created by Marian Mihailescu on 5/6/2026.
//

import SwiftUI

/// Reusable "New Shelf" name-entry alert.
///
/// Centralizes the create-shelf flow that several screens share: prompt for a
/// name, trim/validate it, create the shelf through the persistence layer (which
/// attaches it to the active library and the correct CloudKit store), then hand
/// the new shelf back so the caller can do something with it.
private struct NewShelfAlert: ViewModifier {
    @EnvironmentObject private var persistence: PersistenceController

    @Binding var isPresented: Bool
    let onCreate: (Shelf) -> Void

    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Shelf", isPresented: $isPresented) {
            TextField("Shelf name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") { create() }
        } message: {
            Text("Enter a name for the new shelf")
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let shelf = persistence.makeShelf(name: trimmed)
        onCreate(shelf)
        persistence.save()
        name = ""
    }
}

extension View {
    /// Presents a "New Shelf" alert. `onCreate` receives the newly created shelf.
    func newShelfAlert(
        isPresented: Binding<Bool>,
        onCreate: @escaping (Shelf) -> Void = { _ in }
    ) -> some View {
        modifier(NewShelfAlert(isPresented: isPresented, onCreate: onCreate))
    }
}
