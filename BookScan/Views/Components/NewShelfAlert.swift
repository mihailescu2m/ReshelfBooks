//
//  NewShelfAlert.swift
//  BookScan
//
//  Created by Marian Mihailescu on 5/6/2026.
//

import SwiftUI
import SwiftData

/// Reusable "New Shelf" name-entry alert.
///
/// Centralizes the create-shelf flow that several screens share: prompt for a
/// name, trim/validate it, insert the shelf, then hand the new shelf back so the
/// caller can do something with it (assign a book, select it, etc.).
private struct NewShelfAlert: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    @Binding var isPresented: Bool
    /// Number of existing shelves, used to assign the new shelf's sort order.
    let existingShelfCount: Int
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

        let shelf = Shelf(name: trimmed, sortOrder: existingShelfCount)
        modelContext.insert(shelf)
        onCreate(shelf)
        name = ""
    }
}

extension View {
    /// Presents a "New Shelf" alert. `onCreate` receives the newly inserted shelf.
    func newShelfAlert(
        isPresented: Binding<Bool>,
        existingShelfCount: Int,
        onCreate: @escaping (Shelf) -> Void = { _ in }
    ) -> some View {
        modifier(NewShelfAlert(isPresented: isPresented, existingShelfCount: existingShelfCount, onCreate: onCreate))
    }
}
