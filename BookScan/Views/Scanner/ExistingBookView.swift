//
//  ExistingBookView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct ExistingBookView: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let onManualEntry: (() -> Void)?

    // Quick Scan Mode
    private let autoDismissSeconds: Double = 3.0
    @State private var timeRemaining: Double = 3.0
    @State private var isAutoDismissActive = true
    @State private var timer: Timer?

    init(book: Book, onManualEntry: (() -> Void)? = nil) {
        self.book = book
        self.onManualEntry = onManualEntry
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Book Found!")
                    .font(.title)
                    .fontWeight(.bold)

                bookInfoCard

                notRightBookLink

                shelfLocationCard

                Spacer()

                if isAutoDismissActive {
                    countdownSection
                } else {
                    doneButton
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                cancelAutoDismiss()
            }
            .navigationTitle("Book Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                startAutoDismissTimer()
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }

    private var countdownSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)

                // Progress circle
                Circle()
                    .trim(from: 0, to: timeRemaining / autoDismissSeconds)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: timeRemaining)

                // Countdown number
                Text("\(Int(ceil(timeRemaining)))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Text("Tap to keep open")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    private func startAutoDismissTimer() {
        timeRemaining = autoDismissSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 0.1
            } else {
                timer?.invalidate()
                dismiss()
            }
        }
    }

    private func cancelAutoDismiss() {
        timer?.invalidate()
        withAnimation {
            isAutoDismissActive = false
        }
    }

    private var bookInfoCard: some View {
        HStack(spacing: 16) {
            bookCoverImage
                .frame(width: 80, height: 120)
                .cornerRadius(8)
                .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(book.yearPublished)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("ISBN: \(book.isbn)")
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
    private var bookCoverImage: some View {
        if let imageData = book.coverImageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
        }
    }

    private var shelfLocationCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text("Place this book on:")
                    .font(.headline)

                Spacer()
            }

            if let shelf = book.shelf {
                HStack {
                    Text(shelf.name)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    Spacer()
                }
            } else {
                HStack {
                    Text("No shelf assigned")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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

    return ExistingBookView(book: book)
        .modelContainer(container)
}
