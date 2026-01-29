//
//  BookDetailView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
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
    }

    private var bookCoverSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                bookCoverImage
                    .frame(width: 150, height: 225)
                    .cornerRadius(12)
                    .shadow(radius: 8)

                // Camera button overlay
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
        dismiss()
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

    return BookDetailView(book: book, shelves: [shelf])
        .modelContainer(container)
}
