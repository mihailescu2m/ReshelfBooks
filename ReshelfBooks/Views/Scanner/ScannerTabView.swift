//
//  ScannerTabView.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import CoreData
import AVFoundation

/// All sheets the scanner can present. A single enum drives one `.sheet(item:)`,
/// so SwiftUI never has two competing presentation state machines on the same view —
/// which causes the first presentation to be immediately dismissed on iPad.
enum ScannerSheet: Identifiable {
    // returnedFrom carries the borrower name captured *before* returnBook() cleared it,
    // so the "Returned from X" banner can name them. nil for an anonymous/non-return.
    case existingBook(Book, wasReturned: Bool, returnedFrom: String?)
    case newBook(BookMetadata)
    case manualEntry(initialISBN: String?)

    var id: String {
        switch self {
        case .existingBook(let book, _, _):
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
    /// Which camera to scan with. Defaults to the rear camera on iPhone and the front
    /// camera on iPad (where the rear camera is awkward to aim at a shelf); the header
    /// button flips between them.
    @State private var cameraPosition: AVCaptureDevice.Position =
        UIDevice.current.userInterfaceIdiom == .pad ? .front : .back
    @State private var activeSheet: ScannerSheet?
    @State private var pendingAction: PendingScannerAction?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lookupTask: Task<Void, Never>?
    /// Cover search for the book currently being looked up / previewed. Started at
    /// lookup time, handed off to the saved Book on Add (where it finishes in the
    /// background), cancelled on Cancel/reset. One pipeline per scanned new book.
    @State private var coverPipeline: CoverPipeline?

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
                ),
                cameraPosition: $cameraPosition
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

    /// Floating header overlaid on the camera (replaces the old nav-bar toolbar).
    /// Same translucent bar as every sheet — the camera feed blurs through it.
    private var header: some View {
        // Matches the Library header surface: opaque secondarySystemBackground on
        // iOS 18–25, translucent glass on iOS 26 (handled by SheetHeaderBar).
        SheetHeaderBar(title: "Scan Book", background: AnyShapeStyle(Color(.secondarySystemBackground)), trailing: {
            CircularIconButton(systemName: "arrow.triangle.2.circlepath.camera", accessibilityLabel: "Switch camera") {
                cameraPosition = (cameraPosition == .back) ? .front : .back
            }
        })
    }

    @ViewBuilder
    private func sheetContent(for sheet: ScannerSheet) -> some View {
        switch sheet {
        case .existingBook(let book, let wasReturned, let returnedFrom):
            ExistingBookView(book: book, wasReturned: wasReturned, returnedFrom: returnedFrom, onManualEntry: {
                transitionToManualEntry()
            })
            .standardSheetPresentation()
        case .newBook(let metadata):
            NewBookView(
                metadata: metadata,
                shelves: persistence.visibleOnly(shelves),
                coverPipeline: coverPipeline ?? .finished(),
                onSave: { shelf in
                    saveNewBook(metadata: metadata, shelf: shelf)
                },
                onManualEntry: {
                    transitionToManualEntry()
                }
            )
            .standardSheetPresentation()
        case .manualEntry(let isbn):
            // Use .sheet (not .fullScreenCover) so this doesn't share the parent
            // navigation context — fullScreenCover on iPad causes a crash.
            ManualISBNEntryView(initialISBN: isbn, onLookup: { lookupISBN in
                pendingAction = .lookup(lookupISBN)
                activeSheet = nil
            })
            .presentationDetents([.large])
            .standardSheetPresentation()
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var enterISBNButton: some View {
        Button {
            // Abandon any in-flight lookup: its completion would otherwise replace
            // the manual-entry sheet with a New Book sheet mid-typing.
            lookupTask?.cancel()
            lookupTask = nil
            coverPipeline?.cancel()
            coverPipeline = nil
            errorMessage = nil
            isLoading = false
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
            .clipShape(RoundedRectangle(cornerRadius: 25))
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
                // Capture the borrower before returnBook() clears it, so the banner
                // can say who returned it.
                let returnedFrom = book.borrowerName
                book.returnBook()
                persistence.save()
                activeSheet = .existingBook(book, wasReturned: true, returnedFrom: returnedFrom)
            } else {
                activeSheet = .existingBook(book, wasReturned: false, returnedFrom: nil)
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
            errorMessage = String(localized: "This barcode isn't a book ISBN.")
            scannedCode = nil
            return
        }

        isLoading = true
        errorMessage = nil

        // Start the cover search NOW: its ISBN-keyed phase needs nothing but the
        // barcode, so it races in parallel with the metadata lookup below.
        coverPipeline?.cancel()
        let pipeline = CoverPipeline()
        coverPipeline = pipeline
        pipeline.start(isbn: isbn)

        lookupTask?.cancel()
        lookupTask = Task {
            do {
                let metadata = try await ISBNLookupService.shared.lookupBook(isbn: isbn)
                await MainActor.run {
                    // Re-check cancellation *inside* the hop: a reset that lands
                    // between the await and this assignment must not resurrect a
                    // stale result.
                    guard !Task.isCancelled else { pipeline.cancel(); return }
                    pipeline.metadataArrived(metadata)
                    isLoading = false
                    activeSheet = .newBook(metadata)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { pipeline.cancel(); return }
                    // No metadata means no sheet and no book — stop the cover work.
                    pipeline.cancel()
                    isLoading = false
                    errorMessage = error.localizedDescription
                    scannedCode = nil
                    isScanning = true
                }
            }
        }
    }

    private func saveNewBook(metadata: BookMetadata, shelf: Shelf?) {
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
        persistence.save()

        // Hand the cover search to the saved book: an already-found image is written
        // immediately; otherwise the pipeline keeps running in the background and
        // attaches the cover when found — while the user scans the next book.
        // (The reference is kept until resetScanner so the still-dismissing sheet
        // doesn't re-render against a missing pipeline; attaching marks it immune
        // to the reset's cancel.)
        coverPipeline?.attach(to: book, persistence: persistence)
        // NewBookView dismisses itself, which runs resetScanner via handleSheetDismiss.
    }

    private func resetScanner() {
        lookupTask?.cancel()
        lookupTask = nil
        // A pipeline that was never handed to a saved book is abandoned — stop it.
        // An attached one keeps running in the background for its book.
        if coverPipeline?.isAttached != true {
            coverPipeline?.cancel()
        }
        coverPipeline = nil
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
