//
//  SearchView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import CoreData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) private var books: FetchedResults<Book>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(key: "sortOrder", ascending: true),
        NSSortDescriptor(key: "dateCreated", ascending: true),
        NSSortDescriptor(key: "name", ascending: true)
    ])
    private var shelves: FetchedResults<Shelf>

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    // Debounce delay in milliseconds
    private let debounceDelay: UInt64 = 300_000_000 // 300ms in nanoseconds

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if debouncedSearchText.isEmpty {
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
            .onChange(of: searchText) { _, newValue in
                debounceSearch(newValue)
            }
        }
    }

    // MARK: - Debounced Search

    private func debounceSearch(_ query: String) {
        // Cancel any existing search task
        searchTask?.cancel()

        // If empty, update immediately
        if query.isEmpty {
            debouncedSearchText = ""
            return
        }

        // Capture the query value to compare after sleep
        let capturedQuery = query

        // Create new debounced task
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)

                // Double-check: only update if the query hasn't changed
                // and the task wasn't cancelled
                guard !Task.isCancelled, searchText == capturedQuery else {
                    return
                }

                debouncedSearchText = capturedQuery
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search by title, author, or ISBN...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search field")
                    .accessibilityHint("Enter title, author, or ISBN to search")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        debouncedSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
        .padding()
    }

    // MARK: - Filtered Results

    private var filteredBooks: [Book] {
        let query = debouncedSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        return books.filter { book in
            book.title.lowercased().contains(query) ||
            book.author.lowercased().contains(query) ||
            book.isbn.lowercased().contains(query)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Empty State Views

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search your library by title, author, or ISBN")
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

            Text("No books found matching \"\(debouncedSearchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found for \(debouncedSearchText)")
    }

    // MARK: - Results List

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
                            SearchBookDetailView(book: book, shelves: Array(shelves))
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

// MARK: - Search Result Row

struct SearchResultRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 16) {
            BookCoverImage(imageData: book.coverImageData, title: book.title, size: .small)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author), on shelf \(book.shelf?.name ?? "Unshelved")")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Search Book Detail View (inline navigation)

struct SearchBookDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var book: Book
    let shelves: [Shelf]

    var body: some View {
        BookDetailContent(book: book, shelves: shelves) {
            dismiss()
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SearchView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
