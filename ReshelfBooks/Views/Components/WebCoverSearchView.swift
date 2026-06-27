//
//  WebCoverSearchView.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 30/1/2026.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.reshelfbooks", category: "WebCoverSearch")

struct WebCoverSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let isbn: String
    let title: String
    let author: String
    @Binding var selectedImage: UIImage?

    @State private var coverURLs: [String] = []
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var loadingURLs: Set<String> = []
    @State private var isSearching = true
    @State private var selectedURL: String?
    @State private var hasSelected = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        // No NavigationStack — presented as a sheet from BookDetailContent's parent
        // NavigationStack; nesting a second one causes a fatal nav-bar conflict on iPad.
        SheetHeaderContainer {
            SheetHeaderBar(title: "Search Web", leading: {
                CircularIconButton(systemName: "xmark", accessibilityLabel: "Cancel") {
                    // Mark as selected so any in-flight download that completes
                    // after this dismiss doesn't commit its image to the parent.
                    hasSelected = true
                    dismiss()
                }
            })
        } content: {
            Group {
                if isSearching {
                    loadingView
                } else if coverURLs.isEmpty {
                    noResultsView
                } else {
                    coverGridView
                }
            }
            .scrollsBehindHeader()
            .task {
                await searchForCovers()
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching for cover images...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Cover Images Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("We couldn't find any cover images for this book.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var coverGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select a cover image")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(coverURLs, id: \.self) { url in
                        coverImageCell(url: url)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func coverImageCell(url: String) -> some View {
        Button {
            selectCover(url: url)
        } label: {
            ZStack {
                if let image = loadedImages[url] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 150)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            ProgressView()
                        }
                }

                if selectedURL == url {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 100, height: 150)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                        .background(Circle().fill(.white))
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await loadImage(from: url)
        }
    }

    // MARK: - Actions

    @MainActor
    private func searchForCovers() async {
        isSearching = true

        let urls = await ISBNLookupService.shared.searchCoverImages(
            isbn: isbn,
            title: title,
            author: author,
            maxResults: 6
        )

        coverURLs = urls
        isSearching = false
    }

    @MainActor
    private func loadImage(from url: String) async {
        // Skip if already loaded or a download for this URL is already in flight.
        // @MainActor guarantees the guard + insert run atomically (no await between
        // them), so two concurrent callers can't both start a download.
        guard loadedImages[url] == nil, !loadingURLs.contains(url) else { return }
        loadingURLs.insert(url)
        defer { loadingURLs.remove(url) }

        do {
            let data = try await ISBNLookupService.shared.downloadCoverImage(from: url)
            if let image = UIImage(data: data) {
                loadedImages[url] = image
                // If the user tapped this cover while it was still downloading,
                // commit the selection now that the image is available.
                if selectedURL == url {
                    commitSelection(url)
                }
            }
        } catch {
            logger.debug("Failed to load cover image from \(url): \(error.localizedDescription)")
            // Clear the pending selection if this was the cover the user tapped.
            if selectedURL == url {
                selectedURL = nil
            }
        }
    }

    private func selectCover(url: String) {
        // Ignore further taps once a cover has been committed (prevents two
        // selections both calling dismiss()).
        guard !hasSelected else { return }

        if loadedImages[url] != nil {
            commitSelection(url)
        } else {
            // Not loaded yet — mark it selected and make sure a load is running.
            // Whichever load finishes first (this one, or the cell's own .task)
            // commits the selection, so tapping a still-downloading cover works
            // instead of silently failing.
            selectedURL = url
            Task { await loadImage(from: url) }
        }
    }

    /// Commits the chosen cover once its image is available.
    private func commitSelection(_ url: String) {
        guard !hasSelected, let image = loadedImages[url] else { return }
        hasSelected = true
        selectedImage = image
        dismiss()
    }
}

#Preview {
    @Previewable @State var selectedImage: UIImage?

    return WebCoverSearchView(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        selectedImage: $selectedImage
    )
}
