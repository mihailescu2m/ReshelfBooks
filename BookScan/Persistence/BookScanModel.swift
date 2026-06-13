//
//  BookScanModel.swift
//  BookScan
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  The Core Data model, defined programmatically so there is no .xcdatamodeld
//  bundle to keep in sync. Every attribute is optional or has a default and every
//  relationship is optional with an inverse — the requirements for CloudKit mirroring.
//

import CoreData

extension PersistenceController {

    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // MARK: Entities

        let library = NSEntityDescription()
        library.name = "Library"
        library.managedObjectClassName = "Library"

        let shelf = NSEntityDescription()
        shelf.name = "Shelf"
        shelf.managedObjectClassName = "Shelf"

        let book = NSEntityDescription()
        book.name = "Book"
        book.managedObjectClassName = "Book"

        // MARK: Attributes

        library.properties = [
            attribute("createdAt", .dateAttributeType, optional: true)
        ]

        shelf.properties = [
            attribute("name", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("dateCreated", .dateAttributeType, optional: true),
            attribute("sortOrder", .integer64AttributeType, optional: false, defaultValue: 0),
            attribute("isLendingShelf", .booleanAttributeType, optional: false, defaultValue: false)
        ]

        book.properties = [
            attribute("isbn", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("title", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("author", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("yearPublished", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("coverImageURL", .stringAttributeType, optional: true),
            attribute("coverImageData", .binaryDataAttributeType, optional: true, allowsExternalStorage: true),
            attribute("dateAdded", .dateAttributeType, optional: true),
            // Join-time contribution tag (see Book.contributedBy). NOTE: new fields
            // must be deployed to the Production CloudKit schema before release.
            attribute("contributedBy", .stringAttributeType, optional: true),
            // Lending: who the book is currently lent to, and when. Both set in
            // lend(to:borrower:) and cleared in returnBook(). NOTE: same Production
            // CloudKit schema deploy requirement as contributedBy above.
            attribute("borrower", .stringAttributeType, optional: true),
            attribute("dateLent", .dateAttributeType, optional: true)
        ]

        // MARK: Relationships (created in pairs, then linked as inverses)

        // Library 1—* Shelf
        let libraryShelves = relationship("shelves", destination: shelf, toMany: true)
        let shelfLibrary = relationship("library", destination: library, toMany: false)
        link(libraryShelves, shelfLibrary)

        // Library 1—* Book
        let libraryBooks = relationship("books", destination: book, toMany: true)
        let bookLibrary = relationship("library", destination: library, toMany: false)
        link(libraryBooks, bookLibrary)

        // Shelf 1—* Book (current shelf)
        let shelfBooks = relationship("books", destination: book, toMany: true)
        let bookShelf = relationship("shelf", destination: shelf, toMany: false)
        link(shelfBooks, bookShelf)

        // Shelf 1—* Book (previous shelf, remembered while lent)
        let shelfPreviousBooks = relationship("previousBooks", destination: book, toMany: true)
        let bookPreviousShelf = relationship("previousShelf", destination: shelf, toMany: false)
        link(shelfPreviousBooks, bookPreviousShelf)

        library.properties += [libraryShelves, libraryBooks]
        shelf.properties += [shelfLibrary, shelfBooks, shelfPreviousBooks]
        book.properties += [bookLibrary, bookShelf, bookPreviousShelf]

        model.entities = [library, shelf, book]
        return model
    }

    // MARK: - Builders

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil,
        allowsExternalStorage: Bool = false
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        if let defaultValue { attr.defaultValue = defaultValue }
        attr.allowsExternalBinaryDataStorage = allowsExternalStorage
        return attr
    }

    private static func relationship(
        _ name: String,
        destination: NSEntityDescription,
        toMany: Bool
    ) -> NSRelationshipDescription {
        let rel = NSRelationshipDescription()
        rel.name = name
        rel.destinationEntity = destination
        rel.isOptional = true                  // CloudKit requires optional relationships
        rel.deleteRule = .nullifyDeleteRule
        rel.minCount = 0
        rel.maxCount = toMany ? 0 : 1          // 0 == to-many (unlimited)
        rel.isOrdered = false
        return rel
    }

    private static func link(_ a: NSRelationshipDescription, _ b: NSRelationshipDescription) {
        a.inverseRelationship = b
        b.inverseRelationship = a
    }
}
