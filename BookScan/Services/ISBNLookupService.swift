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

    /// Main lookup function — tries five sources in order, stopping at the first hit.
    ///
    /// Each source covers a different sweet spot:
    /// - Open Library (catalog API): classics, public-domain, library-catalogued, older titles
    /// - Google Books: modern popular / English-language titles
    /// - Open Library (search index): contemporary popular fiction & non-fiction — backed by
    ///   a different (Solr) index than the catalog API, so it often has records the catalog
    ///   call misses
    /// - Crossref: academic, scientific, textbooks, university press (Springer, OUP, etc.)
    /// - Library of Congress: niche US-published books, regional publishers, children's
    ///   books, cookbooks, official publications — anything with a US legal deposit record
    func lookupBook(isbn: String) async throws -> BookMetadata {
        let cleanISBN = ISBNValidator.normalize(isbn)

        // Try Open Library catalog API first
        if let result = try? await lookupFromOpenLibrary(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        // Fallback to Google Books
        if let result = try? await lookupFromGoogleBooks(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        // Second fallback: Open Library search index — a different backend than the catalog
        // API above, with strong coverage of contemporary popular fiction & non-fiction that
        // the catalog call (and sometimes Google Books) misses.
        if let result = try? await lookupFromOpenLibrarySearch(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        // Third fallback: Crossref — strongest coverage for academic and technical books
        // that the consumer-facing sources commonly miss.
        if let result = try? await lookupFromCrossref(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        // Fourth fallback: Library of Congress — niche US publications, regional titles,
        // children's books, and official publications not well covered elsewhere.
        if let result = try? await lookupFromLibraryOfCongress(isbn: cleanISBN) {
            return await ensureCoverImage(for: result)
        }

        throw ISBNLookupError.notFound
    }

    /// Searches for book cover images from multiple sources and returns up to maxResults URLs
    func searchCoverImages(isbn: String, title: String, author: String, maxResults: Int = 6) async -> [String] {
        // Kick off every source concurrently so the slow per-source network calls
        // (including HEAD validation) overlap instead of running back-to-back.
        async let openLibraryByISBN = getOpenLibraryCoverURL(isbn: isbn)
        async let googleByISBN = searchGoogleBooks(query: "isbn:\(isbn)", maxResults: 1)
        async let googleByTitleAuthor = searchGoogleBooks(query: "\(title) \(author)", maxResults: 2)
        async let googleByTitle = searchGoogleBooks(query: title, maxResults: maxResults)
        async let openLibraryBySearch = searchOpenLibrary(title: title, author: author, maxResults: maxResults)
        async let bookcoverByISBN = getBookcoverAPIURL(isbn: isbn)
        async let betterWorldByISBN = getBetterWorldBooksURL(isbn: isbn)
        async let worldcatByISBN = getWorldCatCoverURL(isbn: isbn)

        var coverURLs: [String] = []
        func append(_ candidates: [String]) {
            for url in candidates where !coverURLs.contains(url) {
                coverURLs.append(url)
            }
        }

        // Assemble in priority order: ISBN matches first, then title/author, then broader fallbacks.
        if let url = await openLibraryByISBN { append([url]) }
        append(await googleByISBN)
        append(await googleByTitleAuthor)
        append(await googleByTitle)
        append(await openLibraryBySearch)
        if let url = await bookcoverByISBN { append([url]) }
        if let url = await betterWorldByISBN { append([url]) }
        if let url = await worldcatByISBN { append([url]) }

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

        // Try WorldCat (OCLC) by ISBN — good coverage for academic & non-English books
        if let coverURL = await getWorldCatCoverURL(isbn: isbn) {
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

    // MARK: - Crossref API

    /// Looks up book metadata from the Crossref API.
    ///
    /// Crossref is the DOI registration agency used by virtually every academic and
    /// scientific publisher worldwide — Springer, Elsevier, Oxford/Cambridge University
    /// Press, MIT Press, IEEE, ACM, and thousands more. It indexes ~155 million works and
    /// consistently returns metadata for textbooks, university press titles, and specialist
    /// non-fiction that Open Library and Google Books both miss.
    ///
    /// Free, no API key required. Adding a `mailto:` to the User-Agent header opts the
    /// request into Crossref's "polite pool" — higher rate limits and prioritised service
    /// in exchange for being identifiable. This is the API's own documented request.
    ///
    /// Crossref does not serve cover images; cover sources are handled separately.
    private func lookupFromCrossref(isbn: String) async throws -> BookMetadata {
        let urlString = "https://api.crossref.org/works?filter=isbn:\(isbn)&rows=1"
        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("BookScan/1.3 (mailto:mihailescu2m@gmail.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]],
              let item = items.first else {
            throw ISBNLookupError.notFound
        }

        // Crossref returns title as an array; take the first non-empty element.
        guard let titleArray = item["title"] as? [String],
              let title = titleArray.first, !title.isEmpty else {
            throw ISBNLookupError.notFound
        }

        // Author entries carry structured "given"/"family" fields; organisations use "name".
        let author: String
        if let authors = item["author"] as? [[String: Any]], let first = authors.first {
            let given  = first["given"]  as? String ?? ""
            let family = first["family"] as? String ?? ""
            let full   = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            author = full.isEmpty ? (first["name"] as? String ?? "Unknown Author") : full
        } else {
            author = "Unknown Author"
        }

        // date-parts is a nested array: [[year, month, day]] — only year is guaranteed.
        var yearPublished = "Unknown"
        if let published  = item["published"]   as? [String: Any],
           let dateParts  = published["date-parts"] as? [[Int]],
           let year       = dateParts.first?.first {
            yearPublished = String(year)
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: nil   // Crossref doesn't serve cover images
        )
    }

    // MARK: - Library of Congress API

    /// Looks up book metadata from the Library of Congress catalog.
    ///
    /// The LOC is the US national library and legal deposit holder for all US publications.
    /// It fills the gap left by the other three sources: niche non-fiction, regional and
    /// small-press publishers, children's books, cookbooks, lifestyle titles, and official
    /// government publications — anything that received a US copyright registration but
    /// wasn't big enough to appear prominently in Google Books or Open Library.
    ///
    /// The `/books/` JSON endpoint performs a keyword search against all catalog fields
    /// (including ISBN), so the ISBN query reliably targets the matching record.
    /// Free, no API key. LOC does not serve cover images.
    private func lookupFromLibraryOfCongress(isbn: String) async throws -> BookMetadata {
        let encodedISBN = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let urlString = "https://www.loc.gov/books/?q=\(encodedISBN)&fo=json&c=1"
        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let title = first["title"] as? String, !title.isEmpty else {
            throw ISBNLookupError.notFound
        }

        // LOC contributor format: "Last, First, 1775-1817" — reformat to "First Last".
        let author: String
        if let contributors = first["contributor"] as? [String],
           let raw = contributors.first {
            author = reformatLOCContributor(raw)
        } else {
            author = "Unknown Author"
        }

        let yearPublished = extractYear(from: first["date"] as? String)

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: nil   // LOC doesn't serve cover images
        )
    }

    /// Converts a LOC authority-file contributor string to a display name.
    ///
    /// LOC stores authors in AACR2/RDA authority form: "Last, First, dates"
    /// (e.g. "Austen, Jane, 1775-1817") or for organisations just "Name".
    /// We split on ", ", drop any pure-date segments, and reverse the name parts.
    private func reformatLOCContributor(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Keep only parts that start with a letter (drops "1775-1817", "-2020", etc.).
        let nameParts = parts.filter { $0.first?.isLetter == true }

        switch nameParts.count {
        case 0: return parts.first ?? raw     // fallback: return raw string
        case 1: return nameParts[0]           // single-segment: organisation name
        default: return "\(nameParts[1]) \(nameParts[0])"  // "First Last"
        }
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

    /// Looks up book metadata from the Open Library **search index** (`/search.json`).
    ///
    /// This is a separate backend from `lookupFromOpenLibrary` (which hits the `/api/books`
    /// catalog endpoint). The two indexes are populated independently, so a book absent from
    /// the catalog API can still be present here — particularly contemporary popular fiction
    /// and non-fiction. The search index also returns cleaner structured fields:
    /// `author_name` as an array and `first_publish_year` as an integer.
    private func lookupFromOpenLibrarySearch(isbn: String) async throws -> BookMetadata {
        // Restrict the payload to just the fields we use; `limit=1` since ISBN is unique.
        let urlString = "https://openlibrary.org/search.json?isbn=\(isbn)"
            + "&fields=title,author_name,first_publish_year,cover_i&limit=1"
        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]],
              let doc = docs.first,
              let title = doc["title"] as? String, !title.isEmpty else {
            throw ISBNLookupError.notFound
        }

        let author = (doc["author_name"] as? [String])?.first ?? "Unknown Author"

        let yearPublished: String
        if let year = doc["first_publish_year"] as? Int {
            yearPublished = String(year)
        } else {
            yearPublished = "Unknown"
        }

        var coverImageURL: String? = nil
        if let coverId = doc["cover_i"] as? Int {
            coverImageURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
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

    /// Gets a cover image URL from the Bookcover API.
    ///
    /// The endpoint returns a JSON body like `{"url": "https://…/cover.jpg"}`, NOT an
    /// image directly. Treating the API endpoint as an image URL (via `isValidImageURL`)
    /// would pass the HEAD/size check (the JSON response is large enough), but then
    /// `UIImage(data:)` on the downloaded JSON would return nil — silently wasting a
    /// network round-trip and never yielding a cover. Instead we parse the JSON to get
    /// the real image URL and validate that.
    private func getBookcoverAPIURL(isbn: String) async -> String? {
        let apiURLString = "https://bookcover.longitood.com/bookcover/\(isbn)"
        guard let apiURL = URL(string: apiURLString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let imageURL = json["url"] as? String,
                  !imageURL.isEmpty else {
                return nil
            }
            return await isValidImageURL(imageURL) ? imageURL : nil
        } catch {
            logger.debug("Bookcover API request failed for ISBN \(isbn): \(error.localizedDescription)")
            return nil
        }
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

    // MARK: - WorldCat (OCLC)

    /// Gets cover URL from WorldCat (OCLC) if valid.
    ///
    /// WorldCat is run by OCLC — the world's largest library cooperative — and has
    /// particularly strong coverage of academic titles, older publications, and
    /// non-English books that the other sources often miss. Free, no API key needed.
    private func getWorldCatCoverURL(isbn: String) async -> String? {
        let coverURL = "https://covers.worldcat.org/isbn/\(isbn)-L.jpg"

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
