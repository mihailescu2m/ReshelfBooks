//
//  ISBNLookupService.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation

struct BookMetadata {
    let isbn: String
    let title: String
    let author: String
    let yearPublished: String
    let coverImageURL: String?
}

enum ISBNLookupError: Error, LocalizedError {
    case networkError(Error)
    case notFound
    case invalidResponse
    case decodingError

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .notFound:
            return "Book not found"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Could not parse book data"
        }
    }
}

actor ISBNLookupService {
    static let shared = ISBNLookupService()

    private init() {}

    /// Main lookup function - tries Open Library first, then Google Books as fallback
    func lookupBook(isbn: String) async throws -> BookMetadata {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")

        // Try Open Library first
        if let result = try? await lookupFromOpenLibrary(isbn: cleanISBN) {
            return result
        }

        // Fallback to Google Books
        if let result = try? await lookupFromGoogleBooks(isbn: cleanISBN) {
            return result
        }

        throw ISBNLookupError.notFound
    }

    // MARK: - Open Library API

    private func lookupFromOpenLibrary(isbn: String) async throws -> BookMetadata {
        let urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"

        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bookData = json["ISBN:\(isbn)"] as? [String: Any] else {
            throw ISBNLookupError.notFound
        }

        let title = bookData["title"] as? String ?? "Unknown Title"

        var author = "Unknown Author"
        if let authors = bookData["authors"] as? [[String: Any]],
           let firstAuthor = authors.first,
           let authorName = firstAuthor["name"] as? String {
            author = authorName
        }

        var yearPublished = "Unknown"
        if let publishDate = bookData["publish_date"] as? String {
            yearPublished = extractYear(from: publishDate)
        }

        var coverImageURL: String? = nil
        if let cover = bookData["cover"] as? [String: Any] {
            coverImageURL = cover["large"] as? String ?? cover["medium"] as? String ?? cover["small"] as? String
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: coverImageURL
        )
    }

    // MARK: - Google Books API

    private func lookupFromGoogleBooks(isbn: String) async throws -> BookMetadata {
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"

        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let firstItem = items.first,
              let volumeInfo = firstItem["volumeInfo"] as? [String: Any] else {
            throw ISBNLookupError.notFound
        }

        let title = volumeInfo["title"] as? String ?? "Unknown Title"

        var author = "Unknown Author"
        if let authors = volumeInfo["authors"] as? [String],
           let firstAuthor = authors.first {
            author = firstAuthor
        }

        var yearPublished = "Unknown"
        if let publishedDate = volumeInfo["publishedDate"] as? String {
            yearPublished = extractYear(from: publishedDate)
        }

        var coverImageURL: String? = nil
        if let imageLinks = volumeInfo["imageLinks"] as? [String: Any] {
            // Prefer larger images, convert http to https
            let imageURL = imageLinks["large"] as? String
                ?? imageLinks["medium"] as? String
                ?? imageLinks["small"] as? String
                ?? imageLinks["thumbnail"] as? String
                ?? imageLinks["smallThumbnail"] as? String
            coverImageURL = imageURL?.replacingOccurrences(of: "http://", with: "https://")
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: coverImageURL
        )
    }

    // MARK: - Helpers

    private func extractYear(from dateString: String) -> String {
        let yearPattern = #"\b(19|20)\d{2}\b"#
        if let range = dateString.range(of: yearPattern, options: .regularExpression) {
            return String(dateString[range])
        }
        return dateString
    }

    func downloadCoverImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        return data
    }
}
