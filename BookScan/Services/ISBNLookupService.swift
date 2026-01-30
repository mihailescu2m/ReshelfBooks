//
//  ISBNLookupService.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import os.log

// Simple logger for the app
private let logger = Logger(subsystem: "com.bookscan", category: "ISBNLookup")

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

    // Minimum image size to be considered valid (filters out placeholder images)
    private let minimumImageSize = 1000

    private init() {}

    // MARK: - Public API

    /// Main lookup function - tries Open Library first, then Google Books as fallback
    func lookupBook(isbn: String) async throws -> BookMetadata {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")

        // Try Open Library first
        if let result = try? await lookupFromOpenLibrary(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        // Fallback to Google Books
        if let result = try? await lookupFromGoogleBooks(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        throw ISBNLookupError.notFound
    }

    /// Searches for book cover images from multiple sources and returns up to maxResults URLs
    func searchCoverImages(isbn: String, title: String, author: String, maxResults: Int = 6) async -> [String] {
        var coverURLs: [String] = []

        // 1. Try Open Library Covers API by ISBN
        if let openLibraryCover = await getOpenLibraryCoverURL(isbn: isbn) {
            coverURLs.append(openLibraryCover)
        }

        // 2. Try Google Books by ISBN
        if let googleCover = await searchGoogleBooks(query: "isbn:\(isbn)", maxResults: 1).first {
            if !coverURLs.contains(googleCover) {
                coverURLs.append(googleCover)
            }
        }

        // 3. Try Google Books by title + author
        if coverURLs.count < maxResults {
            let titleAuthorCovers = await searchGoogleBooks(query: "\(title) \(author)", maxResults: 2)
            for cover in titleAuthorCovers where !coverURLs.contains(cover) {
                coverURLs.append(cover)
                if coverURLs.count >= maxResults { break }
            }
        }

        // 4. Try Google Books by title only (different editions)
        if coverURLs.count < maxResults {
            let titleCovers = await searchGoogleBooks(query: title, maxResults: maxResults - coverURLs.count + 2)
            for cover in titleCovers where !coverURLs.contains(cover) {
                coverURLs.append(cover)
                if coverURLs.count >= maxResults { break }
            }
        }

        // 5. Try Open Library search by title/author
        if coverURLs.count < maxResults {
            let openLibraryCovers = await searchOpenLibrary(title: title, author: author, maxResults: maxResults - coverURLs.count + 2)
            for cover in openLibraryCovers where !coverURLs.contains(cover) {
                coverURLs.append(cover)
                if coverURLs.count >= maxResults { break }
            }
        }

        // 6. Try Bookcover API by ISBN
        if coverURLs.count < maxResults {
            if let bookcoverURL = await getBookcoverAPIURL(isbn: isbn) {
                if !coverURLs.contains(bookcoverURL) {
                    coverURLs.append(bookcoverURL)
                }
            }
        }

        // 7. Try Better World Books by ISBN
        if coverURLs.count < maxResults {
            if let bwbURL = await getBetterWorldBooksURL(isbn: isbn) {
                if !coverURLs.contains(bwbURL) {
                    coverURLs.append(bwbURL)
                }
            }
        }

        return Array(coverURLs.prefix(maxResults))
    }

    /// Downloads a cover image from URL
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

    // MARK: - Cover Image Helpers

    /// Ensures the book metadata has a cover image, searching if needed
    private func ensureCoverImage(for metadata: BookMetadata) async -> BookMetadata {
        if metadata.coverImageURL != nil {
            return metadata
        }

        // Try to find a cover image
        if let coverURL = await findFirstCoverImage(isbn: metadata.isbn, title: metadata.title, author: metadata.author) {
            return BookMetadata(
                isbn: metadata.isbn,
                title: metadata.title,
                author: metadata.author,
                yearPublished: metadata.yearPublished,
                coverImageURL: coverURL
            )
        }

        return metadata
    }

    /// Finds the first valid cover image from multiple sources
    private func findFirstCoverImage(isbn: String, title: String, author: String) async -> String? {
        // Try Open Library Covers API by ISBN
        if let coverURL = await getOpenLibraryCoverURL(isbn: isbn) {
            return coverURL
        }

        // Try Google Books by title + author
        if let coverURL = await searchGoogleBooks(query: "\(title) \(author)", maxResults: 1).first {
            return coverURL
        }

        // Try Bookcover API by ISBN
        if let coverURL = await getBookcoverAPIURL(isbn: isbn) {
            return coverURL
        }

        // Try Better World Books by ISBN
        if let coverURL = await getBetterWorldBooksURL(isbn: isbn) {
            return coverURL
        }

        return nil
    }

    /// Gets cover URL from Open Library Covers API if valid
    private func getOpenLibraryCoverURL(isbn: String) async -> String? {
        let coverURL = "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg"

        if await isValidImageURL(coverURL) {
            return coverURL
        }

        return nil
    }

    /// Checks if an image URL returns a valid (non-placeholder) image
    private func isValidImageURL(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(contentLength),
               length > minimumImageSize {
                return true
            }
        } catch {
            logger.debug("Failed to validate image URL \(urlString): \(error.localizedDescription)")
        }

        return false
    }

    // MARK: - Google Books API

    /// Searches Google Books and returns cover image URLs
    private func searchGoogleBooks(query: String, maxResults: Int) async -> [String] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=\(encodedQuery)&maxResults=\(maxResults)"

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return []
            }

            return items.compactMap { extractCoverURL(from: $0) }
        } catch {
            logger.error("Google Books search failed for query '\(query)': \(error.localizedDescription)")
            return []
        }
    }

    /// Looks up book metadata from Google Books API
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
        let author = (volumeInfo["authors"] as? [String])?.first ?? "Unknown Author"
        let yearPublished = extractYear(from: volumeInfo["publishedDate"] as? String)
        let coverImageURL = extractCoverURL(from: firstItem)

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: coverImageURL
        )
    }

    /// Extracts cover URL from a Google Books item
    private func extractCoverURL(from item: [String: Any]) -> String? {
        guard let volumeInfo = item["volumeInfo"] as? [String: Any],
              let imageLinks = volumeInfo["imageLinks"] as? [String: Any] else {
            return nil
        }

        let imageURL = imageLinks["large"] as? String
            ?? imageLinks["medium"] as? String
            ?? imageLinks["small"] as? String
            ?? imageLinks["thumbnail"] as? String
            ?? imageLinks["smallThumbnail"] as? String

        return imageURL?.replacingOccurrences(of: "http://", with: "https://")
    }

    // MARK: - Open Library API

    /// Looks up book metadata from Open Library API
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

        let yearPublished = extractYear(from: bookData["publish_date"] as? String)

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

    /// Searches Open Library for book covers
    private func searchOpenLibrary(title: String, author: String, maxResults: Int) async -> [String] {
        let query = "\(title) \(author)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://openlibrary.org/search.json?q=\(query)&limit=\(maxResults)"

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]] else {
                return []
            }

            return docs.compactMap { doc -> String? in
                guard let coverId = doc["cover_i"] as? Int else { return nil }
                return "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
            }
        } catch {
            logger.error("Open Library search failed for '\(title) \(author)': \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Bookcover API

    /// Gets cover URL from Bookcover API if valid
    private func getBookcoverAPIURL(isbn: String) async -> String? {
        let coverURL = "https://bookcover.longitood.com/bookcover/\(isbn)"

        if await isValidImageURL(coverURL) {
            return coverURL
        }

        return nil
    }

    // MARK: - Better World Books

    /// Gets cover URL from Better World Books if valid
    private func getBetterWorldBooksURL(isbn: String) async -> String? {
        let coverURL = "https://images.betterworldbooks.com/isbn/\(isbn).jpg"

        if await isValidImageURL(coverURL) {
            return coverURL
        }

        return nil
    }

    // MARK: - Helpers

    private func extractYear(from dateString: String?) -> String {
        guard let dateString = dateString else { return "Unknown" }

        let yearPattern = #"\b(19|20)\d{2}\b"#
        if let range = dateString.range(of: yearPattern, options: .regularExpression) {
            return String(dateString[range])
        }
        return dateString
    }
}
