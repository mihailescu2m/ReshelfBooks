//
//  Library.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 6/6/2026.
//

import Foundation
import CoreData

/// The hidden root object that owns every shelf and book.
///
/// There is exactly one active `Library` per device-library. It exists purely as a
/// CloudKit *sharing anchor*: sharing this single object moves the entire object
/// graph (shelves + books) into a shared CloudKit zone, and any new object that is
/// connected to it automatically becomes part of the share. The UI never displays
/// the `Library` itself.
@objc(Library)
public final class Library: NSManagedObject {
    @NSManaged public var createdAt: Date?
    @NSManaged public var shelves: Set<Shelf>?
    @NSManaged public var books: Set<Book>?

    static func fetchRequestAll() -> NSFetchRequest<Library> {
        NSFetchRequest<Library>(entityName: "Library")
    }
}
