//
//  BookDetailView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var book: Book
    let shelves: [Shelf]

    var body: some View {
        NavigationStack {
            BookDetailContent(book: book, shelves: shelves) {
                dismiss()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, Shelf.self, configurations: config)

    let shelf = Shelf(name: "Fiction", sortOrder: 0)
    container.mainContext.insert(shelf)

    let book = Book(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        shelf: shelf
    )
    container.mainContext.insert(book)

    return BookDetailView(book: book, shelves: [shelf])
        .modelContainer(container)
}
