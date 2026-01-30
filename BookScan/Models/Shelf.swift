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
    var name: String
    var dateCreated: Date
    var sortOrder: Int
    var isLendingShelf: Bool

    @Relationship
    var books: [Book] = []

    init(name: String, sortOrder: Int = 0, isLendingShelf: Bool = false) {
        self.name = name
        self.dateCreated = Date()
        self.sortOrder = sortOrder
        self.isLendingShelf = isLendingShelf
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
