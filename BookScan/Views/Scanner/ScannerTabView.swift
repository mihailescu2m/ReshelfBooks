//
//  ScannerTabView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "Scanner")

// Enum to represent scan result for sheet presentation
enum ScanResult: Identifiable {
    case existingBook(Book, wasReturned: Bool)
    case newBook(BookMetadata)

    var id: String {
        switch self {
        case .existingBook(let book, _):
            return "existing-\(book.isbn)"
        case .newBook(let metadata):
            return "new-\(metadata.isbn)"
        }
    }
}

struct ScannerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query(sort: \Shelf.sortOrder) private var shelves: [Shelf]

    @State private var scannedCode: String?
    @State private var isScanning = true
    @State private var scanResult: ScanResult?
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
            .sheet(item: $scanResult, onDismiss: {
                resetScanner()
            }) { result in
                switch result {
                case .existingBook(let book, let wasReturned):
                    ExistingBookView(book: book, wasReturned: wasReturned, onManualEntry: {
                        scanResult = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingManualEntry = true
                        }
                    })
                case .newBook(let metadata):
                    NewBookView(metadata: metadata, shelves: shelves, onSave: { shelf in
                        saveNewBook(metadata: metadata, shelf: shelf)
                    }, onManualEntry: {
                        scanResult = nil
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
            // Check if book is currently lent and auto-return it
            if book.isLent {
                book.returnBook()
                scanResult = .existingBook(book, wasReturned: true)
            } else {
                scanResult = .existingBook(book, wasReturned: false)
            }
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
                    isLoading = false
                    scanResult = .newBook(metadata)
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
                do {
                    let imageData = try await ISBNLookupService.shared.downloadCoverImage(from: coverURL)
                    await MainActor.run {
                        book.coverImageData = imageData
                    }
                    logger.info("Successfully downloaded cover image for ISBN \(metadata.isbn)")
                } catch {
                    // Log the error but don't fail - book is still saved, just without cover
                    logger.warning("Failed to download cover image for ISBN \(metadata.isbn): \(error.localizedDescription)")
                }
            }
        }

        modelContext.insert(book)
        scanResult = nil
    }

    private func resetScanner() {
        scannedCode = nil
        scanResult = nil
        errorMessage = nil
        isScanning = true
    }
}

#Preview {
    ScannerTabView()
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
