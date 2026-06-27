//
//  Book.swift
//  ReshelfBooks
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
    /// Who the book is currently lent to (nil/empty = an anonymous lend). Set in
    /// `lend(to:borrower:)`, cleared in `returnBook()`.
    @NSManaged public var borrower: String?
    /// When the book was lent. Set in `lend(to:borrower:)`, cleared in `returnBook()`.
    @NSManaged public var dateLent: Date?
    /// Manual position within a regular shelf, for drag-to-reorder. Default 0 → the shelf
    /// falls back to alphabetical order (the sort tiebreaks on title). New/moved books are
    /// assigned the next value so they append to the end of their shelf.
    @NSManaged public var sortOrder: Int64

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

    /// The borrower's name if one was recorded and non-blank, else nil. Use this for
    /// display so an empty-string borrower reads the same as an anonymous lend.
    public var borrowerName: String? {
        guard let name = borrower?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    // MARK: - Lending Actions

    /// Lends the book by moving it to the lending shelf, remembering its current
    /// shelf so it can be returned later. Records an optional borrower name (blank
    /// is treated as anonymous) and the lend date. No-op if `lendingShelf` isn't a
    /// lending shelf.
    func lend(to lendingShelf: Shelf, borrower: String? = nil) {
        guard lendingShelf.isLendingShelf else { return }
        previousShelf = shelf
        shelf = lendingShelf
        let trimmed = borrower?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.borrower = (trimmed?.isEmpty == false) ? trimmed : nil
        dateLent = Date()
    }

    /// Returns the book to its original shelf (or unshelved if none) and clears the
    /// remembered previous shelf and lending details.
    func returnBook() {
        shelf = previousShelf
        previousShelf = nil
        borrower = nil
        dateLent = nil
    }
}

extension Book: Identifiable {
    // Use the always-present, unique objectID rather than a stored optional UUID
    // (legacy records can have a nil id, which collides in ForEach / sheet(item:)).
    public var id: NSManagedObjectID { objectID }
}
