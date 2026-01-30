//
//  BookScanTests.swift
//  BookScanTests
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Testing
import SwiftData
import Foundation
@testable import BookScan

// MARK: - Book Model Tests

@Suite("Book Model Tests")
struct BookModelTests {

    @Test("Book initialization sets all properties correctly")
    func bookInitialization() {
        let book = Book(
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
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        // No shelf
        #expect(book.isLent == false)

        // Regular shelf
        let regularShelf = Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false)
        book.shelf = regularShelf
        #expect(book.isLent == false)
    }

    @Test("Book isLent returns true when on lending shelf")
    func bookIsLentTrueWhenOnLendingShelf() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let lendingShelf = Shelf(name: "Lent", sortOrder: 0, isLendingShelf: true)
        book.shelf = lendingShelf
        #expect(book.isLent == true)
    }

    @Test("Book lend() moves book to lending shelf and stores previous shelf")
    func bookLendStoresPreviousShelf() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let originalShelf = Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false)
        let lendingShelf = Shelf(name: "Lent", sortOrder: 1, isLendingShelf: true)

        book.shelf = originalShelf
        book.lend(to: lendingShelf)

        #expect(book.shelf === lendingShelf)
        #expect(book.previousShelf === originalShelf)
        #expect(book.isLent == true)
    }

    @Test("Book lend() works when book has no shelf")
    func bookLendFromUnshelved() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let lendingShelf = Shelf(name: "Lent", sortOrder: 0, isLendingShelf: true)

        #expect(book.shelf == nil)
        book.lend(to: lendingShelf)

        #expect(book.shelf === lendingShelf)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == true)
    }

    @Test("Book lend() ignores non-lending shelves")
    func bookLendIgnoresNonLendingShelf() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let originalShelf = Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false)
        let notLendingShelf = Shelf(name: "Not Lending", sortOrder: 1, isLendingShelf: false)

        book.shelf = originalShelf
        book.lend(to: notLendingShelf)

        // Should not have changed
        #expect(book.shelf === originalShelf)
        #expect(book.previousShelf == nil)
    }

    @Test("Book returnBook() restores previous shelf")
    func bookReturnRestoresPreviousShelf() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let originalShelf = Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false)
        let lendingShelf = Shelf(name: "Lent", sortOrder: 1, isLendingShelf: true)

        book.shelf = originalShelf
        book.lend(to: lendingShelf)
        book.returnBook()

        #expect(book.shelf === originalShelf)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == false)
    }

    @Test("Book returnBook() sets shelf to nil when no previous shelf")
    func bookReturnToUnshelved() {
        let book = Book(
            isbn: "9780141439518",
            title: "Pride and Prejudice",
            author: "Jane Austen",
            yearPublished: "1813"
        )

        let lendingShelf = Shelf(name: "Lent", sortOrder: 0, isLendingShelf: true)

        book.lend(to: lendingShelf)
        book.returnBook()

        #expect(book.shelf == nil)
        #expect(book.previousShelf == nil)
        #expect(book.isLent == false)
    }
}

// MARK: - Shelf Model Tests

@Suite("Shelf Model Tests")
struct ShelfModelTests {

    @Test("Shelf initialization sets all properties correctly")
    func shelfInitialization() {
        let shelf = Shelf(name: "Fiction", sortOrder: 5, isLendingShelf: false)

        #expect(shelf.name == "Fiction")
        #expect(shelf.sortOrder == 5)
        #expect(shelf.isLendingShelf == false)
        #expect(shelf.books.isEmpty)
    }

    @Test("Lending shelf initialization")
    func lendingShelfInitialization() {
        let shelf = Shelf(name: "Lent", sortOrder: 0, isLendingShelf: true)

        #expect(shelf.isLendingShelf == true)
    }

    @Test("Array extension regularShelves filters out lending shelf")
    func regularShelvesFiltering() {
        let shelves = [
            Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false),
            Shelf(name: "Non-Fiction", sortOrder: 1, isLendingShelf: false),
            Shelf(name: "Lent", sortOrder: 2, isLendingShelf: true)
        ]

        let regularShelves = shelves.regularShelves

        #expect(regularShelves.count == 2)
        #expect(regularShelves.allSatisfy { !$0.isLendingShelf })
    }

    @Test("Array extension lendingShelf returns lending shelf")
    func lendingShelfFinding() {
        let shelves = [
            Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false),
            Shelf(name: "Lent", sortOrder: 1, isLendingShelf: true)
        ]

        let lendingShelf = shelves.lendingShelf

        #expect(lendingShelf != nil)
        #expect(lendingShelf?.name == "Lent")
        #expect(lendingShelf?.isLendingShelf == true)
    }

    @Test("Array extension lendingShelf returns nil when no lending shelf")
    func lendingShelfNilWhenMissing() {
        let shelves = [
            Shelf(name: "Fiction", sortOrder: 0, isLendingShelf: false),
            Shelf(name: "Non-Fiction", sortOrder: 1, isLendingShelf: false)
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
}

// MARK: - ISBN Validation Tests

@Suite("ISBN Validation Tests")
struct ISBNValidationTests {

    private func isValidISBN(_ isbn: String) -> Bool {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return (cleanISBN.count == 10 || cleanISBN.count == 13) &&
               cleanISBN.allSatisfy { $0.isNumber }
    }

    @Test("Valid ISBN-13 without dashes")
    func validISBN13NoDashes() {
        #expect(isValidISBN("9780141439518") == true)
    }

    @Test("Valid ISBN-13 with dashes")
    func validISBN13WithDashes() {
        #expect(isValidISBN("978-0-14-143951-8") == true)
    }

    @Test("Valid ISBN-10 without dashes")
    func validISBN10NoDashes() {
        #expect(isValidISBN("0141439513") == true)
    }

    @Test("Valid ISBN-10 with dashes")
    func validISBN10WithDashes() {
        #expect(isValidISBN("0-14-143951-3") == true)
    }

    @Test("Invalid ISBN - too short")
    func invalidISBNTooShort() {
        #expect(isValidISBN("12345") == false)
    }

    @Test("Invalid ISBN - too long")
    func invalidISBNTooLong() {
        #expect(isValidISBN("12345678901234") == false)
    }

    @Test("Invalid ISBN - contains letters")
    func invalidISBNWithLetters() {
        #expect(isValidISBN("978014143951X") == false)
    }

    @Test("Empty ISBN is invalid")
    func emptyISBN() {
        #expect(isValidISBN("") == false)
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
