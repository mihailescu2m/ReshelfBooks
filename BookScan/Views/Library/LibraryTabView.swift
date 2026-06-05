//
//  LibraryTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct LibraryTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]
    @Query private var books: [Book]

    @State private var showingNewShelfAlert = false
    @State private var selectedBook: Book?
    @State private var showingBookDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if isLibraryEmpty {
                    emptyLibraryView
                } else {
                    libraryContentView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewShelfAlert = true
                    } label: {
                        Label("Add Shelf", systemImage: "plus")
                    }
                }
            }
            .newShelfAlert(isPresented: $showingNewShelfAlert, existingShelfCount: shelves.count)
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book, shelves: shelves)
            }
        }
    }

    /// Check if there is nothing to display anywhere: no regular shelves and no
    /// books at all (lent books still render in the lending section, so they count).
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

    private var libraryContentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Lending shelf at the top if it has books
                if let lendingShelf = shelves.lendingShelf, !(lendingShelf.books ?? []).isEmpty {
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
    }

    private var unshelvedBooks: [Book] {
        books.filter { $0.shelf == nil }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
                Text("\(unshelvedBooks.count) books")
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
        for book in shelf.books ?? [] {
            book.shelf = nil
        }
        modelContext.delete(shelf)
    }
}

// MARK: - Lending Shelf Section (special styling, no delete option)

struct LendingShelfSectionView: View {
    let shelf: Shelf
    let onBookTap: (Book) -> Void

    private var sortedBooks: [Book] {
        (shelf.books ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
                Text("\(bookCount) books")
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
    let shelf: Shelf
    let onBookTap: (Book) -> Void
    let onDeleteShelf: () -> Void

    @State private var showingDeleteConfirmation = false

    private var sortedBooks: [Book] {
        (shelf.books ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
                Text("\(bookCount) books")
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
    let book: Book
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
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
