//
//  EditBookDetailsView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 12/6/2026.
//

import SwiftUI

/// Re-queries every metadata source for the book's ISBN and lists each distinct
/// description, so the user can replace wrong details with one tap. The ISBN itself
/// never changes (it must keep matching the physical barcode), and there is no
/// free-text editing — the catalog sources are the only inputs.
struct EditBookDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let isbn: String
    let currentTitle: String
    let currentAuthor: String
    let currentYear: String
    /// Receives the chosen description's metadata; the parent applies and saves it.
    let onSelect: (BookMetadata) -> Void

    @State private var descriptions: [EditionDescription] = []
    @State private var isSearching = true
    @State private var hasSelected = false

    var body: some View {
        // No NavigationStack — presented as a sheet from BookDetailContent's parent
        // NavigationStack; nesting a second one causes a fatal nav-bar conflict on iPad.
        SheetHeaderContainer {
            SheetHeaderBar(title: "Edit Book", leading: {
                CircularIconButton(systemName: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            })
        } content: {
            Group {
                if isSearching {
                    loadingView
                } else if descriptions.isEmpty {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .scrollsBehindHeader()
            .task {
                descriptions = await ISBNLookupService.shared.lookupAllDescriptions(isbn: isbn)
                isSearching = false
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching book catalogs...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Details Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Couldn't find details for this ISBN.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select the correct details for ISBN \(isbn)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                LazyVStack(spacing: 12) {
                    // Index as the row id: the list is fetched once and never reordered.
                    ForEach(Array(descriptions.enumerated()), id: \.offset) { _, description in
                        descriptionRow(description)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func descriptionRow(_ description: EditionDescription) -> some View {
        let metadata = description.metadata
        let isCurrent = metadata.title == currentTitle
            && metadata.author == currentAuthor
            && metadata.yearPublished == currentYear

        return Button {
            // Ignore further taps once a description has been chosen (prevents two
            // selections both calling dismiss()).
            guard !hasSelected else { return }
            hasSelected = true
            onSelect(metadata)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metadata.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text(metadata.yearPublished)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(description.sources.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metadata.title) by \(metadata.author), \(metadata.yearPublished)\(isCurrent ? ", current details" : "")")
        .accessibilityHint("Double tap to use these details")
    }
}

#Preview {
    EditBookDetailsView(
        isbn: "9780141439518",
        currentTitle: "Pride and Prejudice",
        currentAuthor: "Jane Austen",
        currentYear: "1813"
    ) { metadata in
        print("Selected: \(metadata.title)")
    }
}
