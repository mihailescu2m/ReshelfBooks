//
//  ScannerTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct ScannerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]

    @State private var scannedCode: String?
    @State private var isScanning = true
    @State private var showingResult = false
    @State private var existingBook: Book?
    @State private var newBookMetadata: BookMetadata?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingManualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeScannerView(scannedCode: $scannedCode, isScanning: $isScanning)
                    .ignoresSafeArea()

                if isLoading {
                    loadingOverlay
                }

                VStack {
                    enterISBNButton

                    if let error = errorMessage {
                        errorBanner(message: error)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Scan Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetScanner()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(isScanning && !isLoading)
                }
            }
            .onChange(of: scannedCode) { oldValue, newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
            .sheet(isPresented: $showingResult) {
                resetScanner()
            } content: {
                if let book = existingBook {
                    ExistingBookView(book: book, onManualEntry: {
                        showingResult = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingManualEntry = true
                        }
                    })
                } else if let metadata = newBookMetadata {
                    NewBookView(metadata: metadata, shelves: shelves, onSave: { shelf in
                        saveNewBook(metadata: metadata, shelf: shelf)
                    }, onManualEntry: {
                        showingResult = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingManualEntry = true
                        }
                    })
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                resetScanner()
            } content: {
                ManualISBNEntryView(
                    initialISBN: scannedCode,
                    onLookup: { isbn in
                        showingManualEntry = false
                        scannedCode = isbn
                        handleScannedCode(isbn)
                    }
                )
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Looking up book...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .foregroundColor(.white)
            Spacer()
            Button {
                errorMessage = nil
                resetScanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .cornerRadius(12)
    }

    private var enterISBNButton: some View {
        Button {
            isScanning = false
            showingManualEntry = true
        } label: {
            HStack {
                Image(systemName: "keyboard")
                Text("Enter ISBN")
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(25)
        }
        .padding(.top, 20)
    }

    private func handleScannedCode(_ code: String) {
        if let book = books.first(where: { $0.isbn == code }) {
            existingBook = book
            showingResult = true
        } else {
            lookupBook(isbn: code)
        }
    }

    private func lookupBook(isbn: String) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let metadata = try await ISBNLookupService.shared.lookupBook(isbn: isbn)
                await MainActor.run {
                    newBookMetadata = metadata
                    isLoading = false
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    scannedCode = nil
                    isScanning = true
                }
            }
        }
    }

    private func saveNewBook(metadata: BookMetadata, shelf: Shelf?) {
        let book = Book(
            isbn: metadata.isbn,
            title: metadata.title,
            author: metadata.author,
            yearPublished: metadata.yearPublished,
            coverImageURL: metadata.coverImageURL,
            shelf: shelf
        )

        if let coverURL = metadata.coverImageURL {
            Task {
                if let imageData = try? await ISBNLookupService.shared.downloadCoverImage(from: coverURL) {
                    await MainActor.run {
                        book.coverImageData = imageData
                    }
                }
            }
        }

        modelContext.insert(book)
        showingResult = false
    }

    private func resetScanner() {
        scannedCode = nil
        existingBook = nil
        newBookMetadata = nil
        errorMessage = nil
        isScanning = true
    }
}

#Preview {
    ScannerTabView()
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
