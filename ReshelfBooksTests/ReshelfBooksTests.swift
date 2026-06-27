//
//  ReshelfBooksTests.swift
//  ReshelfBooksTests
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Testing
import CoreData
import Foundation
import UIKit
@testable import ReshelfBooks

// MARK: - Core Data test helpers

/// A fresh in-memory Core Data stack per test, so model objects have a context and
/// tests don't share state.
private func makeTestContext() -> NSManagedObjectContext {
    PersistenceController(inMemory: true).viewContext
}

@discardableResult
private func makeBook(
    in context: NSManagedObjectContext,
    isbn: String,
    title: String,
    author: String,
    yearPublished: String,
    coverImageURL: String? = nil,
    shelf: Shelf? = nil
) -> Book {
    let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context) as! Book
    book.dateAdded = Date()
    book.isbn = isbn
    book.title = title
    book.author = author
    book.yearPublished = yearPublished
    book.coverImageURL = coverImageURL
    book.shelf = shelf
    return book
}

@discardableResult
private func makeShelf(
    in context: NSManagedObjectContext,
    name: String,
    sortOrder: Int64 = 0,
    isLendingShelf: Bool = false
) -> Shelf {
    let shelf = NSEntityDescription.insertNewObject(forEntityName: "Shelf", into: context) as! Shelf
    shelf.dateCreated = Date()
    shelf.name = name
    shelf.sortOrder = sortOrder
    shelf.isLendingShelf = isLendingShelf
    return shelf
}

// MARK: - Book Model Tests

@Suite("Book Model Tests")
struct BookModelTests {

    @Test("Book initialization sets all properties correctly")
    func bookInitialization() {
        let context = makeTestContext()
        let book = makeBook(
            in: context,
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813",
            coverImageURL: "https://example.com/cover.jpg"
        )

        #expect(book.isbn == "9780141439518")
        #expect(book.title == "Pride and Prejudice")
        #expect(book.author == "Jane Austen")
        #expect(book.yearPublished == "1813")
        #expect(book.coverImageURL == "https://example.com/cover.jpg")
        #expect(book.shelf == nil)
        #expect(book.previousShelf == nil)
        #expect(book.coverImageData == nil)
    }

    @Test("Book isLent returns false when not on lending shelf")
    func bookIsLentFalseWhenNotOnLendingShelf() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        // No shelf
        #expect(book.isLent == false)

