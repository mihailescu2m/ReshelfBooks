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

    var body: some View {
        // No NavigationStack — this view is a page inside ContentView's page-style
        // TabView (backed by UIPageViewController). Wrapping each tab in its own
        // NavigationStack nests wrapped navigation controllers, which crashes on iPad
        // (NSInternalInconsistencyException) when both pages lay out at once. The
        // toolbar is replaced by an inline header instead.
        VStack(spacing: 0) {
            header
            Divider()
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
                BookDetailView(book: book, shelves: Array(shelves))
                    .presentationDetents([.large])
                    .presentationSizing(.page)
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
    }

    private var header: some View {
        ZStack {
            Text(persistence.isLibraryShared ? "Shared Library" : "Library")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Button {
                    presentSharing()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Library")

                Spacer()

                Button {
                    showingNewShelfAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Shelf")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    isPreparingShare = false
                    if retryCount == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            presentSharing(retryCount: 1)
                        }
                    } else {
                        shareUnavailable = true
                    }
                    return
                }
                persistence.prepareShare(for: library) { share in
                    isPreparingShare = false
                    guard let share else {
                        if retryCount == 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                presentSharing(retryCount: 1)
                            }
                        } else {
                            shareUnavailable = true
                        }
                        return
                    }
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
        shelves.regularShelves.isEmpty && books.isEmpty
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

    /// The lending shelf to display, preferring the one in the same persistent store as
    /// the active library. This mirrors the store-scoping in
    /// `PersistenceController.lendingShelf` so the shelf shown in the UI is always the
    /// same shelf that receives lent books — avoiding a split-brain situation where the
    /// UI shows a private-store lending shelf (empty) while lent books land on the
    /// shared-store one (hidden).
    private var activeLendingShelf: Shelf? {
        let activeStore = persistence.activeLibrary(creatingIfNeeded: false)?.objectID.persistentStore
        let preferred = shelves
            .filter { $0.isLendingShelf && (activeStore == nil || $0.objectID.persistentStore === activeStore) }
            .min { ($0.dateCreated ?? .distantFuture) < ($1.dateCreated ?? .distantFuture) }
        return preferred ?? shelves.lendingShelf   // fallback: no store info yet
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
                ForEach(shelves.regularShelves) { shelf in
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
    }

    private var unshelvedBooks: [Book] {
        books.filter { $0.shelf == nil }
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
                Text("\(unshelvedBooks.count) \(unshelvedBooks.count == 1 ? "book" : "books")")
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
                Text("\(bookCount) \(bookCount == 1 ? "book" : "books")")
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
        .cornerRadius(12)
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
                Text("\(bookCount) \(bookCount == 1 ? "book" : "books")")
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
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
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
        .confirmationDialog(
            "Delete Shelf",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDeleteShelf()
            }
        } message: {
            Text("Books on this shelf will be moved to Unshelved.")
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
                    .cornerRadius(8)
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
