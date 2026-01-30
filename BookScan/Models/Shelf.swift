//
//  Shelf.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import SwiftData

@Model
final class Shelf {
    // CloudKit requires all attributes to have default values or be optional
    var name: String = ""
    var dateCreated: Date = Date()
    var sortOrder: Int = 0
    var isLendingShelf: Bool = false

    // CloudKit requires all relationships to be optional (use optional array)
    @Relationship(deleteRule: .nullify)
    var books: [Book]? = []

    // Inverse relationship for Book.previousShelf (required by CloudKit)
    @Relationship(deleteRule: .nullify)
    var previousBooks: [Book]? = []

    init(name: String, sortOrder: Int = 0, isLendingShelf: Bool = false) {
        self.name = name
        self.dateCreated = Date()
        self.sortOrder = sortOrder
        self.isLendingShelf = isLendingShelf
        self.books = []
        self.previousBooks = []
    }
}

// MARK: - Array Extension for Shelf Filtering

extension Array where Element == Shelf {
    /// Returns only regular shelves (excluding the lending shelf)
    var regularShelves: [Shelf] {
        filter { !$0.isLendingShelf }
    }

    /// Returns the special lending shelf, if it exists
    var lendingShelf: Shelf? {
        first { $0.isLendingShelf }
    }
}
