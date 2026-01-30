//
//  WebCoverSearchView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 30/1/2026.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "WebCoverSearch")

struct WebCoverSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let isbn: String
    let title: String
    let author: String
    @Binding var selectedImage: UIImage?

    @State private var coverURLs: [String] = []
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var isSearching = true
    @State private var selectedURL: String?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    loadingView
                } else if coverURLs.isEmpty {
                    noResultsView
                } else {
                    coverGridView
                }
            }
            .navigationTitle("Search Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 150)
                        .cornerRadius(8)
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

    private func searchForCovers() async {
        isSearching = true

        let urls = await ISBNLookupService.shared.searchCoverImages(
            isbn: isbn,
            title: title,
            author: author,
            maxResults: 6
        )

        await MainActor.run {
            coverURLs = urls
            isSearching = false
        }
    }

    private func loadImage(from url: String) async {
        guard loadedImages[url] == nil else { return }

        do {
            let data = try await ISBNLookupService.shared.downloadCoverImage(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    loadedImages[url] = image
                }
            }
        } catch {
            logger.debug("Failed to load cover image from \(url): \(error.localizedDescription)")
        }
    }

    private func selectCover(url: String) {
        if let image = loadedImages[url] {
            selectedImage = image
            dismiss()
        } else {
            // Image not loaded yet, mark as selected and wait
            selectedURL = url

            Task {
                await loadImage(from: url)
                if let image = loadedImages[url] {
                    await MainActor.run {
                        selectedImage = image
                        dismiss()
                    }
                }
            }
        }
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
