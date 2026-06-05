//
//  BookScanTests.swift
//  BookScanTests
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Testing
import SwiftData
import Foundation
import UIKit
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
        #expect((shelf.books ?? []).isEmpty)
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
