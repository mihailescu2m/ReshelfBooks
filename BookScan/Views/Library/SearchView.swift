//
//  SearchView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if searchText.isEmpty {
                    emptySearchView
                } else if filteredBooks.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search by title, author, or ISBN...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
        .padding()
    }

    private var filteredBooks: [Book] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        return books.filter { book in
            book.title.lowercased().contains(query) ||
            book.author.lowercased().contains(query) ||
            book.isbn.lowercased().contains(query)
        }
    }

    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("Search Your Library")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Find books by title, author, or ISBN")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No books found matching \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(filteredBooks.count) result\(filteredBooks.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredBooks) { book in
                        NavigationLink {
                            SearchBookDetailView(book: book, shelves: shelves)
                        } label: {
                            SearchResultRow(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct SearchResultRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 16) {
            bookCoverImage
                .frame(width: 60, height: 90)
                .cornerRadius(6)
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "books.vertical.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(book.shelf?.name ?? "Unshelved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
                    Image(systemName: "book.closed.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
        }
    }
}

// MARK: - Book Detail View for Search (inline, no sheet)

struct SearchBookDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var book: Book
    let shelves: [Shelf]

    @State private var showingDeleteConfirmation = false
    @State private var showingNewShelfAlert = false
    @State private var newShelfName = ""
    @State private var showingImageSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var selectedImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                bookCoverSection

                bookInfoSection

                shelfSelectionSection

                deleteSection
            }
            .padding()
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
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
        .confirmationDialog(
            "Delete Book",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteBook()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            "Change Cover Image",
            isPresented: $showingImageSourcePicker,
            titleVisibility: .visible
        ) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoLibrary = true
            }
            if book.coverImageData != nil {
                Button("Remove Cover", role: .destructive) {
                    book.coverImageData = nil
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            PhotoLibraryPicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                book.coverImageData = image.jpegData(compressionQuality: 0.8)
                selectedImage = nil
            }
        }
    }

    private var bookCoverSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                bookCoverImage
                    .frame(width: 150, height: 225)
                    .cornerRadius(12)
                    .shadow(radius: 8)

                Button {
                    showingImageSourcePicker = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .offset(x: 8, y: 8)
            }

            Text("Tap camera to change cover")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text(book.title)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
        }
    }

    private var bookInfoSection: some View {
        VStack(spacing: 16) {
            Text(book.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                infoRow(label: "Author", value: book.author)
                infoRow(label: "Year", value: book.yearPublished)
                infoRow(label: "ISBN", value: book.isbn)
                infoRow(label: "Added", value: book.dateAdded.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var shelfSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.accentColor)
                Text("Shelf Assignment")
                    .font(.headline)
                Spacer()

                Button {
                    showingNewShelfAlert = true
                } label: {
                    Label("New Shelf", systemImage: "plus")
                        .font(.subheadline)
                }
            }

            if shelves.isEmpty {
                Text("No shelves available. Create one to organize this book.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    shelfOption(nil, label: "Unshelved")

                    ForEach(shelves) { shelf in
                        shelfOption(shelf, label: shelf.name)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func shelfOption(_ shelf: Shelf?, label: String) -> some View {
        Button {
            withAnimation {
                book.shelf = shelf
            }
        } label: {
            HStack {
                Image(systemName: book.shelf == shelf ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(book.shelf == shelf ? .accentColor : .secondary)
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
                if let shelf = shelf {
                    Text("\(shelf.books.count) books")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(book.shelf == shelf ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(book.shelf == shelf ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Book")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(12)
        }
    }

    private func createNewShelf() {
        guard !newShelfName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let shelf = Shelf(name: newShelfName, sortOrder: shelves.count)
        modelContext.insert(shelf)
        book.shelf = shelf
        newShelfName = ""
    }

    private func deleteBook() {
        modelContext.delete(book)
    }
}

#Preview {
    SearchView()
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
