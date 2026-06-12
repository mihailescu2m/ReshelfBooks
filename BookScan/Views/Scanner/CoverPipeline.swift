//
//  CoverPipeline.swift
//  BookScan
//
//  Created by Marian Mihailescu on 12/6/2026.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "CoverPipeline")

/// Finds cover art for a newly scanned book WITHOUT ever delaying the scan flow.
///
/// Lifecycle (owned by ScannerTabView, one instance per scanned new book):
/// 1. `start(isbn:)` fires at lookup time — phase 1 (the ISBN-keyed cover sources)
///    races in parallel with the metadata lookup.
/// 2. `metadataArrived(_:)` feeds in the lookup result: the winning source's own
///    cover URL becomes the top-priority candidate, and a title/author search
///    (phase 2) joins only if nothing else produced a cover.
/// 3. NewBookView observes `image`/`isSearching` — the preview fills in whenever
///    ready; the sheet never waits.
/// 4. `attach(to:)` on Add to Library: an already-found image is written
///    immediately; otherwise the search continues in the BACKGROUND and writes on
///    completion (guarded by `isGone`), while the user scans the next book.
/// 5. `cancel()` on Cancel / scanner reset stops all work.
///
/// The main task closure retains `self`, so the pipeline stays alive after
/// ScannerTabView releases it on save, and frees itself when the task finishes.
@MainActor
final class CoverPipeline: ObservableObject {

    /// The best cover found so far, for the NewBookView preview.
    @Published private(set) var image: UIImage?
    /// True while the search/download is still running.
    @Published private(set) var isSearching = true

    /// Normalized (size-capped, re-encoded) JPEG of `image`, kept so the eventual
    /// Core Data write doesn't have to re-compress the preview a second time.
    private var imageData: Data?

    private var task: Task<Void, Never>?

    /// True once the pipeline has been handed a saved book (or wrote its cover):
    /// from then on it belongs to that book, and the scanner's reset must not
    /// cancel it.
    private(set) var isAttached = false

    /// Set when the book is saved before the search finished; the cover is attached
    /// the moment it arrives.
    private var pendingBook: Book?
    private var persistence: PersistenceController?

    /// Bridges the metadata race's result into the running task. `.some(nil)` means
    /// the lookup failed (no book will be saved), `nil` means still pending.
    private var metadataResult: BookMetadata??
    private var metadataContinuation: CheckedContinuation<BookMetadata?, Never>?

    /// Creates a pipeline that is already finished with no image (previews/fallback).
    static func finished() -> CoverPipeline {
        let pipeline = CoverPipeline()
        pipeline.isSearching = false
        return pipeline
    }

    // MARK: - Driving (ScannerTabView)

    /// Begins the search. Phase 1 (ISBN-keyed sources) starts immediately; the rest
    /// waits for `metadataArrived`.
    func start(isbn: String) {
        guard task == nil else { return }
        task = Task {
            // Capturing self strongly is intentional: the pipeline must outlive the
            // owning view's reference once a save hands it a pendingBook.
            let data = await self.searchCoverData(isbn: isbn)
            self.finish(with: data)
        }
    }

    /// Feeds in the metadata race's verdict (nil = lookup failed; stop quietly).
    func metadataArrived(_ metadata: BookMetadata?) {
        if let continuation = metadataContinuation {
            metadataContinuation = nil
            continuation.resume(returning: metadata)
        } else {
            metadataResult = .some(metadata)
        }
    }

    /// Called on Add to Library. Writes the cover now if it's already in hand,
    /// otherwise remembers the book and writes when the search completes.
    func attach(to book: Book, persistence: PersistenceController) {
        isAttached = true
        if let imageData {
            write(imageData, to: book, persistence: persistence)
        } else if isSearching {
            pendingBook = book
            self.persistence = persistence
        }
    }

    /// Stops all work (sheet cancelled, scanner reset, or a new scan superseding us).
    func cancel() {
        task?.cancel()
        // A pending waitForMetadata must be released or the task never exits.
        metadataArrived(nil)
        pendingBook = nil
        persistence = nil
        isSearching = false
    }

    // MARK: - Search

    private func searchCoverData(isbn: String) async -> Data? {
        // Phase 1 races while the metadata lookup runs elsewhere.
        async let isbnCoverURL = ISBNLookupService.shared.findCoverURLByISBN(isbn: isbn)

        // No metadata means the lookup failed — no sheet, no book, nothing to do.
        // (Returning here cancels the unawaited phase-1 child task automatically.)
        guard let metadata = await waitForMetadata() else { return nil }

        // Candidates in quality order; first one that downloads and decodes wins.
        // The winning metadata source's own URL is most likely to match the edition.
        if let url = metadata.coverImageURL, let data = await download(url) { return data }
        if Task.isCancelled { return nil }
        if let url = await isbnCoverURL, let data = await download(url) { return data }
        if Task.isCancelled { return nil }
        if let url = await ISBNLookupService.shared.findCoverURL(title: metadata.title, author: metadata.author),
           let data = await download(url) {
            return data
        }
        return nil
    }

    private func waitForMetadata() async -> BookMetadata? {
        if let result = metadataResult { return result }
        return await withCheckedContinuation { metadataContinuation = $0 }
    }

    /// Downloads and normalizes (size-cap + re-encode) a candidate; nil on any failure.
    private func download(_ url: String) async -> Data? {
        guard !Task.isCancelled,
              let raw = try? await ISBNLookupService.shared.downloadCoverImage(from: url) else {
            return nil
        }
        return CoverImage.normalizedData(from: raw)
    }

    // MARK: - Completion

    private func finish(with data: Data?) {
        if let data {
            imageData = data
            image = UIImage(data: data)
        }
        isSearching = false
        if let data, let book = pendingBook, let persistence {
            write(data, to: book, persistence: persistence)
        }
        pendingBook = nil
        persistence = nil
        task = nil
    }

    private func write(_ data: Data, to book: Book, persistence: PersistenceController) {
        // The book may have been deleted (locally or by a family member) while the
        // cover was still downloading.
        guard !book.isGone else { return }
        book.coverImageData = data
        persistence.save()
        logger.info("Attached cover found in background")
    }
}
