//
//  BookDetailView.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var book: Book
    let shelves: [Shelf]

    var body: some View {
        // No NavigationStack — this sheet is presented from within LibraryTabView's
        // NavigationStack; nesting a second one causes a fatal nav-bar conflict on iPad.
        SheetHeaderContainer {
            SheetHeaderBar(title: "Book Details", trailing: {
                CircularIconButton(systemName: "checkmark", prominent: true, accessibilityLabel: "Done") { dismiss() }
            })
        } content: {
            BookDetailContent(book: book, shelves: shelves) { dismiss() }
        }
    }
}

#Preview {
    let persistence = PersistenceController.preview
    let shelf = persistence.makeShelf(name: "Fiction")
    let book = persistence.makeBook(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        coverImageURL: nil,
        shelf: shelf
    )
    persistence.save()

    return BookDetailView(book: book, shelves: [shelf])
        .environment(\.managedObjectContext, persistence.viewContext)
        .environmentObject(persistence)
}
