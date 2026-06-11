//
//  Book.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import CoreData

@objc(Book)
public final class Book: NSManagedObject {
    // CloudKit requires every attribute to be optional or have a default value.
    @NSManaged public var isbn: String
    @NSManaged public var title: String
    @NSManaged public var author: String
    @NSManaged public var yearPublished: String
    @NSManaged public var coverImageURL: String?
    @NSManaged public var coverImageData: Data?
    @NSManaged public var dateAdded: Date?
    /// ID of the participant who moved this book into a shared library at join time;
    /// nil for books created directly. Lets that user take these books back when
    /// leaving the share. Never shown in the UI.
    @NSManaged public var contributedBy: String?

    // CloudKit requires every relationship to be optional and have an inverse.
    @NSManaged public var library: Library?
    @NSManaged public var shelf: Shelf?
    /// The shelf the book lived on before being lent, so it can be returned later.
    @NSManaged public var previousShelf: Shelf?

    static func fetchRequestAll() -> NSFetchRequest<Book> {
        NSFetchRequest<Book>(entityName: "Book")
    }

    // MARK: - Lending state

    /// Whether the book is currently on the lending shelf.
    public var isLent: Bool {
        shelf?.isLendingShelf ?? false
    }

    // MARK: - Lending Actions

    /// Lends the book by moving it to the lending shelf, remembering its current
    /// shelf so it can be returned later. No-op if `lendingShelf` isn't a lending shelf.
    func lend(to lendingShelf: Shelf) {
        guard lendingShelf.isLendingShelf else { return }
        previousShelf = shelf
        shelf = lendingShelf
    }

    /// Returns the book to its original shelf (or unshelved if none) and clears the
    /// remembered previous shelf.
    func returnBook() {
        shelf = previousShelf
        previousShelf = nil
    }
}

extension Book: Identifiable {
    // Use the always-present, unique objectID rather than a stored optional UUID
    // (legacy records can have a nil id, which collides in ForEach / sheet(item:)).
    public var id: NSManagedObjectID { objectID }
}
