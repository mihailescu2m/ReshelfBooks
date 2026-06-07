//
//  BookDetailContent.swift
//  BookScan
//
//  Created by Marian Mihailescu on 30/1/2026.
//

import SwiftUI

/// Shared content view for displaying and editing book details.
/// Used by both BookDetailView (sheet) and SearchBookDetailView (navigation).
struct BookDetailContent: View {
    @EnvironmentObject private var persistence: PersistenceController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var book: Book
    let shelves: [Shelf]
    let onDelete: (() -> Void)?

    // Half-sheet detent heights are computed deterministically from the button count
    // (see halfSheetHeight) rather than measured at runtime. A measured height only
    // becomes available *after* the sheet is presented, and an iPad form sheet does not
    // reliably resize once it's on screen — so it would stay stuck at its seed and clip
    // taller content (this is what cramped the cover sheet). A computed height is known
    // at presentation time, so the card is the right size immediately, on iPhone and iPad.
    //
    // The pieces are @ScaledMetric so the detent grows with Dynamic Type along with the
    // text it's sizing around.
    @ScaledMetric(relativeTo: .headline) private var sheetTitleHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var sheetMessageHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var sheetButtonHeight: CGFloat = 50
    // Single presentation binding — one .sheet(item:) avoids having multiple
    // presentation state machines on the same view, which causes the first
    // presentation to auto-dismiss (reproducible on iPad).
    @State private var activeSheet: BookDetailSheet?
    @State private var showingNewShelfAlert = false
    @State private var showingLendingShelfMissingAlert = false
    @State private var selectedImage: UIImage?
    // The cover source chosen in the picker sheet. Stashed and acted on in the
    // picker's onDismiss so we don't try to present a second sheet (camera/library/
    // web) while the picker is still dismissing.
    @State private var pendingCoverSource: CoverSource? = nil