        // Regular shelf
        let regularShelf = makeShelf(in: context, name: "Fiction", isLendingShelf: false)
        book.shelf = regularShelf
        #expect(book.isLent == false)
    }

    @Test("Book isLent returns true when on lending shelf")
    func bookIsLentTrueWhenOnLendingShelf() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let lendingShelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)
        book.shelf = lendingShelf
        #expect(book.isLent == true)
    }

    @Test("Book lend() moves book to lending shelf and stores previous shelf")
    func bookLendStoresPreviousShelf() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let originalShelf = makeShelf(in: context, name: "Fiction", isLendingShelf: false)
        let lendingShelf = makeShelf(in: context, name: "Lent", sortOrder: 1, isLendingShelf: true)

        book.shelf = originalShelf
        book.lend(to: lendingShelf)

        #expect(book.shelf === lendingShelf)
        #expect(book.previousShelf === originalShelf)
        #expect(book.isLent == true)
    }

    @Test("Book lend() works when book has no shelf")
    func bookLendFromUnshelved() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let lendingShelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)

        #expect(book.shelf == nil)
        book.lend(to: lendingShelf)

        #expect(book.shelf === lendingShelf)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == true)
    }

    @Test("Book lend() ignores non-lending shelves")
    func bookLendIgnoresNonLendingShelf() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let originalShelf = makeShelf(in: context, name: "Fiction", isLendingShelf: false)
        let notLendingShelf = makeShelf(in: context, name: "Not Lending", sortOrder: 1, isLendingShelf: false)

        book.shelf = originalShelf
        book.lend(to: notLendingShelf)

        // Should not have changed
        #expect(book.shelf === originalShelf)
        #expect(book.previousShelf == nil)
    }

    @Test("Book returnBook() restores previous shelf")
    func bookReturnRestoresPreviousShelf() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let originalShelf = makeShelf(in: context, name: "Fiction", isLendingShelf: false)
        let lendingShelf = makeShelf(in: context, name: "Lent", sortOrder: 1, isLendingShelf: true)

        book.shelf = originalShelf
        book.lend(to: lendingShelf)
        book.returnBook()

        #expect(book.shelf === originalShelf)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == false)
    }

    @Test("Book returnBook() sets shelf to nil when no previous shelf")
    func bookReturnToUnshelved() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")

        let lendingShelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)

        book.lend(to: lendingShelf)
        book.returnBook()

        #expect(book.shelf == nil)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == false)
    }

    @Test("Book lend(to:borrower:) records the borrower and lend date")
    func bookLendRecordsBorrower() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")
        let lendingShelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)

        book.lend(to: lendingShelf, borrower: "Alice")

        #expect(book.borrower == "Alice")
        #expect(book.borrowerName == "Alice")
        #expect(book.dateLent != nil)
    }

    @Test("Book lend(to:borrower:) treats a blank borrower as anonymous")
    func bookLendBlankBorrowerIsAnonymous() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")
        let lendingShelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)

        book.lend(to: lendingShelf, borrower: "   ")

        #expect(book.borrower == nil)
        #expect(book.borrowerName == nil)
        // Still lent, with a date — just no named borrower.
        #expect(book.isLent == true)
        #expect(book.dateLent != nil)
    }

    @Test("Book returnBook() clears the borrower and lend date")
    func bookReturnClearsBorrower() {
        let context = makeTestContext()
        let book = makeBook(in: context, isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen", yearPublished: "1813")
        let originalShelf = makeShelf(in: context, name: "Fiction", isLendingShelf: false)
        let lendingShelf = makeShelf(in: context, name: "Lent", sortOrder: 1, isLendingShelf: true)

        book.shelf = originalShelf
        book.lend(to: lendingShelf, borrower: "Bob")
        book.returnBook()

        #expect(book.shelf === originalShelf)
        #expect(book.borrower == nil)
        #expect(book.dateLent == nil)
    }
}

// MARK: - Shelf Model Tests

@Suite("Shelf Model Tests")
struct ShelfModelTests {

    @Test("Shelf initialization sets all properties correctly")
    func shelfInitialization() {
        let context = makeTestContext()
        let shelf = makeShelf(in: context, name: "Fiction", sortOrder: 5, isLendingShelf: false)

        #expect(shelf.name == "Fiction")
        #expect(shelf.sortOrder == 5)
        #expect(shelf.isLendingShelf == false)
        #expect((shelf.books ?? []).isEmpty)
    }

    @Test("Lending shelf initialization")
    func lendingShelfInitialization() {
        let context = makeTestContext()
        let shelf = makeShelf(in: context, name: "Lent", isLendingShelf: true)

        #expect(shelf.isLendingShelf == true)
    }

    @Test("Array extension regularShelves filters out lending shelf")
    func regularShelvesFiltering() {
        let context = makeTestContext()
        let shelves = [
            makeShelf(in: context, name: "Fiction", sortOrder: 0, isLendingShelf: false),
            makeShelf(in: context, name: "Non-Fiction", sortOrder: 1, isLendingShelf: false),
            makeShelf(in: context, name: "Lent", sortOrder: 2, isLendingShelf: true)
        ]

        let regularShelves = shelves.regularShelves

        #expect(regularShelves.count == 2)
        #expect(regularShelves.allSatisfy { !$0.isLendingShelf })
    }

    @Test("Array extension lendingShelf returns lending shelf")
    func lendingShelfFinding() {
        let context = makeTestContext()
        let shelves = [
            makeShelf(in: context, name: "Fiction", sortOrder: 0, isLendingShelf: false),
            makeShelf(in: context, name: "Lent", sortOrder: 1, isLendingShelf: true)
        ]

        let lendingShelf = shelves.lendingShelf

        #expect(lendingShelf != nil)
        #expect(lendingShelf?.name == "Lent")
        #expect(lendingShelf?.isLendingShelf == true)
    }

