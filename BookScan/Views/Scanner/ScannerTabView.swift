//
//  ScannerTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "Scanner")

/// The sheets the scanner can present. A single enum drives one `.sheet(item:)`,
/// so we never have two presentations competing during a transition.
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
        case .manualEntry:
            return "manual"
        }
    }
}

/// Work to run once the current sheet has fully dismissed. SwiftUI can't swap one
/// sheet for another in place, so we stash the follow-up and perform it in
/// `onDismiss`, which avoids the timing hacks the old two-sheet design needed.
private enum PendingScannerAction {
    case present(ScannerSheet)
    case lookup(String)
}

struct ScannerTabView: View {
    /// Whether the Scanner tab is currently visible. The camera only runs while
    /// it is, so we don't hold the camera (and show the green indicator) on other tabs.
    var isTabActive: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]

    @State private var scannedCode: String?
    @State private var isScanning = true
    @State private var activeSheet: ScannerSheet?
    @State private var pendingAction: PendingScannerAction?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lookupTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
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

                VStack {
                    enterISBNButton

                    if let error = errorMessage {
                        errorBanner(message: error)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Scan Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetScanner()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(isScanning && !isLoading)
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
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ScannerSheet) -> some View {
        switch sheet {
        case .existingBook(let book, let wasReturned):
            ExistingBookView(book: book, wasReturned: wasReturned, onManualEntry: {
                transition(to: .manualEntry(initialISBN: nil))
            })
        case .newBook(let metadata):
            NewBookView(metadata: metadata, shelves: shelves, onSave: { shelf, coverImage in
                saveNewBook(metadata: metadata, shelf: shelf, coverImage: coverImage)
            }, onManualEntry: {
                transition(to: .manualEntry(initialISBN: nil))
            })
        case .manualEntry(let initialISBN):
            ManualISBNEntryView(initialISBN: initialISBN, onLookup: { isbn in
                // Handle after this sheet is gone (see handleSheetDismiss), so the
                // result sheet can present without colliding with the dismissal.
                pendingAction = .lookup(isbn)
                activeSheet = nil
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

    /// Dismisses the current sheet, then presents `sheet` once dismissal completes.
    private func transition(to sheet: ScannerSheet) {
        pendingAction = .present(sheet)
        activeSheet = nil
    }

    private func handleSheetDismiss() {
        switch pendingAction {
        case .present(let sheet):
            pendingAction = nil
            activeSheet = sheet
        case .lookup(let isbn):
            pendingAction = nil
            handleScannedCode(isbn)
        case nil:
            resetScanner()
        }
    }

    // MARK: - Scan handling

    private func handleScannedCode(_ code: String) {
        if let book = books.first(where: { $0.isbn == code }) {
            // Scanning a lent book returns it (per the lending shelf's instructions).
            if book.isLent {
                book.returnBook()
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
        let book = Book(
            isbn: metadata.isbn,
            title: metadata.title,
            author: metadata.author,
            yearPublished: metadata.yearPublished,
            coverImageURL: metadata.coverImageURL,
            shelf: shelf
        )
        modelContext.insert(book)

        if let coverImage {
            // Reuse the image already downloaded for the preview — no second fetch.
            book.coverImageData = coverImage.coverJPEGData()
        } else if let coverURL = metadata.coverImageURL {
            // Preview hadn't finished loading yet; fetch the cover now.
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
                    }
                    logger.info("Successfully downloaded cover image for ISBN \(metadata.isbn)")
                } catch {
                    // Log the error but don't fail - book is still saved, just without cover
                    logger.warning("Failed to download cover image for ISBN \(metadata.isbn): \(error.localizedDescription)")
                }
            }
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
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
