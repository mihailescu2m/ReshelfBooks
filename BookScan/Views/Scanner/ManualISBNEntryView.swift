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
    let onBack: (() -> Void)?

    @State private var isbn: String = ""
    @State private var isValidISBN = false
    @FocusState private var isTextFieldFocused: Bool

    init(initialISBN: String? = nil, onLookup: @escaping (String) -> Void, onBack: (() -> Void)? = nil) {
        self.initialISBN = initialISBN
        self.onLookup = onLookup
        self.onBack = onBack
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection

                    inputSection

                    helperTextSection

                    lookupButton
                }
                .padding()
            }
            .navigationTitle("Enter ISBN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onBack = onBack {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let initialISBN = initialISBN {
                    isbn = initialISBN
                    validateISBN()
                }
                isTextFieldFocused = true
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text("Enter ISBN Manually")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding(.top, 20)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("978-0-14-143951-8", text: $isbn)
                .font(.title3)
                .keyboardType(.numberPad)
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
            let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: " ", with: "")
            onLookup(cleanISBN)
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
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        // ISBN-10 or ISBN-13
        isValidISBN = (cleanISBN.count == 10 || cleanISBN.count == 13) &&
                      cleanISBN.allSatisfy { $0.isNumber }
    }
}

#Preview("From Scanner") {
    ManualISBNEntryView(onLookup: { isbn in
        print("Looking up: \(isbn)")
    })
}

#Preview("From Wrong Book") {
    ManualISBNEntryView(
        initialISBN: "9780141439518",
        onLookup: { isbn in
            print("Looking up: \(isbn)")
        },
        onBack: {
            print("Going back")
        }
    )
}