    @Test("Array extension lendingShelf returns nil when no lending shelf")
    func lendingShelfNilWhenMissing() {
        let context = makeTestContext()
        let shelves = [
            makeShelf(in: context, name: "Fiction", sortOrder: 0, isLendingShelf: false),
            makeShelf(in: context, name: "Non-Fiction", sortOrder: 1, isLendingShelf: false)
        ]

        let lendingShelf = shelves.lendingShelf

        #expect(lendingShelf == nil)
    }

    @Test("Array extension works with empty array")
    func emptyArrayExtensions() {
        let shelves: [Shelf] = []

        #expect(shelves.regularShelves.isEmpty)
        #expect(shelves.lendingShelf == nil)
    }

    @Test("Lending shelf dedup picks the earliest-created shelf")
    func lendingShelfPicksEarliest() {
        let context = makeTestContext()
        let older = makeShelf(in: context, name: "Lent", isLendingShelf: true)
        older.dateCreated = Date(timeIntervalSince1970: 1_000)
        let newer = makeShelf(in: context, name: "Lent", isLendingShelf: true)
        newer.dateCreated = Date(timeIntervalSince1970: 2_000)

        let shelves = [newer, older]
        #expect(shelves.lendingShelf === older)
    }
}

// MARK: - ISBN Validation Tests

@Suite("ISBN Validation Tests")
struct ISBNValidationTests {

    @Test("Valid ISBN-13 without dashes")
    func validISBN13NoDashes() {
        #expect(ISBNValidator.isValid("9780141439518"))
    }

    @Test("Valid ISBN-13 with dashes")
    func validISBN13WithDashes() {
        #expect(ISBNValidator.isValid("978-0-14-143951-8"))
    }

    @Test("Valid ISBN-10 without dashes")
    func validISBN10NoDashes() {
        #expect(ISBNValidator.isValid("0141439513"))
    }

    @Test("Valid ISBN-10 with dashes")
    func validISBN10WithDashes() {
        #expect(ISBNValidator.isValid("0-14-143951-3"))
    }

    @Test("Valid ISBN-10 with X check digit (any case)")
    func validISBN10WithXCheckDigit() {
        #expect(ISBNValidator.isValid("080442957X"))
        #expect(ISBNValidator.isValid("080442957x"))
    }

    @Test("Invalid ISBN - too short")
    func invalidISBNTooShort() {
        #expect(ISBNValidator.isValid("12345") == false)
    }

    @Test("Invalid ISBN - too long")
    func invalidISBNTooLong() {
        #expect(ISBNValidator.isValid("12345678901234") == false)
    }

    @Test("Invalid ISBN - contains letters")
    func invalidISBNWithLetters() {
        #expect(ISBNValidator.isValid("978014143951X") == false)
    }

    @Test("Empty ISBN is invalid")
    func emptyISBN() {
        #expect(ISBNValidator.isValid("") == false)
    }

    @Test("ISBN-13 with wrong check digit is invalid")
    func invalidISBN13Checksum() {
        // Correct check digit is 8; 9 fails the checksum.
        #expect(ISBNValidator.isValid("9780141439519") == false)
    }

    @Test("ISBN-10 with wrong check digit is invalid")
    func invalidISBN10Checksum() {
        // Correct check digit is 3; 2 fails the checksum.
        #expect(ISBNValidator.isValid("0141439512") == false)
    }

    @Test("X outside the final position is invalid")
    func invalidISBN10MisplacedX() {
        #expect(ISBNValidator.isValid("01X1439513") == false)
    }

    @Test("normalize strips separators and uppercases")
    func normalizeStripsSeparators() {
        #expect(ISBNValidator.normalize("978-0-14 143951-8") == "9780141439518")
        #expect(ISBNValidator.normalize("080442957x") == "080442957X")
    }

    @Test("canonicalize converts ISBN-10 to ISBN-13")
    func canonicalizeConvertsISBN10() {
        #expect(ISBNValidator.canonicalize("0141439513") == "9780141439518")
        // X check digit: dropped and recomputed for the 978 form.
        #expect(ISBNValidator.canonicalize("080442957X") == "9780804429573")
        #expect(ISBNValidator.canonicalize("0-14-143951-3") == "9780141439518")
    }

