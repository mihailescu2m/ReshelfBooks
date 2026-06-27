//
//  BookDetailContent.swift
//  ReshelfBooks
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
            if !book.isGone {
                VStack(spacing: 24) {
                    bookCoverSection

                    bookInfoSection

                    shelfSelectionSection

                    actionButtonsSection
                }
                .padding()
            }
        }
        .scrollsBehindHeader()
        .dismissWhenDeleted(book)
        .newShelfAlert(isPresented: $showingNewShelfAlert) { newShelf in
            book.shelf = newShelf
            // Land at the end of the new shelf's manual order (matches the shelf picker).
            book.sortOrder = persistence.nextSortOrder(in: newShelf, excluding: book)
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
            BookCoverImage(imageData: book.coverImageData, title: book.title, size: .large)
                .frame(width: 150, height: 225)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                .overlay(alignment: .topTrailing) {
                    coverButton(icon: "pencil", accessibilityLabel: "Edit book details") {
                        activeSheet = .editMetadata
                    }
                    .offset(x: 8, y: -8)
                }
                .overlay(alignment: .bottomTrailing) {
                    coverButton(icon: "camera.fill", accessibilityLabel: "Change cover image") {
                        activeSheet = .imagePicker(hasCover: book.coverImageData != nil)
                    }
                    .offset(x: 8, y: 8)
                }

            Text("Tap camera to change cover, pencil to edit details")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// The circular accent buttons pinned to the cover's corners.
    private func coverButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .accessibilityLabel(accessibilityLabel)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                lentStatusBanner
            } else if shelves.regularShelves.isEmpty {
                Text("No shelves available. Create one to organize this book.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Shown in place of the shelf grid while a book is lent: who has it (if named)
    /// and how long ago, plus the reminder to use Return.
    private var lentStatusBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(book.borrowerName.map { String(localized: "Lent to \($0)") }
                     ?? String(localized: "This book is lent"))
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "person.fill")
                    .foregroundColor(.accentColor)
            }
            .font(.subheadline)

            if let lentDate = book.dateLent {
                Text("Lent \(lentDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Use Return to move it back to its shelf.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func shelfOption(_ shelf: Shelf?, label: String) -> some View {
        // Compare by object identity, not an (optional) id attribute: legacy records
        // synced from the old schema can have a nil id, which would make `nil == nil`
        // match both "Unshelved" and the real shelf at once.
        let isSelected = book.shelf == shelf

        return Button {
            withAnimation {
                book.shelf = shelf
                // Land at the end of the new shelf's manual order.
                if let shelf { book.sortOrder = persistence.nextSortOrder(in: shelf, excluding: book) }
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
                    Text("^[\(count) book](inflect: true)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Delete book")
            .accessibilityHint("Double tap to delete this book permanently")
        }
    }

    // MARK: - Actions

    /// Bottom padding inside the half-sheets — shared device logic on SheetMetrics.
    private var sheetBottomPadding: CGFloat { SheetMetrics.defaultBottomPadding }

    @ViewBuilder
    private func sheetContent(for sheet: BookDetailSheet) -> some View {
        switch sheet {
        case .deleteConfirmation:
            ConfirmationSheet(
                title: "Delete Book",
                message: "This action cannot be undone.",
                actionLabel: "Delete",
                actionRole: .destructive,
                bottomPadding: sheetBottomPadding
            ) { deleteBook() }

        case .lendConfirmation:
            LendSheet(recentBorrowers: persistence.recentBorrowers()) { borrower in
                lendBook(borrower: borrower)
            }

        case .returnConfirmation:
            ConfirmationSheet(
                title: "Return Book",
                message: "This book will be returned to its original shelf.",
                actionLabel: "Return",
                actionRole: nil,
                // Green to match the green Return button that opens this sheet.
                actionTint: .green,
                bottomPadding: sheetBottomPadding
            ) { returnBook() }

        case .imagePicker(let hasCover):
            CoverSourceSheet(
                hasCover: hasCover,
                bottomPadding: sheetBottomPadding
            ) { source in
                pendingCoverSource = source
                activeSheet = nil
            }

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
            .standardSheetPresentation()

        case .editMetadata:
            EditBookDetailsView(
                isbn: book.isbn,
                currentTitle: book.title,
                currentAuthor: book.author,
                currentYear: book.yearPublished
            ) { metadata in
                // The ISBN stays as-is: it must keep matching the physical barcode.
                guard !book.isGone else { return }
                book.title = metadata.title
                book.author = metadata.author
                book.yearPublished = metadata.yearPublished
                persistence.save()
            }
            .standardSheetPresentation()
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

    private func lendBook(borrower: String) {
        guard let lendingShelf = persistence.lendingShelf(creatingIfNeeded: true) else {
            // The lending shelf is created on demand; guard the edge case where it
            // can't be (e.g. no writable store) by surfacing an error, not failing silently.
            showingLendingShelfMissingAlert = true
            return
        }

        withAnimation {
            book.lend(to: lendingShelf, borrower: borrower)
        }
        // Remember the name for the Lend sheet's quick-tap chips next time.
        persistence.recordBorrower(borrower)
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
///
/// Sizing: every element is pinned to a fixed height (see SheetMetrics) and the `.height`
/// detent is computed from those exact heights, so the card fits the content with no slack.
/// The earlier gap came from computing the detent from constants while letting the elements
/// render at their smaller *natural* heights — here the elements are forced to match.
struct ConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let metrics = SheetMetrics()

    let title: String
    let message: String
    let actionLabel: String
    let actionRole: ButtonRole?
    /// Overrides the default action-button fill (so Return can use green to match its
    /// green action-row button). nil falls back to the role-based default.
    var actionTint: Color? = nil
    /// Bottom padding inside the card. Computed by the parent (see sheetBottomPadding) so it
    /// doesn't double up on the home-indicator safe area.
    var bottomPadding: CGFloat = 0
    let onConfirm: () -> Void

    private var actionColor: Color {
        actionTint ?? (actionRole == .destructive ? .red : .accentColor)
    }

    var body: some View {
        VStack(spacing: SheetMetrics.outerSpacing) {
            metrics.header(title: title, message: message)

            metrics.pillButton(actionLabel, fill: actionColor, weight: .semibold, role: actionRole) {
                dismiss()
                onConfirm()
            }

            // Cancel — neutral grey so it reads as secondary.
            metrics.pillButton("Cancel", fill: Color(.systemGray5), foreground: .primary, weight: .medium) {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, SheetMetrics.topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity)
        // 2 buttons: the action + Cancel.
        .presentationDetents([.height(metrics.height(buttonCount: 2, bottomPadding: bottomPadding))])
        .presentationCornerRadius(24)
        .presentationBackground { Color(.systemBackground).ignoresSafeArea() }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Shared Half-Sheet Metrics

/// Fixed-height building blocks shared by ConfirmationSheet and CoverSourceSheet, plus the
/// matching detent-height calculation. Because the views and the calculation use the *same*
/// constants — and every element is pinned to those heights — the computed `.height` detent
/// equals the rendered content exactly, so there's no dead space.
///
/// The text/button heights are @ScaledMetric so they grow with Dynamic Type along with the
/// content; titles and messages are kept to one line (shrinking slightly if needed) so their
/// height stays fixed and the math stays exact. Conforms to DynamicProperty so SwiftUI keeps
/// the @ScaledMetric values updated even though this lives as a plain property of the sheet.
struct SheetMetrics: DynamicProperty {
    static let topPadding: CGFloat = 20      // space above the title
    static let headerSpacing: CGFloat = 8    // title ↔ message
    static let outerSpacing: CGFloat = 12    // between header and each button

    /// Bottom padding for the half-sheets, by device — shared by every confirmation
    /// half-sheet. iPad: a fixed pad balances the centered card. Face-ID iPhone: 0
    /// (the system reserves the home-indicator strip). Touch-ID iPhone (no indicator):
    /// a small pad so the last pill isn't flush.
    static var defaultBottomPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad { return 24 }
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
        return bottomInset > 0 ? 0 : 16
    }

    // .title3 matches the main sheet headers (SheetHeaderBar); the height tracks it.
    @ScaledMetric(relativeTo: .title3) var titleHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .subheadline) var messageHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .body) var buttonHeight: CGFloat = 50

    /// Detent height = top padding + header + buttonCount×(button + spacing) + bottom padding.
    func height(buttonCount: Int, bottomPadding: CGFloat) -> CGFloat {
        let header = titleHeight + Self.headerSpacing + messageHeight
        let buttons = CGFloat(buttonCount) * (buttonHeight + Self.outerSpacing)
        return Self.topPadding + header + buttons + bottomPadding
    }

    /// Centered title + one-line message, each pinned to a fixed height.
    func header(title: String, message: String) -> some View {
        VStack(spacing: Self.headerSpacing) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: titleHeight)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: messageHeight)
        }
    }

    /// Full-width pill button of fixed height.
    func pillButton(
        _ label: String,
        fill: Color,
        foreground: Color = .white,
        weight: Font.Weight,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(label)
                .font(.body.weight(weight))
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(fill)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet Enum

/// All sheets BookDetailContent can present. Drives a single `.sheet(item:)` so
/// SwiftUI never has competing presentation state machines on the same view.
private enum BookDetailSheet: Identifiable {
    case deleteConfirmation
    case lendConfirmation
    case returnConfirmation
    // hasCover is captured at tap time so every sheetContent re-evaluation
    // (including SwiftUI reconciliation passes) uses the same stable value.
    // Reading book.coverImageData inside sheetContent instead would race with
    // async cover downloads: the view reconciles (no Remove Cover button) but
    // presentationDetents on an already-presented sheet stays locked at the
    // stale height.
    case imagePicker(hasCover: Bool)
    case camera
    case photoLibrary
    case webSearch
    case editMetadata

    var id: String {
        switch self {
        case .deleteConfirmation:       return "deleteConfirmation"
        case .lendConfirmation:         return "lendConfirmation"
        case .returnConfirmation:       return "returnConfirmation"
        case .imagePicker(let hasCover): return "imagePicker-\(hasCover)"
        case .camera:                   return "camera"
        case .photoLibrary:             return "photoLibrary"
        case .webSearch:                return "webSearch"
        case .editMetadata:             return "editMetadata"
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
    private let metrics = SheetMetrics()

    let hasCover: Bool
    /// See ConfirmationSheet.bottomPadding for why this is passed from the parent.
    var bottomPadding: CGFloat = 0
    let onSelect: (CoverSource) -> Void

    /// 3 source options + (Remove Cover when present) + Cancel.
    private var buttonCount: Int { hasCover ? 5 : 4 }

    var body: some View {
        VStack(spacing: SheetMetrics.outerSpacing) {
            metrics.header(title: "Change Cover Image", message: "Select image source from below.")

            // Faint tinted fills with colored text — accent for the source options,
            // red for Remove Cover. Medium weight matches Cancel, so the half-sheet
            // family uses just two weights (medium here, semibold for the prominent
            // confirm actions in ConfirmationSheet).
            metrics.pillButton("Take Photo", fill: .accentColor.opacity(0.1), foreground: .accentColor, weight: .medium) { onSelect(.camera) }
            metrics.pillButton("Choose from Library", fill: .accentColor.opacity(0.1), foreground: .accentColor, weight: .medium) { onSelect(.library) }
            metrics.pillButton("Search the Web", fill: .accentColor.opacity(0.1), foreground: .accentColor, weight: .medium) { onSelect(.web) }
            if hasCover {
                metrics.pillButton("Remove Cover", fill: .red.opacity(0.1), foreground: .red, weight: .medium, role: .destructive) { onSelect(.remove) }
            }

            // Cancel — neutral grey, matches ConfirmationSheet's Cancel.
            metrics.pillButton("Cancel", fill: Color(.systemGray5), foreground: .primary, weight: .medium) {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, SheetMetrics.topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(metrics.height(buttonCount: buttonCount, bottomPadding: bottomPadding))])
        .presentationCornerRadius(24)
        .presentationBackground { Color(.systemBackground).ignoresSafeArea() }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Lend Sheet (borrower entry)

/// Half-sheet for lending a book to a named person. The recent-borrower chips are the
/// fast path — tapping one lends immediately. Typing a new name then Lend (or the
/// keyboard's Done) handles first-time borrowers; leaving the field blank performs an
/// anonymous lend, preserving the previous one-tap behavior. The sheet is sized to its
/// content via a `.height` detent so iOS floats it above the keyboard, keeping the
/// buttons reachable while typing.
private struct LendSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let metrics = SheetMetrics()

    let recentBorrowers: [String]
    /// Reports the chosen borrower (possibly empty for an anonymous lend); the parent
    /// performs the lend after this sheet dismisses.
    let onLend: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(spacing: SheetMetrics.outerSpacing) {
            metrics.header(title: "Lend Book", message: "Who's borrowing it?")

            HStack(spacing: 8) {
                Image(systemName: "person")
                    .foregroundColor(.secondary)
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { lend(name) }
            }
            .padding(12)
            // Same translucent fill as the search box: contrasts on the systemBackground
            // sheet in both light and dark (tertiarySystemBackground is white in light).
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !recentBorrowers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent — tap to lend now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Single scrolling row rather than wrapping flow — deterministic
                    // height (so the detent math stays exact) and a familiar iOS pattern.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentBorrowers, id: \.self) { borrower in
                                Button { lend(borrower) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.crop.circle")
                                        Text(borrower)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Lend to \(borrower)")
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }

            metrics.pillButton("Lend", fill: .accentColor, weight: .semibold) { lend(name) }
            metrics.pillButton("Cancel", fill: Color(.systemGray5), foreground: .primary, weight: .medium) {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, SheetMetrics.topPadding)
        .padding(.bottom, SheetMetrics.defaultBottomPadding)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(sheetHeight)])
        .presentationCornerRadius(24)
        .presentationBackground { Color(.systemBackground).ignoresSafeArea() }
        .presentationDragIndicator(.hidden)
    }

    /// Header + 2 pill buttons via the shared metric math, plus the name field and the
    /// optional recents row, so the sheet is exactly as tall as its content.
    private var sheetHeight: CGFloat {
        var h = metrics.height(buttonCount: 2, bottomPadding: SheetMetrics.defaultBottomPadding)
        h += 46 + SheetMetrics.outerSpacing                       // name field row
        if !recentBorrowers.isEmpty {
            h += 16 + 8 + 38 + SheetMetrics.outerSpacing          // caption + chip row
        }
        return h
    }

    private func lend(_ borrower: String) {
        dismiss()
        onLend(borrower)
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
