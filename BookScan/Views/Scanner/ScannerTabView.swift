//
//  ScannerTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import CoreData
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "Scanner")

/// All sheets the scanner can present. A single enum drives one `.sheet(item:)`,
/// so SwiftUI never has two competing presentation state machines on the same view —
/// which causes the first presentation to be immediately dismissed on iPad.
enum ScannerSheet: Identifiable {
    case existingBook(Book, wasReturned: Bool)
    case newBook(BookMetadata)
    case manualEntry(initialISBN: String?)

    var id: String {
        switch self {
        case .existingBook(let book, _):
            return "existing-\(book.isbn)"
        case .newBook(let metadata):
            return "new-\(metadata.isbn)"
        case .manualEntry(let isbn):
            return "manual-\(isbn ?? "")"
        }
    }
}

/// Work to run once the current sheet has fully dismissed. SwiftUI can't swap one
/// presentation for another in place, so we stash the follow-up and perform it in
/// `onDismiss`, which avoids the timing hacks the old two-sheet design needed.
private enum PendingScannerAction {
    case showManualEntry(initialISBN: String?)
    case lookup(String)
}

struct ScannerTabView: View {
    /// Whether the Scanner tab is currently visible. The camera only runs while
    /// it is, so we don't hold the camera (and show the green indicator) on other tabs.
    var isTabActive: Bool = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var persistence: PersistenceController
    @FetchRequest(sortDescriptors: []) private var books: FetchedResults<Book>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(key: "sortOrder", ascending: true),
        NSSortDescriptor(key: "dateCreated", ascending: true),
        NSSortDescriptor(key: "name", ascending: true)
    ])
    private var shelves: FetchedResults<Shelf>

    @State private var scannedCode: String?
    @State private var isScanning = true
    @State private var activeSheet: ScannerSheet?
    @State private var pendingAction: PendingScannerAction?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lookupTask: Task<Void, Never>?

    var body: some View {
        // No NavigationStack — this view is a page inside ContentView's page-style
        // TabView (backed by UIPageViewController). Wrapping each tab in its own
        // NavigationStack nests wrapped navigation controllers, which crashes on iPad
        // (NSInternalInconsistencyException) when both pages lay out at once. The
        // toolbar is replaced by an inline header overlaid on the camera instead.
        ZStack {
            BarcodeScannerView(
                scannedCode: $scannedCode,
                // Effective camera state: only run when this tab is visible AND
                // we're in the scanning state. The setter preserves the scanner's
                // own writes (it sets false after finding a code).
                isScanning: Binding(
                    get: { isTabActive && isScanning },
                    set: { isScanning = $0 }
                )
            )
            .ignoresSafeArea()

            if isLoading {
                loadingOverlay
            }

            VStack(spacing: 0) {
                header

                VStack {
                    enterISBNButton

                    if let error = errorMessage {
                        errorBanner(message: error)
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .onChange(of: scannedCode) { _, newValue in
            if let code = newValue {
                handleScannedCode(code)
            }
        }
        // Single sheet modifier — two modifiers on the same view cause SwiftUI's
        // internal presentation state machines to compete, producing an immediate
        // auto-dismiss on the first presentation (reproducible on iPad simulator).
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            sheetContent(for: sheet)
        }
    }

    /// Inline header overlaid on the camera (replaces the old nav-bar toolbar).
    /// The material background keeps the centered title and reset button legible.
    private var header: some View {
        ZStack {
            Text("Scan Book")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Spacer()
                Button {
                    resetScanner()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(isScanning && !isLoading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func sheetContent(for sheet: ScannerSheet) -> some View {
        switch sheet {
        case .existingBook(let book, let wasReturned):
            ExistingBookView(book: book, wasReturned: wasReturned, onManualEntry: {
                transitionToManualEntry()
            })
        case .newBook(let metadata):
            NewBookView(metadata: metadata, shelves: persistence.visibleOnly(shelves), onSave: { shelf, coverImage in
                saveNewBook(metadata: metadata, shelf: shelf, coverImage: coverImage)
            }, onManualEntry: {
                transitionToManualEntry()
            })
        case .manualEntry(let isbn):
            // Use .sheet (not .fullScreenCover) so this doesn't share the parent
            // navigation context — fullScreenCover on iPad causes a crash. On iPhone
            // (compact) remove the corner radius so it looks like a full-screen cover;
            // on iPad keep the default radius.
            ManualISBNEntryView(initialISBN: isbn, onLookup: { lookupISBN in
                pendingAction = .lookup(lookupISBN)
                activeSheet = nil
            })
            .presentationDetents([.large])
            .presentationCornerRadius(horizontalSizeClass == .compact ? 0 : 12)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Looking up book...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .foregroundColor(.white)
            Spacer()
            Button {
                errorMessage = nil
                resetScanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .cornerRadius(12)
    }

    private var enterISBNButton: some View {
        Button {
            isScanning = false
            activeSheet = .manualEntry(initialISBN: scannedCode)
        } label: {
            HStack {
                Image(systemName: "keyboard")
                Text("Enter ISBN")
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(25)
        }
        .padding(.top, 20)
    }

    // MARK: - Sheet coordination

    /// Dismisses any active card sheet, then presents the full-screen manual entry cover.
    /// Called from within ExistingBookView / NewBookView via their onManualEntry callback.
    private func transitionToManualEntry(initialISBN: String? = nil) {
        pendingAction = .showManualEntry(initialISBN: initialISBN)
        activeSheet = nil
    }

    private func handleSheetDismiss() {
        switch pendingAction {
        case .showManualEntry(let isbn):
            pendingAction = nil
            activeSheet = .manualEntry(initialISBN: isbn)
        case .lookup(let isbn):
            pendingAction = nil
            handleScannedCode(isbn)
        case nil:
            resetScanner()
        }
    }

    // MARK: - Scan handling

    private func handleScannedCode(_ code: String) {
        // Canonicalize to ISBN-13 on BOTH sides of the comparison: the camera always
        // delivers EAN-13, but a book entered by hand may be stored as ISBN-10 (and
        // participant-store books can predate the owner-side bootstrap migration).
        let isbn = ISBNValidator.canonicalize(code)
        // Match only against the active library's books: a private book parked while
        // participating in a shared library shouldn't block adding the same title to
        // the family library (and its hidden shelf couldn't be shown anyway).
        if let book = persistence.visibleOnly(books).first(where: { ISBNValidator.canonicalize($0.isbn) == isbn }) {
            // Scanning a lent book returns it (per the lending shelf's instructions).
            if book.isLent {
                book.returnBook()
                persistence.save()
                activeSheet = .existingBook(book, wasReturned: true)
            } else {
                activeSheet = .existingBook(book, wasReturned: false)
            }
        } else {
            lookupBook(isbn: isbn)
        }
    }

    private func lookupBook(isbn: String) {
        // An EAN-13 outside the "Bookland" 978/979 prefixes is a product barcode, not
        // an ISBN — say so instead of running five doomed catalog lookups. Unlike the
        // network-error path below, scanning is NOT resumed here: this guard fails
        // instantly, so resuming with the same barcode still in frame would re-detect
        // it several times a second (haptic buzzing, banner flicker). The camera is
        // already stopped; the banner's ✕ runs resetScanner() and resumes cleanly.
        if isbn.count == 13 && !isbn.hasPrefix("978") && !isbn.hasPrefix("979") {
            errorMessage = "This barcode isn't a book ISBN."
            scannedCode = nil
            return
        }

        isLoading = true
        errorMessage = nil

        lookupTask?.cancel()
        lookupTask = Task {
            do {
                let metadata = try await ISBNLookupService.shared.lookupBook(isbn: isbn)
                await MainActor.run {
                    // Re-check cancellation *inside* the hop: a reset that lands
                    // between the await and this assignment must not resurrect a
                    // stale result.
                    guard !Task.isCancelled else { return }
                    isLoading = false
                    activeSheet = .newBook(metadata)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isLoading = false
                    errorMessage = error.localizedDescription
                    scannedCode = nil
                    isScanning = true
                }
            }
        }
    }

    private func saveNewBook(metadata: BookMetadata, shelf: Shelf?, coverImage: UIImage?) {
        // Factory attaches the book to the active library and assigns it to the
        // correct CloudKit store (private for the owner, shared for a participant).
        let book = persistence.makeBook(
            isbn: metadata.isbn,
            title: metadata.title,
            author: metadata.author,
            yearPublished: metadata.yearPublished,
            coverImageURL: metadata.coverImageURL,
            shelf: shelf
        )

        if let coverImage {
            // Reuse the image already downloaded for the preview — no second fetch.
            book.coverImageData = coverImage.coverJPEGData()
            persistence.save()
        } else if let coverURL = metadata.coverImageURL {
            // Persist the book now; fetch the cover asynchronously.
            persistence.save()
            Task {
                do {
                    let rawData = try await ISBNLookupService.shared.downloadCoverImage(from: coverURL)
                    guard let imageData = CoverImage.normalizedData(from: rawData) else {
                        logger.warning("Downloaded cover for ISBN \(metadata.isbn) was not a valid image; skipping")
                        return
                    }
                    await MainActor.run {
                        // The book may be gone by now: deleted by the user (or a family
                        // member, merged in with a nil context), or rolled back by a
                        // failed save — writing to it then would crash or be lost.
                        guard !book.isGone else { return }
                        book.coverImageData = imageData
                        persistence.save()
                    }
                    logger.info("Successfully downloaded cover image for ISBN \(metadata.isbn)")
                } catch {
                    // Log the error but don't fail - book is still saved, just without cover
                    logger.warning("Failed to download cover image for ISBN \(metadata.isbn): \(error.localizedDescription)")
                }
            }
        } else {
            persistence.save()
        }
        // NewBookView dismisses itself, which runs resetScanner via handleSheetDismiss.
    }

    private func resetScanner() {
        lookupTask?.cancel()
        lookupTask = nil
        scannedCode = nil
        activeSheet = nil
        pendingAction = nil
        errorMessage = nil
        isLoading = false
        isScanning = true
    }
}

#Preview {
    ScannerTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
