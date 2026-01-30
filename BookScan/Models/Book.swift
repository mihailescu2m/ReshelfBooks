//
//  Book.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import SwiftData

@Model
final class Book {
    // CloudKit requires all attributes to have default values or be optional
    var isbn: String = ""
    var title: String = ""
    var author: String = ""
    var yearPublished: String = ""
    var coverImageURL: String?
    var coverImageData: Data?
    var dateAdded: Date = Date()

    @Relationship(inverse: \Shelf.books)
    var shelf: Shelf?

    // Stores the original shelf before lending
    // CloudKit requires all relationships to have an inverse
    @Relationship(inverse: \Shelf.previousBooks)
    var previousShelf: Shelf?

    // Computed property to check if book is currently lent
    var isLent: Bool {
        shelf?.isLendingShelf ?? false
    }

    // MARK: - Lending Actions

    /// Lends the book by moving it to the lending shelf.
    /// Stores the current shelf in `previousShelf` so it can be returned later.
    /// - Parameter lendingShelf: The special lending shelf to move the book to
    func lend(to lendingShelf: Shelf) {
        guard lendingShelf.isLendingShelf else { return }

        // Store the current shelf before moving to lent
        previousShelf = shelf

        // Move to lending shelf
        shelf = lendingShelf
    }

    /// Returns the book to its original shelf (or unshelved if no previous shelf).
    /// Clears the `previousShelf` reference after returning.
    func returnBook() {
        shelf = previousShelf
        previousShelf = nil
    }

    init(isbn: String, title: String, author: String, yearPublished: String, coverImageURL: String? = nil, coverImageData: Data? = nil, shelf: Shelf? = nil) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.yearPublished = yearPublished
        self.coverImageURL = coverImageURL
        self.coverImageData = coverImageData
        self.dateAdded = Date()
        self.shelf = shelf
    }
}