    @Test("canonicalize leaves ISBN-13 and invalid input unchanged (just normalized)")
    func canonicalizePassthrough() {
        #expect(ISBNValidator.canonicalize("978-0-14-143951-8") == "9780141439518")
        #expect(ISBNValidator.canonicalize("12345") == "12345")
        // Invalid ISBN-10 (bad checksum) is not converted.
        #expect(ISBNValidator.canonicalize("0141439512") == "0141439512")
    }
}

// MARK: - Leave-Share Restore Tests

@Suite("Leave Share Restore Tests")
struct LeaveRestoreTests {

    @Test("restoreContributedBooks rebuilds books, shelves and lending state")
    func restoreRebuildsLibrary() {
        let persistence = PersistenceController(inMemory: true)
        persistence.pendingLeaveSnapshot = [
            ContributedBookSnapshot(
                isbn: "9780141439518", title: "Pride and Prejudice", author: "Jane Austen",
                yearPublished: "1813", coverImageURL: nil, coverImageData: nil,
                dateAdded: Date(timeIntervalSince1970: 1_000),
                shelfName: "Fiction", isLent: false, previousShelfName: nil
            ),
            ContributedBookSnapshot(
                isbn: "9780804429573", title: "Borrowed Tome", author: "A. Lender",
                yearPublished: "2000", coverImageURL: nil, coverImageData: nil,
                dateAdded: Date(timeIntervalSince1970: 2_000),
                shelfName: nil, isLent: true, previousShelfName: "Fiction"
            ),
            ContributedBookSnapshot(
                isbn: "9780000000002", title: "Loose Leaf", author: "N. Shelf",
                yearPublished: "2010", coverImageURL: nil, coverImageData: nil,
                dateAdded: nil, shelfName: nil, isLent: false, previousShelfName: nil
            )
        ]

        persistence.restoreContributedBooks()

        let books = (try? persistence.viewContext.fetch(Book.fetchRequestAll())) ?? []
        #expect(books.count == 3)
        #expect(persistence.pendingLeaveSnapshot == nil)

        let shelved = books.first { $0.isbn == "9780141439518" }
        #expect(shelved?.shelf?.name == "Fiction")
        #expect(shelved?.isLent == false)

        let lent = books.first { $0.isbn == "9780804429573" }
        #expect(lent?.isLent == true)
        #expect(lent?.previousShelf?.name == "Fiction")
        // The shelf is matched by name, not duplicated.
        #expect(lent?.previousShelf === shelved?.shelf)

        let unshelved = books.first { $0.isbn == "9780000000002" }
        #expect(unshelved?.shelf == nil)
    }

    @Test("restoreContributedBooks is a no-op without a snapshot")
    func restoreWithoutSnapshotDoesNothing() {
        let persistence = PersistenceController(inMemory: true)
        persistence.restoreContributedBooks()
        let books = (try? persistence.viewContext.fetch(Book.fetchRequestAll())) ?? []
        #expect(books.isEmpty)
    }
}

// MARK: - Shelf Reorder (sortOrder) Tests

@Suite("Shelf Reorder Tests")
struct ShelfReorderTests {

