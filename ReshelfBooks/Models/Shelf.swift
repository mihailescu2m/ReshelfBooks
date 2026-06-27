//
//  Shelf.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import CoreData

@objc(Shelf)
public final class Shelf: NSManagedObject {
    // CloudKit requires every attribute to be optional or have a default value.
    @NSManaged public var name: String
    @NSManaged public var dateCreated: Date?
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isLendingShelf: Bool

    // CloudKit requires every relationship to be optional and have an inverse.
    @NSManaged public var library: Library?
    @NSManaged public var books: Set<Book>?
    @NSManaged public var previousBooks: Set<Book>?

    static func fetchRequestAll() -> NSFetchRequest<Shelf> {
        NSFetchRequest<Shelf>(entityName: "Shelf")
    }

    /// Convenience: the books on this shelf as a plain array (the relationship is a Set).
    var bookList: [Book] {
        Array(books ?? [])
    }
}

extension Shelf: Identifiable {
    // Use the always-present, unique objectID rather than a stored optional UUID
    // (legacy records can have a nil id, which collides in ForEach / sheet(item:)).
    public var id: NSManagedObjectID { objectID }
}

// MARK: - Array Extension for Shelf Filtering

extension Sequence where Element == Shelf {
    /// Returns only regular shelves (excluding the lending shelf), as an array.
    var regularShelves: [Shelf] {
        filter { !$0.isLendingShelf }
    }

    /// Returns the special lending shelf, if it exists.
    /// If duplicates exist (e.g. a CloudKit sync race before dedup runs), the
    /// earliest-created shelf is returned so the choice is stable everywhere.
    var lendingShelf: Shelf? {
        filter { $0.isLendingShelf }
            .min { ($0.dateCreated ?? .distantFuture) < ($1.dateCreated ?? .distantFuture) }
    }
}