    init(book: Book, shelves: [Shelf], onDelete: (() -> Void)? = nil) {
        self.book = book
        self.shelves = shelves
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            // If a family member deletes this book while we have it open, the object's
            // relationships fault to rows that no longer exist — rendering them would
            // crash. Render nothing and dismiss instead (see onChange below).
            if !book.isDeleted {
                VStack(spacing: 24) {
                    bookCoverSection

                    bookInfoSection

                    shelfSelectionSection

                    actionButtonsSection
                }
                .padding()
            }
        }
        .dismissWhenDeleted(book)
        .newShelfAlert(isPresented: $showingNewShelfAlert) { newShelf in
            book.shelf = newShelf
        }
        .alert("Cannot Lend Book", isPresented: $showingLendingShelfMissingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The lending shelf is not available right now. Please try again.")
        }
        // Single sheet modifier — multiple .sheet modifiers on the same view create
        // competing presentation state machines that cause the first presentation to
        // auto-dismiss (same root cause as the ScannerTabView two-sheet bug).
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            sheetContent(for: sheet)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                // Size-cap + re-encode (web-search results arrive at full resolution).
                book.coverImageData = image.coverJPEGData()
                persistence.save()
                selectedImage = nil
            }
        }
    }

    // MARK: - Cover Section

    private var bookCoverSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                BookCoverImage(imageData: book.coverImageData, title: book.title, size: .large)
                    .frame(width: 150, height: 225)
                    .cornerRadius(12)
                    .shadow(radius: 8)

                Button {
                    activeSheet = .imagePicker
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Change cover image")
                .offset(x: 8, y: 8)
            }

            Text("Tap camera to change cover")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Info Section

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
                infoRow(label: "Added", value: book.dateAdded?.formatted(date: .abbreviated, time: .omitted) ?? "—")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Shelf Selection

    private var shelfSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.accentColor)
                Text("Shelf Assignment")
                    .font(.headline)
                Spacer()

                // Hide while lent — the shelf is fixed to "Lent" until the book is
                // returned, so assigning a shelf here would leave stale state.
                if !book.isLent {
                    Button {
                        showingNewShelfAlert = true
                    } label: {
                        Label("New Shelf", systemImage: "plus")
                            .font(.subheadline)
                    }
                }
            }

            if book.isLent {
                Text("This book is lent. Use Return to move it back to its shelf.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else if shelves.regularShelves.isEmpty {
                Text("No shelves available. Create one to organize this book.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else {
                // Adaptive grid: fits as many columns as the available width allows.
                // min 260 pt → 1 column in portrait, 2+ columns in landscape and on iPad,
                // without a size-class check (which is always .compact on iPhone regardless
                // of orientation, causing a forced single-column layout in landscape).
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 8) {
                    shelfOption(nil, label: "Unshelved")
                    ForEach(shelves.regularShelves) { shelf in
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
        // Compare by object identity, not an (optional) id attribute: legacy records
        // synced from the old schema can have a nil id, which would make `nil == nil`
        // match both "Unshelved" and the real shelf at once.
        let isSelected = book.shelf == shelf

        return Button {
            withAnimation {
                book.shelf = shelf
            }
            persistence.save()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
                if let shelf = shelf {
                    let count = shelf.books?.count ?? 0
                    Text("\(count) \(count == 1 ? "book" : "books")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Double tap to select this shelf")
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Show Return button if book is lent, otherwise show Lend button
            if book.isLent {
                // Return button (green)
                Button {
                    activeSheet = .returnConfirmation
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.backward")
                        Text("Return")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Return book")
                .accessibilityHint("Double tap to return this book to its original shelf")
            } else {
                // Lend button (blue)
                Button {
                    activeSheet = .lendConfirmation
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward")
                        Text("Lend")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Lend book")
                .accessibilityHint("Double tap to mark this book as lent")
            }

            // Delete button
            Button(role: .destructive) {
                activeSheet = .deleteConfirmation
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .accessibilityLabel("Delete book")
            .accessibilityHint("Double tap to delete this book permanently")
        }
    }

    // MARK: - Actions

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Detent height for a half-sheet with a centered title + one-line message and
    /// `buttonCount` full-width pill buttons (the option buttons plus Cancel). Mirrors
    /// the layout in ConfirmationSheet / CoverSourceSheet exactly:
    ///
    ///   topPad(16) + headerTopPad(4) + title + headerSpacing(8) + message
    ///   + buttonCount × (button + outerSpacing(12)) + bottomPad(8 [+8 on iPad])
    ///
    /// Computed (not measured) so the value exists at presentation time — an iPad form
    /// sheet won't resize after it's shown, so the height must be right up front.
    private func halfSheetHeight(buttonCount: Int) -> CGFloat {
        let topPadding: CGFloat = 16 + 4
        let headerSpacing: CGFloat = 8
        let outerSpacing: CGFloat = 12
        let bottomPadding: CGFloat = 8 + (isIPad ? 8 : 0)
        let header = sheetTitleHeight + headerSpacing + sheetMessageHeight
        let buttons = CGFloat(buttonCount) * (sheetButtonHeight + outerSpacing)
        return topPadding + header + buttons + bottomPadding
    }

    @ViewBuilder
    private func sheetContent(for sheet: BookDetailSheet) -> some View {
        switch sheet {
        case .deleteConfirmation:
            ConfirmationSheet(
                title: "Delete Book",
                message: "This action cannot be undone.",
                actionLabel: "Delete",
                actionRole: .destructive,
                extraBottomPadding: isIPad ? 8 : 0
            ) { deleteBook() }
            // 2 buttons: the action + Cancel.
            .presentationDetents([.height(halfSheetHeight(buttonCount: 2))])
            .presentationCornerRadius(24)

        case .lendConfirmation:
            ConfirmationSheet(
                title: "Lend Book",
                message: "This book will be moved to the Lent shelf.",
                actionLabel: "Lend",
                actionRole: nil,
                extraBottomPadding: isIPad ? 8 : 0
            ) { lendBook() }
            .presentationDetents([.height(halfSheetHeight(buttonCount: 2))])
            .presentationCornerRadius(24)

        case .returnConfirmation:
            ConfirmationSheet(
                title: "Return Book",
                message: "This book will be returned to its original shelf.",
                actionLabel: "Return",
                actionRole: nil,
                extraBottomPadding: isIPad ? 8 : 0
            ) { returnBook() }
            .presentationDetents([.height(halfSheetHeight(buttonCount: 2))])
            .presentationCornerRadius(24)

        case .imagePicker:
            let hasCover = book.coverImageData != nil
            CoverSourceSheet(
                hasCover: hasCover,
                extraBottomPadding: isIPad ? 8 : 0
            ) { source in
                pendingCoverSource = source
                activeSheet = nil
            }
            // 3 source options + (Remove Cover when present) + Cancel.
            .presentationDetents([.height(halfSheetHeight(buttonCount: hasCover ? 5 : 4))])
            .presentationCornerRadius(24)

        case .camera:
            ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                .ignoresSafeArea()

        case .photoLibrary:
            PhotoLibraryPicker(selectedImage: $selectedImage)

        case .webSearch:
            WebCoverSearchView(
                isbn: book.isbn,
                title: book.title,
                author: book.author,
                selectedImage: $selectedImage
            )
        }
    }

    /// Called when the active sheet dismisses. For the cover-source picker the
    /// pending source is stashed here so camera/library/web opens after the picker
    /// has fully gone — never two sheets at once.
    private func handleSheetDismiss() {
        switch pendingCoverSource {
        case .camera:    activeSheet = .camera
        case .library:   activeSheet = .photoLibrary
        case .web:       activeSheet = .webSearch
        case .remove:
            book.coverImageData = nil
            persistence.save()
        case nil:
            break
        }
        pendingCoverSource = nil
    }

    private func deleteBook() {
        // Save immediately so a re-scan of the same book doesn't find a stale record.
        persistence.delete(book)
        persistence.save()
        onDelete?()
    }

    private func lendBook() {
        guard let lendingShelf = persistence.lendingShelf(creatingIfNeeded: true) else {
            // The lending shelf is created on demand; guard the edge case where it
            // can't be (e.g. no writable store) by surfacing an error, not failing silently.
            showingLendingShelfMissingAlert = true
            return
        }

        withAnimation {
            book.lend(to: lendingShelf)
        }
        persistence.save()
        dismiss()
    }

    private func returnBook() {
        withAnimation {
            book.returnBook()
        }
        persistence.save()
        dismiss()
    }
}

// MARK: - Confirmation Half-Sheet

/// A bottom half-sheet confirmation UI that avoids the confirmationDialog anchoring
/// bug (inside NavigationStack inside .sheet the system dialog renders floating/centred
/// rather than sliding up from the screen bottom).
///
/// Both the confirm and cancel actions use the same full-width pill shape.
/// The drag indicator is intentionally hidden — Cancel is the explicit exit.
private struct ConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let actionLabel: String
    let actionRole: ButtonRole?
    /// Extra bottom padding. Pass isIPad ? 8 : 0 from the parent — size-class
    /// checks inside this sheet resolve to .compact on iPad's narrow form panel.
    var extraBottomPadding: CGFloat = 0
    let onConfirm: () -> Void

    private var actionColor: Color {
        actionRole == .destructive ? .red : .accentColor
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            // Primary action
            Button(role: actionRole) {
                dismiss()
                onConfirm()
            } label: {
                Text(actionLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(actionColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Cancel — same shape, neutral grey so it reads as secondary
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8 + extraBottomPadding)
        // Pin to the top of the detent so any rounding slack between the computed
        // detent height and the rendered content lands at the bottom rather than
        // centering the content (which would leave gaps above the title and below Cancel).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Sheet Enum

/// All sheets BookDetailContent can present. Drives a single `.sheet(item:)` so
/// SwiftUI never has competing presentation state machines on the same view.
private enum BookDetailSheet: Identifiable {
    case deleteConfirmation
    case lendConfirmation
    case returnConfirmation
    case imagePicker
    case camera
    case photoLibrary
    case webSearch

    var id: String {
        switch self {
        case .deleteConfirmation:  return "deleteConfirmation"
        case .lendConfirmation:    return "lendConfirmation"
        case .returnConfirmation:  return "returnConfirmation"
        case .imagePicker:         return "imagePicker"
        case .camera:              return "camera"
        case .photoLibrary:        return "photoLibrary"
        case .webSearch:           return "webSearch"
        }
    }
}

// MARK: - Cover Source Picker Sheet

private enum CoverSource {
    case camera, library, web, remove
}

/// Action-sheet-style picker for changing a book's cover, using the same custom
/// half-sheet styling as ConfirmationSheet (so it matches Lend/Return/Delete instead
/// of the old floating confirmationDialog). Each option is a full-width pill; the
/// selection is reported via `onSelect` and performed in the parent's onDismiss.
private struct CoverSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let hasCover: Bool
    /// See ConfirmationSheet.extraBottomPadding for why this is passed from the parent.
    var extraBottomPadding: CGFloat = 0
    let onSelect: (CoverSource) -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("Change Cover Image")
                    .font(.headline)
                Text("Select image source from below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            optionButton("Take Photo") { onSelect(.camera) }
            optionButton("Choose from Library") { onSelect(.library) }
            optionButton("Search the Web") { onSelect(.web) }
            if hasCover {
                optionButton("Remove Cover", role: .destructive) { onSelect(.remove) }
            }

            // Cancel — neutral grey, matches ConfirmationSheet's Cancel.
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8 + extraBottomPadding)
        // See ConfirmationSheet — top-anchor so any rounding slack lands at the bottom
        // instead of centering the content.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func optionButton(_ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(role == .destructive ? Color.red : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Book Cover Image

enum BookCoverSize {
    case small      // 60x90 - search results
    case medium     // 100x150 - library cards
    case large      // 150x225 - detail view

    var placeholderFont: Font {
        switch self {
        case .small: return .title3
        case .medium: return .title2
        case .large: return .largeTitle
        }
    }

    var titleFont: Font {
        switch self {
        case .small: return .caption2
        case .medium: return .caption2
        case .large: return .caption
        }
    }

    var showTitle: Bool {
        switch self {
        case .small: return false
        case .medium, .large: return true
        }
    }
}

struct BookCoverImage: View {
    let imageData: Data?
    let title: String
    let size: BookCoverSize

    var body: some View {
        if let imageData = imageData,
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
                            .font(size.placeholderFont)
                            .foregroundColor(.gray)

                        if size.showTitle {
                            Text(title)
                                .font(size.titleFont)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                    }
                }
        }
    }
}

#Preview {
    let persistence = PersistenceController.preview
    let shelf = persistence.makeShelf(name: "Fiction")
    let book = persistence.makeBook(
        isbn: "9780141439518",
        title: "Pride and Prejudice",
        author: "Jane Austen",
        yearPublished: "1813",
        coverImageURL: nil,
        shelf: shelf
    )
    persistence.save()

    return BookDetailContent(book: book, shelves: [shelf])
        .environment(\.managedObjectContext, persistence.viewContext)
        .environmentObject(persistence)
}