    @Test("New books append to the end of their shelf's order")
    func newBooksAppend() {
        let p = PersistenceController(inMemory: true)
        let shelf = p.makeShelf(name: "Fiction")
        let dune = p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: shelf)
        let hobbit = p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: shelf)
        #expect(dune.sortOrder == 0)
        #expect(hobbit.sortOrder == 1)
    }

    @Test("nextSortOrder is one past the current maximum")
    func nextSortOrderIsMaxPlusOne() {
        let p = PersistenceController(inMemory: true)
        let shelf = p.makeShelf(name: "Fiction")
        #expect(p.nextSortOrder(in: shelf) == 0)   // empty
        p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: shelf)
        p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: shelf)
        #expect(p.nextSortOrder(in: shelf) == 2)
    }

    @Test("Moving a book to another shelf appends it there")
    func movingAppendsToNewShelf() {
        let p = PersistenceController(inMemory: true)
        let fiction = p.makeShelf(name: "Fiction")
        let scifi = p.makeShelf(name: "Sci-Fi")
        p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: scifi)
        p.makeBook(isbn: "9780451524935", title: "1984", author: "Orwell", yearPublished: "1949", coverImageURL: nil, shelf: scifi)
        let mover = p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: fiction)
        #expect(mover.sortOrder == 0)

        // Simulate the shelf picker's move-to-end behaviour.
        mover.shelf = scifi
        mover.sortOrder = p.nextSortOrder(in: scifi, excluding: mover)
        #expect(mover.sortOrder == 2)   // appended after the two existing Sci-Fi books
    }

    @Test("applyOrder writes dense indices matching the array order")
    func applyOrderAssignsDenseIndices() {
        let p = PersistenceController(inMemory: true)
        let shelf = p.makeShelf(name: "Fiction")
        let dune = p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: shelf)
        let hobbit = p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: shelf)
        let nineteen = p.makeBook(isbn: "9780451524935", title: "1984", author: "Orwell", yearPublished: "1949", coverImageURL: nil, shelf: shelf)

        let changed = ShelfReorder.applyOrder([nineteen, hobbit, dune])   // reversed
        #expect(changed)
        #expect(nineteen.sortOrder == 0)
        #expect(hobbit.sortOrder == 1)
        #expect(dune.sortOrder == 2)
    }

    @Test("applyOrder returns false when the order is unchanged")
    func applyOrderNoChangeReturnsFalse() {
        let p = PersistenceController(inMemory: true)
        let shelf = p.makeShelf(name: "Fiction")
        let dune = p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: shelf)
        let hobbit = p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: shelf)
        #expect(ShelfReorder.applyOrder([dune, hobbit]) == false)   // already 0, 1
    }

    @Test("applyOrder skips a book deleted mid-drag without crashing")
    func applyOrderSkipsDeletedBook() {
        let p = PersistenceController(inMemory: true)
        let shelf = p.makeShelf(name: "Fiction")
        let dune = p.makeBook(isbn: "9780441013593", title: "Dune", author: "Herbert", yearPublished: "1965", coverImageURL: nil, shelf: shelf)
        let hobbit = p.makeBook(isbn: "9780547928227", title: "The Hobbit", author: "Tolkien", yearPublished: "1937", coverImageURL: nil, shelf: shelf)

        p.delete(hobbit)   // simulate a concurrent CloudKit deletion mid-drag

        // hobbit (now deleted) is skipped; the surviving book is still reindexed.
        let changed = ShelfReorder.applyOrder([hobbit, dune])
        #expect(changed)
        #expect(dune.sortOrder == 1)
    }
}

// MARK: - Cover Image Tests

@Suite("Cover Image Tests")
struct CoverImageTests {

    /// Builds a scale-1 JPEG of the given pixel size for deterministic assertions.
    private func makeJPEG(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    @Test("normalizedData returns nil for non-image bytes")
    func rejectsNonImageData() {
        let junk = Data("<html>404 Not Found</html>".utf8)
        #expect(CoverImage.normalizedData(from: junk) == nil)
    }

    @Test("normalizedData re-encodes a valid image")
    func acceptsValidImage() {
        let raw = makeJPEG(width: 400, height: 600)
        let normalized = CoverImage.normalizedData(from: raw)
        #expect(normalized != nil)
        #expect(UIImage(data: normalized!) != nil)
    }

    @Test("Oversized images are capped to the max dimension")
    func capsOversizedImages() {
        let raw = makeJPEG(width: 2000, height: 3000)
        let normalized = CoverImage.normalizedData(from: raw)
        let decoded = UIImage(data: normalized!)!
        // Allow 1px slack for rounding during the resize.
        #expect(max(decoded.size.width, decoded.size.height) <= CoverImage.maxDimension + 1)
    }

    @Test("Images already within bounds keep their size")
    func leavesSmallImagesAlone() {
        let raw = makeJPEG(width: 300, height: 450)
        let decoded = UIImage(data: CoverImage.normalizedData(from: raw)!)!
        #expect(decoded.size.width == 300)
        #expect(decoded.size.height == 450)
    }
}

// MARK: - Edition Description Dedup Tests

@Suite("Edition Description Dedup Tests")
struct EditionDescriptionDedupTests {

