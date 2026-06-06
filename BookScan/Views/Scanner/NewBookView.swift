//
//  NewBookView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "NewBook")

struct NewBookView: View {
    @Environment(\.dismiss) private var dismiss

    let metadata: BookMetadata
    let shelves: [Shelf]
    /// Receives the chosen shelf and the already-loaded cover image (if the
    /// preview finished downloading), so the cover isn't fetched a second time.
    let onSave: (Shelf?, UIImage?) -> Void
    let onManualEntry: (() -> Void)?

    init(metadata: BookMetadata, shelves: [Shelf], onSave: @escaping (Shelf?, UIImage?) -> Void, onManualEntry: (() -> Void)? = nil) {
        self.metadata = metadata
        self.shelves = shelves
        self.onSave = onSave
        self.onManualEntry = onManualEntry
    }

    @State private var selectedShelf: Shelf?
    @State private var showingNewShelfAlert = false
    @State private var coverImage: UIImage?
    @State private var isLoadingImage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    bookInfoSection

                    notRightBookLink

                    shelfSelectionSection

                    Spacer(minLength: 20)

                    saveButton
                }
                .padding()
            }
            .navigationTitle("New Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .newShelfAlert(isPresented: $showingNewShelfAlert) { newShelf in
                selectedShelf = newShelf
            }
            .task {
                await loadCoverImage()
            }
        }
    }

    private var headerSection: some View {
        Text("Add to Library")
            .font(.title2)
            .fontWeight(.bold)
    }

    private var bookInfoSection: some View {
        HStack(spacing: 16) {
            coverImageView
                .frame(width: 100, height: 150)
                .cornerRadius(8)
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(metadata.title)
                    .font(.headline)
                    .lineLimit(3)

                Text(metadata.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(metadata.yearPublished)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("ISBN: \(metadata.isbn)")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var notRightBookLink: some View {
        if let onManualEntry = onManualEntry {
            Button {
                onManualEntry()
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("Not the right book? Enter ISBN manually")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
        }
    }

    @ViewBuilder
    private var coverImageView: some View {
        if isLoadingImage {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    ProgressView()
                }
        } else if let image = coverImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            BookCoverImage(imageData: nil, title: metadata.title, size: .medium)
        }
    }

    private var shelfSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.accentColor)
                Text("Select Shelf")
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
                Text("No shelves yet. Create one to organize your books.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                    ForEach(shelves.regularShelves) { shelf in
                        shelfButton(shelf)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func shelfButton(_ shelf: Shelf) -> some View {
        Button {
            selectedShelf = shelf
        } label: {
            HStack {
                Image(systemName: selectedShelf == shelf ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedShelf == shelf ? .accentColor : .secondary)
                Text(shelf.name)
                    .lineLimit(1)
                Spacer()
            }
            .padding()
            .background(selectedShelf == shelf ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedShelf == shelf ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            onSave(selectedShelf, coverImage)
            dismiss()
        } label: {
            Text("Add to Library")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    private func loadCoverImage() async {
        guard let urlString = metadata.coverImageURL else { return }

        isLoadingImage = true
        defer { isLoadingImage = false }

        do {
            let data = try await ISBNLookupService.shared.downloadCoverImage(from: urlString)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    coverImage = image
                }
            }
        } catch {
            logger.warning("Failed to load cover image for ISBN \(metadata.isbn): \(error.localizedDescription)")
        }
    }
}

#Preview {
    let metadata = BookMetadata(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        coverImageURL: nil
    )

    return NewBookView(metadata: metadata, shelves: []) { _, _ in }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
