//
//  ReorderShelvesView.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 28/6/2026.
//
//  A dedicated sheet for reordering the regular shelves with native drag-to-reorder
//  (List + .onMove). Persists each shelf's `sortOrder` to match the new order — the
//  same field the Library already sorts by, so there is no schema/migration work.
//  The lending shelf is excluded (it stays pinned at the top in its own section).
//

import SwiftUI

struct ReorderShelvesView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @Environment(\.dismiss) private var dismiss

    /// Working copy in display order; reordered live and persisted on each move.
    @State private var orderedShelves: [Shelf]

    init(shelves: [Shelf]) {
        // Seeded in the Library's current display order (already sorted by sortOrder).
        _orderedShelves = State(initialValue: shelves)
    }

    var body: some View {
        SheetHeaderContainer {
            SheetHeaderBar(title: "Reorder Shelves", trailing: {
                CircularIconButton(systemName: "checkmark", prominent: true, accessibilityLabel: "Done") {
                    dismiss()
                }
            })
        } content: {
            Group {
                if orderedShelves.count < 2 {
                    ContentUnavailableView {
                        Label("Nothing to Reorder", systemImage: "arrow.up.arrow.down")
                    } description: {
                        Text("Add a second shelf to change their order.")
                    }
                } else {
                    List {
                        ForEach(orderedShelves) { shelf in
                            HStack(spacing: 12) {
                                Image(systemName: "books.vertical.fill")
                                    .foregroundColor(.accentColor)
                                Text(shelf.name)
                                    .lineLimit(1)
                            }
                        }
                        .onMove(perform: move)
                    }
                    // Always-on edit mode shows the drag handles immediately, so the whole
                    // sheet is "reorder mode" without a separate Edit button.
                    .environment(\.editMode, .constant(.active))
                    .scrollContentBackground(.hidden)   // blend with the sheet background
                }
            }
            .scrollsBehindHeader()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedShelves.move(fromOffsets: source, toOffset: destination)
        var changed = false
        for (index, shelf) in orderedShelves.enumerated()
        where !shelf.isDeleted && shelf.managedObjectContext != nil && shelf.sortOrder != Int64(index) {
            shelf.sortOrder = Int64(index)
            changed = true
        }
        if changed { persistence.save() }
    }
}
