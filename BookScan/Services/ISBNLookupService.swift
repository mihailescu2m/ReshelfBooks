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

/// One distinct description of an ISBN as returned by the metadata sources, with the
/// names of every source that agrees on it. Backs the "Edit Book" picker, which lets
/// the user replace wrong details with another source's answer.
struct EditionDescription {
    let metadata: BookMetadata
    let sources: [String]
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

    /// Session with a per-request timeout so a slow or hanging source can't make a
    /// lookup spin on URLSession's 60s default. The two primary metadata sources are
    /// tried sequentially, so without this cap two stalled requests could block the
    /// loading UI for ~2 minutes before the fallbacks even start.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12    // max stall per request
        config.timeoutIntervalForResource = 20   // max time for the whole transfer
        config.waitsForConnectivity = false      // fail fast when offline, don't queue
        return URLSession(configuration: config)
    }()

    private init() {}

    /// A descriptive User-Agent for APIs that ask callers to identify themselves
    /// (e.g. Crossref's "polite pool"). The version is read from the app bundle so it
    /// stays in step with the marketing version instead of going stale.
    private var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "BookScan/\(version) (mailto:mihailescu2m@gmail.com)"
    }

    // MARK: - Public API

    /// Main lookup function: two tiers of sources, each raced in parallel with
    /// first-hit-wins semantics (losers are cancelled).
    ///
    /// - Tier 1 — Open Library (catalog API) and Google Books: the highest-quality,
    ///   highest-hit-rate sources. Racing them caps the common case at
    ///   min(OL, Google) latency, and one hanging primary can no longer stall the
    ///   scan while the other already has the answer.
    /// - Tier 2 — started only when ALL of tier 1 missed: Open Library's search
    ///   index, Crossref (academic), Library of Congress (US legal deposit), Trove
    ///   (Australian; needs the API key from iOS Settings, silently skipped without
    ///   one), and Inventaire (multilingual European editions, incl. Romanian).
    ///   First-found-wins is fine at this tier: all five are "better than nothing",
    ///   and the Edit Book picker cleans up any rough result.
    ///
    /// Covers are deliberately NOT resolved here — metadata returns the moment a
    /// source answers, and the scan cover pipeline searches for artwork in parallel
    /// (continuing in the background after the book is saved).
    func lookupBook(isbn: String) async throws -> BookMetadata {
        let cleanISBN = ISBNValidator.normalize(isbn)

        // Remember when a source failed because the network itself was unreachable, so
        // the final error says "network problem" rather than the misleading "not found".
        var connectivityError: Error?
        func noteFailure(_ error: Error) {
            if Self.isConnectivityError(error) { connectivityError = error }
        }

        // Tier 1.
        if let metadata = await firstHit(isbn: cleanISBN, noteFailure: noteFailure, lookups: [
            { try await self.lookupFromOpenLibrary(isbn: $0) },
            { try await self.lookupFromGoogleBooks(isbn: $0) }
        ]) {
            return metadata
        }

        // Tier 2.
        if let metadata = await firstHit(isbn: cleanISBN, noteFailure: noteFailure, lookups: [
            { try await self.lookupFromOpenLibrarySearch(isbn: $0) },
            { try await self.lookupFromCrossref(isbn: $0) },
            { try await self.lookupFromLibraryOfCongress(isbn: $0) },
            { try await self.lookupFromTrove(isbn: $0) },
            { try await self.lookupFromInventaire(isbn: $0) }
        ]) {
            return metadata
        }

        if let connectivityError {
            throw ISBNLookupError.networkError(connectivityError)
        }
        throw ISBNLookupError.notFound
    }

    /// Races the given lookups; the first SUCCESS wins and the rest are cancelled.
    /// Failures are reported through `noteFailure` as they arrive (after a win the
    /// group returns immediately, so losers' cancellation errors are never consumed),
    /// letting the caller distinguish "offline" from a genuine miss.
    private func firstHit(
        isbn: String,
        noteFailure: (Error) -> Void,
        lookups: [(String) async throws -> BookMetadata]
    ) async -> BookMetadata? {
        await withTaskGroup(of: Result<BookMetadata, Error>.self) { group in
            for lookup in lookups {
                group.addTask {
                    do { return .success(try await lookup(isbn)) }
                    catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let metadata):
                    group.cancelAll()
                    return metadata
                case .failure(let error):
                    noteFailure(error)
                }
            }
            return nil
        }
    }

    /// Queries ALL metadata sources for this ISBN concurrently and returns every
    /// distinct description found, in the same priority order as `lookupBook`. Unlike
    /// `lookupBook` this never stops at the first hit — it exists so the user can pick
    /// the best description when the source that answered first got the details wrong.
    /// An ISBN identifies a single edition, so these are competing descriptions of the
    /// same book, not different editions.
    func lookupAllDescriptions(isbn: String) async -> [EditionDescription] {
        let cleanISBN = ISBNValidator.normalize(isbn)

        // All sources fan out concurrently (the actor suspends at each URLSession
        // await, so the requests overlap); a failed source simply contributes nothing.
        async let openLibrary       = lookupFromOpenLibrary(isbn: cleanISBN)
        async let googleBooks       = lookupFromGoogleBooks(isbn: cleanISBN)
        async let openLibrarySearch = lookupFromOpenLibrarySearch(isbn: cleanISBN)
        async let crossref          = lookupFromCrossref(isbn: cleanISBN)
        async let libraryOfCongress = lookupFromLibraryOfCongress(isbn: cleanISBN)
        async let trove             = lookupFromTrove(isbn: cleanISBN)
        async let inventaire        = lookupFromInventaire(isbn: cleanISBN)

        // Both Open Library endpoints carry the same public name; dedup merges them.
        let results: [(source: String, metadata: BookMetadata?)] = [
            ("Open Library", try? await openLibrary),
            ("Google Books", try? await googleBooks),
            ("Open Library", try? await openLibrarySearch),
            ("Crossref", try? await crossref),
            ("Library of Congress", try? await libraryOfCongress),
            ("Trove", try? await trove),
            ("Inventaire", try? await inventaire)
        ]
        let found = results.compactMap { result in
            result.metadata.map { (source: result.source, metadata: $0) }
        }
        return Self.dedupedDescriptions(found)
    }

    /// Collapses per-source results into distinct descriptions: results agreeing on
    /// (title, author, year) — compared case- and whitespace-insensitively — merge
    /// into one entry listing every agreeing source. Input order is priority order:
    /// the first occurrence supplies the canonical metadata and the output position.
    static func dedupedDescriptions(_ results: [(source: String, metadata: BookMetadata)]) -> [EditionDescription] {
        var keysInOrder: [String] = []
        var grouped: [String: (metadata: BookMetadata, sources: [String])] = [:]

        for (source, metadata) in results {
            let key = [metadata.title, metadata.author, metadata.yearPublished]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .joined(separator: "|")
            if var existing = grouped[key] {
                if !existing.sources.contains(source) { existing.sources.append(source) }
                grouped[key] = existing
            } else {
                grouped[key] = (metadata, [source])
                keysInOrder.append(key)
            }
        }
        return keysInOrder.compactMap { key in
            grouped[key].map { EditionDescription(metadata: $0.metadata, sources: $0.sources) }
        }
    }

    /// True for failures that mean the network is unreachable (as opposed to a source
    /// simply not knowing the book). `timedOut` is included: with
    /// `waitsForConnectivity = false` a dead connection commonly surfaces as a timeout.
    private static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .timedOut:
            return true
        default:
            return false
        }
    }

    /// Searches for book cover images from multiple sources and returns up to maxResults URLs
    func searchCoverImages(isbn: String, title: String, author: String, maxResults: Int = 6) async -> [String] {
        // Kick off every source concurrently so the slow per-source network calls
        // (including HEAD validation) overlap instead of running back-to-back.
        async let openLibraryByISBN = getOpenLibraryCoverURL(isbn: isbn)
        async let googleByISBN = getGoogleBooksCoverURL(isbn: isbn)
        async let googleByTitleAuthor = searchGoogleBooks(query: "\(title) \(author)", maxResults: 2)
        async let googleByTitle = searchGoogleBooks(query: title, maxResults: maxResults)
        async let openLibraryBySearch = searchOpenLibrary(title: title, author: author, maxResults: maxResults)
        async let itunesByTitleAuthor = getITunesCoverURL(title: title, author: author)
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
        if let url = await googleByISBN { append([url]) }
        append(await googleByTitleAuthor)
        append(await googleByTitle)
        append(await openLibraryBySearch)
        if let url = await itunesByTitleAuthor { append([url]) }
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

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }

        return data
    }

    // MARK: - JSON fetching

    /// Fetches `urlString` and decodes the body as a JSON object (`[String: Any]`).
    /// Throws `ISBNLookupError` on a malformed URL, a non-200 response, or a body that
    /// isn't a JSON object. `headers` lets a caller add request headers — e.g. the
    /// User-Agent that opts Crossref's API into its "polite pool".
    private func fetchJSON(_ urlString: String, headers: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ISBNLookupError.invalidResponse
        }
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISBNLookupError.invalidResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ISBNLookupError.decodingError
        }
        return json
    }

    // MARK: - Cover Image Helpers

    /// Phase 1 of the scan cover pipeline: races all the ISBN-keyed cover sources in
    /// parallel and returns the first valid URL (losers are cancelled). Needs nothing
    /// but the barcode, so the pipeline starts this while the metadata race runs.
    func findCoverURLByISBN(isbn: String) async -> String? {
        await firstNonNil([
            { await self.getOpenLibraryCoverURL(isbn: $0) },
            { await self.getGoogleBooksCoverURL(isbn: $0) },
            { await self.getWorldCatCoverURL(isbn: $0) },
            { await self.getBookcoverAPIURL(isbn: $0) },
            { await self.getBetterWorldBooksURL(isbn: $0) }
        ], input: isbn)
    }

    /// Phase 2 of the scan cover pipeline: title/author-based fallback, used only
    /// when neither the metadata source nor any ISBN-keyed source had a cover.
    func findCoverURL(title: String, author: String) async -> String? {
        if let url = await searchGoogleBooks(query: "\(title) \(author)", maxResults: 1).first {
            return url
        }
        if let url = await getITunesCoverURL(title: title, author: author) {
            return url
        }
        return await searchOpenLibrary(title: title, author: author, maxResults: 1).first
    }

    /// Races async operations on `input`; first non-nil result wins, rest cancelled.
    private func firstNonNil(_ operations: [(String) async -> String?], input: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for operation in operations {
                group.addTask { await operation(input) }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
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
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            // Size check filters out tiny placeholder images (e.g. Open Library's
            // 1x1 "no cover" GIF), so prefer it whenever the server reports a length.
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(contentLength) {
                return length > minimumImageSize
            }
            // No Content-Length (e.g. a chunked HEAD response): fall back to the
            // content type so such servers aren't rejected outright.
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            return contentType.hasPrefix("image/")
        } catch {
            logger.debug("Failed to validate image URL \(urlString): \(error.localizedDescription)")
        }

        return false
    }

    // MARK: - Google Books API

    /// Builds a URL string with properly escaped query values. `.urlQueryAllowed`
    /// percent-encoding is NOT enough for free-text values: it leaves `&`, `=` and `+`
    /// intact (each is legal *somewhere* in a query), so a title like
    /// "Pride & Prejudice" would be cut off at the ampersand server-side.
    /// URLComponents escapes the values correctly; the extra pass escapes `+`, which
    /// URLComponents leaves alone but many servers decode as a space.
    private static func queryURLString(base: String, items: [(String, String)]) -> String? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url?.absoluteString
    }

    /// Searches Google Books and returns cover image URLs
    private func searchGoogleBooks(query: String, maxResults: Int) async -> [String] {
        guard let urlString = Self.queryURLString(
            base: "https://www.googleapis.com/books/v1/volumes",
            items: [("q", query), ("maxResults", String(maxResults))]
        ) else { return [] }

        guard let json = try? await fetchJSON(urlString),
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { extractCoverURL(from: $0) }
    }

    /// Looks up book metadata from Google Books API
    private func lookupFromGoogleBooks(isbn: String) async throws -> BookMetadata {
        let json = try await fetchJSON("https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)")

        guard let items = json["items"] as? [[String: Any]],
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

        // Prefer the largest tier available. `extraLarge`/`large` only appear in the
        // single-volume detail response (see getGoogleBooksCoverURL); search results
        // carry just thumbnail/smallThumbnail, which we clean up below.
        let imageURL = imageLinks["extraLarge"] as? String
            ?? imageLinks["large"] as? String
            ?? imageLinks["medium"] as? String
            ?? imageLinks["small"] as? String
            ?? imageLinks["thumbnail"] as? String
            ?? imageLinks["smallThumbnail"] as? String

        return imageURL.map(Self.cleanGoogleBooksImageURL)
    }

    /// Normalizes a Google Books image URL: HTTPS, and drops the `edge=curl` flag
    /// that renders an ugly page-curl effect on the thumbnail. (We deliberately do
    /// not touch the `zoom` parameter — its behaviour varies by volume and a wrong
    /// value silently yields a broken image.)
    private static func cleanGoogleBooksImageURL(_ url: String) -> String {
        url.replacingOccurrences(of: "http://", with: "https://")
           .replacingOccurrences(of: "&edge=curl", with: "")
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
        let json = try await fetchJSON(
            "https://api.crossref.org/works?filter=isbn:\(isbn)&rows=1",
            headers: ["User-Agent": userAgent]
        )

        guard let message = json["message"] as? [String: Any],
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
        let json = try await fetchJSON("https://www.loc.gov/books/?q=\(encodedISBN)&fo=json&c=1")

        guard let results = json["results"] as? [[String: Any]],
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
        let json = try await fetchJSON("https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")

        guard let bookData = json["ISBN:\(isbn)"] as? [String: Any] else {
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
        let json = try await fetchJSON(urlString)

        guard let docs = json["docs"] as? [[String: Any]],
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
        guard let urlString = Self.queryURLString(
            base: "https://openlibrary.org/search.json",
            items: [("q", "\(title) \(author)"), ("limit", String(maxResults))]
        ) else { return [] }

        guard let json = try? await fetchJSON(urlString),
              let docs = json["docs"] as? [[String: Any]] else {
            return []
        }
        return docs.compactMap { doc -> String? in
            guard let coverId = doc["cover_i"] as? Int else { return nil }
            return "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
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
        guard let json = try? await fetchJSON("https://bookcover.longitood.com/bookcover/\(isbn)"),
              let imageURL = json["url"] as? String,
              !imageURL.isEmpty else {
            return nil
        }
        return await isValidImageURL(imageURL) ? imageURL : nil
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

    // MARK: - iTunes / Apple Books

    /// Cover artwork from the iTunes Search API (Apple Books). Free, no key. The API
    /// is a text search, so the query is title + author; artwork comes back at 100px
    /// and the URL is upscaled to 600px by swapping the size token. Strong coverage
    /// of mainstream commercial titles.
    private func getITunesCoverURL(title: String, author: String) async -> String? {
        guard let urlString = Self.queryURLString(
            base: "https://itunes.apple.com/search",
            items: [("term", "\(title) \(author)"), ("media", "ebook"), ("limit", "1")]
        ),
        let json = try? await fetchJSON(urlString),
        let results = json["results"] as? [[String: Any]],
        let artwork = results.first?["artworkUrl100"] as? String else {
            return nil
        }
        // Artwork URLs end in ".../100x100bb.jpg"; request a larger render.
        return artwork.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }

    // MARK: - Google Books cover (volume detail)

    /// Highest-resolution Google Books cover for an ISBN. The volumes SEARCH response
    /// only carries thumbnail/smallThumbnail; the single-volume DETAIL response adds
    /// small/medium/large/extraLarge when the publisher supplied them — so this does
    /// the two-step (search for the volume id, then fetch its detail) to reach those
    /// larger images. Falls back to the cleaned thumbnail.
    private func getGoogleBooksCoverURL(isbn: String) async -> String? {
        guard let search = try? await fetchJSON("https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"),
              let items = search["items"] as? [[String: Any]],
              let volumeID = items.first?["id"] as? String else {
            return nil
        }
        guard let detail = try? await fetchJSON("https://www.googleapis.com/books/v1/volumes/\(volumeID)"),
              let volumeInfo = detail["volumeInfo"] as? [String: Any] else {
            // Detail fetch failed — use the cleaned thumbnail from the search hit.
            return extractCoverURL(from: items[0])
        }
        return extractCoverURL(from: ["volumeInfo": volumeInfo])
    }

    // MARK: - Trove (National Library of Australia)

    /// User-supplied Trove API key, pasted into the app's iOS Settings page.
    /// nil (or empty/whitespace) disables the Trove source entirely.
    private var troveAPIKey: String? {
        let key = UserDefaults.standard.string(forKey: "trove_api_key")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty ?? true) ? nil : key
    }

    /// Looks up book metadata from Trove (National Library of Australia).
    ///
    /// Trove aggregates the NLA catalogue plus the holdings of libraries across
    /// Australia — by far the deepest source for Australian-published books. It
    /// requires a free API key (request at trove.nla.gov.au; keys expire after 12
    /// months) entered in the iOS Settings page; without one this source simply
    /// reports "not found" and the cascade moves on. An invalid/expired key fails
    /// the same way (non-200 → invalidResponse), so lookups degrade gracefully.
    ///
    /// Trove work records only carry small thumbnails, so no cover URL is returned —
    /// the cover pipeline finds a full-size image from the dedicated cover sources.
    private func lookupFromTrove(isbn: String) async throws -> BookMetadata {
        guard let key = troveAPIKey else { throw ISBNLookupError.notFound }

        let json = try await fetchJSON(
            "https://api.trove.nla.gov.au/v3/result?category=book&q=isbn:\(isbn)&encoding=json&n=1",
            headers: ["X-API-KEY": key]
        )

        guard let categories = json["category"] as? [[String: Any]],
              let records = categories.first?["records"] as? [String: Any],
              let works = records["work"] as? [[String: Any]],
              let work = works.first,
              let title = work["title"] as? String, !title.isEmpty else {
            throw ISBNLookupError.notFound
        }

        // Contributors use the same "Last, First, dates" authority form as LOC.
        let author: String
        if let contributors = work["contributor"] as? [String], let raw = contributors.first {
            author = reformatLOCContributor(raw)
        } else {
            author = "Unknown Author"
        }

        // "issued" may be a year (Int) or a range string like "2008-2014".
        let yearPublished: String
        if let year = work["issued"] as? Int {
            yearPublished = String(year)
        } else {
            yearPublished = extractYear(from: work["issued"] as? String)
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: nil   // thumbnails only; covers come from the cover sources
        )
    }

    // MARK: - Inventaire

    /// Looks up book metadata from Inventaire (inventaire.io).
    ///
    /// Inventaire is a Wikidata-federated open bibliographic database (CC0) with
    /// broad multilingual coverage — notably European editions (including Romanian)
    /// that the big English-centric sources miss. No API key required.
    ///
    /// The data model is Wikidata-style: the ISBN resolves to an *edition* entity;
    /// the edition links its *work* (P629); the work links its *author* (P50), whose
    /// label is fetched last — so a full lookup is up to three small requests.
    private func lookupFromInventaire(isbn: String) async throws -> BookMetadata {
        let edition = try await inventaireEntity(uri: "isbn:\(isbn)")

        guard let title = inventaireClaim(edition, "wdt:P1476") ?? inventaireLabel(edition),
              !title.isEmpty else {
            throw ISBNLookupError.notFound
        }

        // Author (via the work) and the work's publication year as a fallback.
        var author = "Unknown Author"
        var workYear: String?
        if let workURI = inventaireClaim(edition, "wdt:P629"),
           let work = try? await inventaireEntity(uri: workURI) {
            workYear = inventaireClaim(work, "wdt:P577")
            if let authorURI = inventaireClaim(work, "wdt:P50"),
               let authorEntity = try? await inventaireEntity(uri: authorURI),
               let name = inventaireLabel(authorEntity) {
                author = name
            }
        }

        // Prefer the edition's own publication date over the work's first-published.
        let yearPublished = extractYear(from: inventaireClaim(edition, "wdt:P577") ?? workYear)

        // Editions often carry a community-uploaded cover image.
        var coverImageURL: String?
        if let image = edition["image"] as? [String: Any],
           let path = image["url"] as? String {
            coverImageURL = "https://inventaire.io\(path)"
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            author: author,
            yearPublished: yearPublished,
            coverImageURL: coverImageURL
        )
    }

    /// Fetches a single Inventaire entity (edition, work, or author) by URI.
    /// The response keys entities by their canonical URI, which may differ from the
    /// requested one (isbn: URIs redirect to wd:/inv: IDs), so take the first value.
    private func inventaireEntity(uri: String) async throws -> [String: Any] {
        let json = try await fetchJSON("https://inventaire.io/api/entities/by-uris?uris=\(uri)")
        guard let entities = json["entities"] as? [String: Any],
              let entity = entities.values.first as? [String: Any] else {
            throw ISBNLookupError.notFound
        }
        return entity
    }

    /// First value of a claim (e.g. "wdt:P1476") on an Inventaire entity, if any.
    private func inventaireClaim(_ entity: [String: Any], _ property: String) -> String? {
        guard let claims = entity["claims"] as? [String: Any],
              let values = claims[property] as? [Any],
              let first = values.first else { return nil }
        return "\(first)"
    }

    /// The entity's English label, falling back to any available language.
    private func inventaireLabel(_ entity: [String: Any]) -> String? {
        guard let labels = entity["labels"] as? [String: Any] else { return nil }
        return (labels["en"] ?? labels.values.first) as? String
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
