//
//  NewBookView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

struct NewBookView: View {
    @Environment(\.dismiss) private var dismiss

    let metadata: BookMetadata
    let shelves: [Shelf]
    /// The cover search running since scan time (owned by ScannerTabView). The
    /// preview fills in whenever it finds an image — this sheet never waits for it,
    /// and the search continues in the background after the book is saved.
    @ObservedObject var coverPipeline: CoverPipeline
    /// Receives the chosen shelf; the cover is attached by the pipeline.
    let onSave: (Shelf?) -> Void
    let onManualEntry: (() -> Void)?

    init(
        metadata: BookMetadata,
        shelves: [Shelf],
        coverPipeline: CoverPipeline,
        onSave: @escaping (Shelf?) -> Void,
        onManualEntry: (() -> Void)? = nil
    ) {
        self.metadata = metadata
        self.shelves = shelves
        self.coverPipeline = coverPipeline
        self.onSave = onSave
        self.onManualEntry = onManualEntry
    }

    @State private var selectedShelf: Shelf?
    @State private var showingNewShelfAlert = false

    var body: some View {
        // No NavigationStack — presented as a sheet from ScannerTabView's NavigationStack;
        // nesting a second one causes a fatal nav-bar conflict on iPad.
        SheetHeaderContainer {
            SheetHeaderBar(title: "New Book", leading: {
                CircularIconButton(systemName: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            })
        } content: {
            ScrollView {
                VStack(spacing: 24) {
                    bookInfoSection

                    notRightBookLink

                    shelfSelectionSection

                    Spacer(minLength: 20)

                    saveButton
                }
                .padding()
            }
            .scrollsBehindHeader()
            .newShelfAlert(isPresented: $showingNewShelfAlert) { newShelf in
                selectedShelf = newShelf
            }
        }
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
        if let image = coverPipeline.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else if coverPipeline.isSearching {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    ProgressView()
                }
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
                // Same adaptive grid as BookDetailContent's Shelf Assignment, so the
                // column count matches across both screens at the same width.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 8) {
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
            onSave(selectedShelf)
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
}

#Preview {
    let metadata = BookMetadata(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        coverImageURL: nil
    )

    return NewBookView(metadata: metadata, shelves: [], coverPipeline: .finished()) { _ in }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