    private func metadata(title: String, author: String, year: String) -> BookMetadata {
        BookMetadata(isbn: "9780141439518", title: title, author: author, yearPublished: year, coverImageURL: nil)
    }

    @Test("Identical results from two sources collapse into one description")
    func identicalResultsCollapse() {
        let results = [
            (source: "Open Library", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "1813")),
            (source: "Google Books", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "1813"))
        ]
        let deduped = ISBNLookupService.dedupedDescriptions(results)
        #expect(deduped.count == 1)
        #expect(deduped.first?.sources == ["Open Library", "Google Books"])
    }

    @Test("Dedup compares case- and whitespace-insensitively, keeping the first metadata")
    func dedupNormalizes() {
        let results = [
            (source: "Open Library", metadata: metadata(title: "Pride and Prejudice ", author: "JANE AUSTEN", year: "1813")),
            (source: "Crossref", metadata: metadata(title: "pride and prejudice", author: "Jane Austen", year: "1813"))
        ]
        let deduped = ISBNLookupService.dedupedDescriptions(results)
        #expect(deduped.count == 1)
        // The first (highest-priority) source supplies the canonical metadata.
        #expect(deduped.first?.metadata.author == "JANE AUSTEN")
        #expect(deduped.first?.sources == ["Open Library", "Crossref"])
    }

    @Test("Different years stay separate, in priority order")
    func differentYearsSeparate() {
        let results = [
            (source: "Open Library", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "1813")),
            (source: "Google Books", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "2003"))
        ]
        let deduped = ISBNLookupService.dedupedDescriptions(results)
        #expect(deduped.count == 2)
        #expect(deduped[0].metadata.yearPublished == "1813")
        #expect(deduped[1].metadata.yearPublished == "2003")
    }

    @Test("The same source name isn't listed twice on one description")
    func duplicateSourceNotRepeated() {
        // Both Open Library endpoints report under the same public name.
        let results = [
            (source: "Open Library", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "1813")),
            (source: "Open Library", metadata: metadata(title: "Pride and Prejudice", author: "Jane Austen", year: "1813"))
        ]
        let deduped = ISBNLookupService.dedupedDescriptions(results)
        #expect(deduped.count == 1)
        #expect(deduped.first?.sources == ["Open Library"])
    }

    @Test("Empty input produces no descriptions")
    func emptyInput() {
        #expect(ISBNLookupService.dedupedDescriptions([]).isEmpty)
    }
}

// MARK: - BookMetadata Tests

@Suite("BookMetadata Tests")
struct BookMetadataTests {

    @Test("BookMetadata initialization")
    func bookMetadataInit() {
        let metadata = BookMetadata(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813",
            coverImageURL: "https://example.com/cover.jpg"
        )

        #expect(metadata.isbn == "9780141439518")
        #expect(metadata.title == "Pride and Prejudice")
        #expect(metadata.author == "Jane Austen")
        #expect(metadata.yearPublished == "1813")
        #expect(metadata.coverImageURL == "https://example.com/cover.jpg")
    }

    @Test("BookMetadata with nil cover URL")
    func bookMetadataNilCover() {
        let metadata = BookMetadata(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813",
            coverImageURL: nil
        )

        #expect(metadata.coverImageURL == nil)
    }
}

// MARK: - ISBNLookupError Tests

@Suite("ISBNLookupError Tests")
struct ISBNLookupErrorTests {

    @Test("Error descriptions are user-friendly")
    func errorDescriptions() {
        #expect(ISBNLookupError.notFound.errorDescription == "Book not found")
        #expect(ISBNLookupError.invalidResponse.errorDescription == "Invalid response from server")
        #expect(ISBNLookupError.decodingError.errorDescription == "Could not parse book data")
    }

    @Test("Network error includes underlying error")
    func networkErrorDescription() {
        let underlyingError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No internet"])
        let error = ISBNLookupError.networkError(underlyingError)

        #expect(error.errorDescription?.contains("Network error") == true)
    }
}
