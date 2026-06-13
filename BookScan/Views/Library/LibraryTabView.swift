//
//  LibraryTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import CoreData

struct LibraryTabView: View {
    @EnvironmentObject private var persistence: PersistenceController

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            // Deterministic tiebreaks so all devices order shelves identically even
            // when two of them pick the same sortOrder concurrently.
            NSSortDescriptor(key: "dateCreated", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ],
        animation: .default
    ) private var shelves: FetchedResults<Shelf>

    @FetchRequest(sortDescriptors: [], animation: .default)
    private var books: FetchedResults<Book>

    @State private var showingNewShelfAlert = false
    @State private var selectedBook: Book?
    @State private var isPreparingShare = false
    @State private var shareUnavailable = false

    // Active-store filter: while participating in a shared library only its shelves
    // and books are shown; the user's own private books stay parked out of sight
    // until the share ends (and Core Data forbids relating objects across stores).
    private var visibleShelves: [Shelf] { persistence.visibleOnly(shelves) }
    private var visibleBooks: [Book] { persistence.visibleOnly(books) }

    var body: some View {
        // No NavigationStack — this view is a page inside ContentView's page-style
        // TabView (backed by UIPageViewController). Wrapping each tab in its own
        // NavigationStack nests wrapped navigation controllers, which crashes on iPad
        // (NSInternalInconsistencyException) when both pages lay out at once. The
        // toolbar is replaced by a floating header instead.
        SheetHeaderContainer {
            header
        } content: {
            Group {
                if isLibraryEmpty {
                    emptyLibraryView
                } else {
                    libraryContentView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .newShelfAlert(isPresented: $showingNewShelfAlert)
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book, shelves: visibleShelves)
                    .presentationDetents([.large])
                    .presentationSizing(.page)
                    .standardSheetPresentation()
            }
            .onAppear {
                persistence.refreshSharedState()
            }
            .alert("Sharing Unavailable", isPresented: $shareUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Family sharing needs iCloud. Make sure you're signed into iCloud in Settings, then try again.")
            }
        }
        // Elevated gray (matches the system share sheet) instead of pure black, so
        // the translucent header reads as a seamless region of the same surface.
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
    }

    private var header: some View {
        SheetHeaderBar(
            title: persistence.isLibraryShared ? "Shared Library" : "Library",
            // Same surface as the page background, so the bar is seamless.
            background: AnyShapeStyle(Color(.secondarySystemBackground)),
            leading: {
                CircularIconButton(systemName: "square.and.arrow.up", glyphYOffset: -2, accessibilityLabel: "Share Library") {
                    presentSharing()
                }
            },
            trailing: {
                CircularIconButton(systemName: "plus", accessibilityLabel: "Add Shelf") {
                    showingNewShelfAlert = true
                }
            }
        )
    }

    /// Opens the family-sharing sheet. Resolves (creating if needed) the library and
    /// its share when invoked, so we never create objects as a side effect of rendering.
    ///
    /// - Parameter retryCount: Internal retry depth — callers always use the default (0).
    private func presentSharing(retryCount: Int = 0) {
        // Guard against a double-tap kicking off a second container.share() before the
        // first finishes — that would create a duplicate share zone.
        guard !isPreparingShare else { return }
        guard let library = persistence.activeLibrary(creatingIfNeeded: true) else { return }
        isPreparingShare = true

        // Check CloudKit account status before attempting to create the share.
        //
        // On first launch (especially from TestFlight / a fresh install in the Production
        // CloudKit environment), both accountStatus and container.share() can transiently
        // fail with CKError.notAuthenticated even when the user IS signed in — the auth
        // token simply hasn't been fetched yet. bootstrap() fires a pre-warm, but if the
        // user taps Share before that completes we'd show a spurious "sign in" alert.
        //
        // Strategy: if either check fails on the first attempt, retry once silently after
        // a short delay (giving CloudKit time to finish its handshake). Only surface the
        // "Sharing Unavailable" alert on a second consecutive failure, which indicates a
        // genuine problem (actually not signed in, no network, etc.).
        persistence.ckContainer.accountStatus { status, _ in
            DispatchQueue.main.async {
                guard status == .available else {
                    if retryCount == 0 {
                        // Keep isPreparingShare true through the retry window so a
                        // second tap can't start an overlapping share flow meanwhile.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isPreparingShare = false
                            presentSharing(retryCount: 1)
                        }
                    } else {
                        isPreparingShare = false
                        shareUnavailable = true
                    }
                    return
                }
                persistence.prepareShare(for: library) { share in
                    guard let share else {
                        if retryCount == 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isPreparingShare = false
                                presentSharing(retryCount: 1)
                            }
                        } else {
                            isPreparingShare = false
                            shareUnavailable = true
                        }
                        return
                    }
                    isPreparingShare = false
                    SharingPresenter.present(
                        share: share,
                        container: persistence.ckContainer,
                        persistence: persistence
                    )
                }
            }
        }
    }

    /// Nothing to display anywhere: no regular shelves and no books at all
    /// (lent books still render in the lending section, so they count).
    private var isLibraryEmpty: Bool {
        visibleShelves.regularShelves.isEmpty && visibleBooks.isEmpty
    }

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Scan book barcodes to add them to your library")
        } actions: {
            Button {
                showingNewShelfAlert = true
            } label: {
                Text("Create a Shelf")
            }
        }
    }

    /// The lending shelf to display. `visibleShelves` is already scoped to the active
    /// library's store — the same scoping `PersistenceController.lendingShelf` uses —
    /// so the shelf shown here is always the one that receives lent books.
    private var activeLendingShelf: Shelf? {
        visibleShelves.lendingShelf
    }

    private var libraryContentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Lending shelf at the top if it has books
                if let lendingShelf = activeLendingShelf, !(lendingShelf.books ?? []).isEmpty {
                    LendingShelfSectionView(
                        shelf: lendingShelf,
                        onBookTap: { book in
                            selectedBook = book
                        }
                    )
                }

                // Regular shelves
                ForEach(visibleShelves.regularShelves) { shelf in
                    ShelfSectionView(
                        shelf: shelf,
                        onBookTap: { book in
                            selectedBook = book
                        },
                        onDeleteShelf: {
                            deleteShelf(shelf)
                        }
                    )
                }

                if !unshelvedBooks.isEmpty {
                    unshelvedBooksSection
                }
            }
            .padding()
        }
        // Clear the floating tab bar (overlaid by ContentView) so the last shelf/book
        // can scroll above it instead of being hidden behind it.
        .contentMargins(.bottom, 90, for: .scrollContent)
        // Shelves scroll behind the floating header and blur through it.
        .scrollsBehindHeader()
    }

    private var unshelvedBooks: [Book] {
        visibleBooks.filter { $0.shelf == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var unshelvedBooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundColor(.secondary)
                Text("Unshelved")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("^[\(unshelvedBooks.count) book](inflect: true)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(unshelvedBooks) { book in
                        BookCardView(book: book) {
                            selectedBook = book
                        }
                    }
                }
            }
        }
    }

    private func deleteShelf(_ shelf: Shelf) {
        for book in shelf.bookList {
            book.shelf = nil
        }
        persistence.delete(shelf)
        persistence.save()
    }
}

