//
//  BookDetailContent.swift
//  BookScan
//
//  Created by Marian Mihailescu on 30/1/2026.
//

import SwiftUI
import SwiftData

/// Shared content view for displaying and editing book details.
/// Used by both BookDetailView (sheet) and SearchBookDetailView (navigation).
struct BookDetailContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var book: Book
    let shelves: [Shelf]
    let onDelete: (() -> Void)?

    @State private var showingDeleteConfirmation = false
    @State private var showingNewShelfAlert = false
    @State private var showingLendConfirmation = false
    @State private var showingReturnConfirmation = false
    @State private var newShelfName = ""
    @State private var showingImageSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingWebSearch = false
    @State private var selectedImage: UIImage?

    init(book: Book, shelves: [Shelf], onDelete: (() -> Void)? = nil) {
        self.book = book
        self.shelves = shelves
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                bookCoverSection

                bookInfoSection

                shelfSelectionSection

                actionButtonsSection
            }
            .padding()
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
            "Lend Book",
            isPresented: $showingLendConfirmation,
            titleVisibility: .visible
        ) {
            Button("Lend") {
                lendBook()
            }
        } message: {
            Text("This book will be moved to the Lent shelf. Scan the barcode again when it's returned.")
        }
        .confirmationDialog(
            "Return Book",
            isPresented: $showingReturnConfirmation,
            titleVisibility: .visible
        ) {
            Button("Return") {
                returnBook()
            }
        } message: {
            Text("This book will be returned to its original shelf.")
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
            Button("Search the Web") {
                showingWebSearch = true
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
        .sheet(isPresented: $showingWebSearch) {
            WebCoverSearchView(
                isbn: book.isbn,
                title: book.title,
                author: book.author,
                selectedImage: $selectedImage
            )
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                book.coverImageData = image.jpegData(compressionQuality: 0.8)
                selectedImage = nil
            }
        }
    }

    // MARK: - Cover Section

    private var bookCoverSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                BookCoverImage(imageData: book.coverImageData, title: book.title, size: .large)
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
                .accessibilityLabel("Change cover image")
                .offset(x: 8, y: 8)
            }

            Text("Tap camera to change cover")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Info Section

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Shelf Selection

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

            if shelves.regularShelves.isEmpty {
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

                    ForEach(shelves.regularShelves) { shelf in
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
        let isSelected = book.shelf?.id == shelf?.id

        return Button {
            withAnimation {
                book.shelf = shelf
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
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
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Double tap to select this shelf")
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Show Return button if book is lent, otherwise show Lend button
            if book.isLent {
                // Return button (green)
                Button {
                    showingReturnConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.backward")
                        Text("Return")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Return book")
                .accessibilityHint("Double tap to return this book to its original shelf")
            } else {
                // Lend button (blue)
                Button {
                    showingLendConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward")
                        Text("Lend")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Lend book")
                .accessibilityHint("Double tap to mark this book as lent")
            }

            // Delete button
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .accessibilityLabel("Delete book")
            .accessibilityHint("Double tap to delete this book permanently")
        }
    }

    // MARK: - Actions

    private func createNewShelf() {
        guard !newShelfName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let shelf = Shelf(name: newShelfName, sortOrder: shelves.count)
        modelContext.insert(shelf)
        book.shelf = shelf
        newShelfName = ""
    }

    private func deleteBook() {
        modelContext.delete(book)

        // Force save to ensure deletion is persisted immediately
        // This prevents potential caching issues when scanning the same book again
        try? modelContext.save()

        onDelete?()
    }

    private func lendBook() {
        guard let lendingShelf = shelves.lendingShelf else { return }

        withAnimation {
            book.lend(to: lendingShelf)
        }
        dismiss()
    }

    private func returnBook() {
        withAnimation {
            book.returnBook()
        }
        dismiss()
    }
}

// MARK: - Reusable Book Cover Image

enum BookCoverSize {
    case small      // 60x90 - search results
    case medium     // 100x150 - library cards
    case large      // 150x225 - detail view

    var placeholderFont: Font {
        switch self {
        case .small: return .title3
        case .medium: return .title2
        case .large: return .largeTitle
        }
    }

    var titleFont: Font {
        switch self {
        case .small: return .caption2
        case .medium: return .caption2
        case .large: return .caption
        }
    }

    var showTitle: Bool {
        switch self {
        case .small: return false
        case .medium, .large: return true
        }
    }
}

struct BookCoverImage: View {
    let imageData: Data?
    let title: String
    let size: BookCoverSize

    var body: some View {
        if let imageData = imageData,
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
                            .font(size.placeholderFont)
                            .foregroundColor(.gray)

                        if size.showTitle {
                            Text(title)
                                .font(size.titleFont)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                    }
                }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, Shelf.self, configurations: config)

    let shelf = Shelf(name: "Fiction", sortOrder: 0)
    container.mainContext.insert(shelf)

    let book = Book(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        shelf: shelf
    )
    container.mainContext.insert(book)

    return BookDetailContent(book: book, shelves: [shelf])
        .modelContainer(container)
}
