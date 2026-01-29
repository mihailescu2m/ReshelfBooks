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
    @State private var newShelfName = ""
    @State private var selectedBook: Book?
    @State private var showingBookDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if shelves.isEmpty && books.isEmpty {
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
            .alert("New Shelf", isPresented: $showingNewShelfAlert) {
                TextField("Shelf name", text: $newShelfName)
                Button("Cancel", role: .cancel) {
                    newShelfName = ""
                }
                Button("Create") {
                    createNewShelf()
                }
            } message: {
                Text("Enter a name for the new shelf")
            }
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book, shelves: shelves)
            }
        }
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
                ForEach(shelves) { shelf in
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
        books.filter { $0.shelf == nil }
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

    private func createNewShelf() {
        guard !newShelfName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let shelf = Shelf(name: newShelfName, sortOrder: shelves.count)
        modelContext.insert(shelf)
        newShelfName = ""
    }

    private func deleteShelf(_ shelf: Shelf) {
        for book in shelf.books {
            book.shelf = nil
        }
        modelContext.delete(shelf)
    }
}

struct ShelfSectionView: View {
    let shelf: Shelf
    let onBookTap: (Book) -> Void
    let onDeleteShelf: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.accentColor)
                Text(shelf.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(shelf.books.count) books")
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

            if shelf.books.isEmpty {
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
                        ForEach(shelf.books) { book in
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
                bookCoverImage
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
    }

    @ViewBuilder
    private var bookCoverImage: some View {
        if let imageData = book.coverImageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    VStack {
                        Image(systemName: "book.closed.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text(book.title)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                }
        }
    }
}

#Preview {
    LibraryTabView()
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