// MARK: - Lending Shelf Section (special styling, no delete option)

struct LendingShelfSectionView: View {
    @ObservedObject var shelf: Shelf
    let onBookTap: (Book) -> Void

    private var sortedBooks: [Book] {
        shelf.bookList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var bookCount: Int {
        shelf.books?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .foregroundColor(.orange)
                Text(shelf.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("^[\(bookCount) book](inflect: true)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Scan a book's barcode to return it")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(sortedBooks) { book in
                        BookCardView(book: book) {
                            onBookTap(book)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Regular Shelf Section

struct ShelfSectionView: View {
    @ObservedObject var shelf: Shelf
    let onBookTap: (Book) -> Void
    let onDeleteShelf: () -> Void

    @State private var showingDeleteConfirmation = false

    private var sortedBooks: [Book] {
        shelf.bookList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var bookCount: Int {
        shelf.books?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.accentColor)
                Text(shelf.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("^[\(bookCount) book](inflect: true)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Menu {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Shelf", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }

            if (shelf.books ?? []).isEmpty {
                Text("No books on this shelf")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    // One level above the tab's secondarySystemBackground surface.
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(sortedBooks) { book in
                            BookCardView(book: book) {
                                onBookTap(book)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingDeleteConfirmation) {
            ConfirmationSheet(
                title: "Delete Shelf",
                message: "Books on this shelf will be moved to Unshelved.",
                actionLabel: "Delete",
                actionRole: .destructive,
                bottomPadding: SheetMetrics.defaultBottomPadding
            ) {
                onDeleteShelf()
            }
        }
    }
}

struct BookCardView: View {
    @ObservedObject var book: Book
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                BookCoverImage(imageData: book.coverImageData, title: book.title, size: .medium)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(book.author)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author)")
        .accessibilityHint("Double tap to view details")
    }
}

#Preview {
    LibraryTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
