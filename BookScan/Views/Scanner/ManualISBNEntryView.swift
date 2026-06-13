//
//  ManualISBNEntryView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

struct ManualISBNEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let initialISBN: String?
    let onLookup: (String) -> Void

    @State private var isbn: String = ""
    @State private var isValidISBN = false
    @FocusState private var isTextFieldFocused: Bool

    init(initialISBN: String? = nil, onLookup: @escaping (String) -> Void) {
        self.initialISBN = initialISBN
        self.onLookup = onLookup
    }

    var body: some View {
        // No NavigationStack — presented as a sheet from ScannerTabView's NavigationStack;
        // nesting a second one causes a fatal nav-bar conflict on iPad.
        SheetHeaderContainer {
            SheetHeaderBar(title: "Enter ISBN", leading: {
                CircularIconButton(systemName: "xmark", accessibilityLabel: "Cancel") { dismiss() }
            })
        } content: {
            ScrollView {
                VStack(spacing: 32) {
                    inputSection

                    helperTextSection

                    lookupButton
                }
                .padding()
            }
            .scrollsBehindHeader()
            .onAppear {
                if let initialISBN = initialISBN {
                    isbn = initialISBN
                    validateISBN()
                }
                isTextFieldFocused = true
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("978-0-14-143951-8", text: $isbn)
                .font(.title3)
                // numbersAndPunctuation (not numberPad) so users can still type
                // the 'X' check digit that some ISBN-10s require (e.g. "080442957X"),
                // while keeping numbers on the primary keyboard layout.
                .keyboardType(.numbersAndPunctuation)
                .textContentType(.none)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isValidISBN ? Color.green : Color.clear, lineWidth: 2)
                )
                .focused($isTextFieldFocused)
                .onChange(of: isbn) { _, _ in
                    validateISBN()
                }

            if !isbn.isEmpty && !isValidISBN {
                Text("Enter a valid 10 or 13 digit ISBN")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var helperTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to find the ISBN:")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                helperItem(icon: "book.closed", text: "Back cover, near the barcode")
                helperItem(icon: "doc.text", text: "Copyright page (first few pages)")
                helperItem(icon: "number", text: "Usually starts with 978 or 979")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func helperItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var lookupButton: some View {
        Button {
            onLookup(ISBNValidator.normalize(isbn))
        } label: {
            Text("Look Up Book")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidISBN ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!isValidISBN)
    }

    private func validateISBN() {
        isValidISBN = ISBNValidator.isValid(isbn)
    }
}

#Preview("Empty") {
    ManualISBNEntryView(onLookup: { isbn in
        print("Looking up: \(isbn)")
    })
}

#Preview("With Initial ISBN") {
    ManualISBNEntryView(
        initialISBN: "9780141439518",
        onLookup: { isbn in
            print("Looking up: \(isbn)")
        }
    )
}
