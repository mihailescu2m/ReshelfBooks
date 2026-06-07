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

/// The card-style sheets the scanner can present. A single enum drives one
/// `.sheet(item:)`, so we never have two presentations competing during a transition.
/// ManualISBNEntryView is excluded here — it has its own separate sheet binding so
/// its corner radius can be tuned per size class (see showingManualEntry below).
enum ScannerSheet: Identifiable {
    case existingBook(Book, wasReturned: Bool)
    case newBook(BookMetadata)

    var id: String {
        switch self {
        case .existingBook(let book, _):
            return "existing-\(book.isbn)"
        case .newBook(let metadata):
            return "new-\(metadata.isbn)"
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
    // Manual ISBN entry is a full-screen cover, not a card sheet, so it gets its own
    // presentation state separate from the card-style `activeSheet`.
    @State private var showingManualEntry = false
    @State private var manualEntryISBN: String? = nil

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
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            sheetContent(for: sheet)
        }
        // Use .sheet (not .fullScreenCover) so ManualISBNEntryView's presentation
        // doesn't share the parent context — fullScreenCover on iPad shares the
        // navigation context and causes a crash. On iPhone (compact size class) we
        // remove the corner radius so it looks identical to a fullScreenCover; on
        // iPad the system default radius is kept.
        .sheet(isPresented: $showingManualEntry, onDismiss: handleManualEntryDismiss) {
            ManualISBNEntryView(initialISBN: manualEntryISBN, onLookup: { isbn in
                pendingAction = .lookup(isbn)
                showingManualEntry = false
            })
            .presentationDetents([.large])
            .presentationCornerRadius(horizontalSizeClass == .compact ? 0 : 12)
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
            NewBookView(metadata: metadata, shelves: Array(shelves), onSave: { shelf, coverImage in
                saveNewBook(metadata: metadata, shelf: shelf, coverImage: coverImage)
            }, onManualEntry: {
                transitionToManualEntry()
            })
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
            manualEntryISBN = scannedCode
            showingManualEntry = true
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
            manualEntryISBN = isbn
            showingManualEntry = true
        case .lookup(let isbn):
            pendingAction = nil
            handleScannedCode(isbn)
        case nil:
            resetScanner()
        }
    }

    private func handleManualEntryDismiss() {
        switch pendingAction {
        case .lookup(let isbn):
            pendingAction = nil
            handleScannedCode(isbn)
        case nil:
            resetScanner()
        default:
            // .showManualEntry isn't triggered from within manual entry
            pendingAction = nil
            resetScanner()
        }
    }

    // MARK: - Scan handling

    private func handleScannedCode(_ code: String) {
        if let book = books.first(where: { $0.isbn == code }) {
            // Scanning a lent book returns it (per the lending shelf's instructions).
            if book.isLent {
                book.returnBook()
                persistence.save()
                activeSheet = .existingBook(book, wasReturned: true)
            } else {
                activeSheet = .existingBook(book, wasReturned: false)
            }
        } else {
            lookupBook(isbn: code)
        }
    }

    private func lookupBook(isbn: String) {
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
                        // The user may have deleted the book while the cover downloaded.
                        guard !book.isDeleted else { return }
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
        showingManualEntry = false
        manualEntryISBN = nil
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
