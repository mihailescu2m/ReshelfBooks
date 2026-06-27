//
//  ISBNValidator.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 5/6/2026.
//

import Foundation

/// Validation and normalization for ISBN-10 / ISBN-13 values.
///
/// This is the single source of truth used by both the UI and the tests, so the
/// two can't drift apart. Validation includes the standard check-digit so that
/// a correctly-lengthed-but-mistyped ISBN is rejected before a pointless lookup.
enum ISBNValidator {

    /// Strips separators and uppercases (ISBN-10 may end in an 'X' check digit).
    static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    /// True if `raw` is a structurally valid ISBN-10 or ISBN-13 (including check digit).
    static func isValid(_ raw: String) -> Bool {
        let value = normalize(raw)
        switch value.count {
        case 10: return isValidISBN10(value)
        case 13: return isValidISBN13(value)
        default: return false
        }
    }

    /// Canonical ISBN-13 form, for storage and matching: a valid ISBN-10 is converted
    /// ("978" prefix + recomputed check digit); everything else is returned normalized
    /// but otherwise unchanged. The camera always delivers EAN-13 while manual entry
    /// also accepts ISBN-10, so both must collapse to a single form — otherwise the
    /// same physical book gets a second record when entered both ways.
    static func canonicalize(_ raw: String) -> String {
        let value = normalize(raw)
        guard value.count == 10, isValidISBN10(value) else { return value }
        let first12 = "978" + value.prefix(9)
        return first12 + String(isbn13CheckDigit(for: first12))
    }

    // MARK: - Check-digit math

    private static func isValidISBN10(_ value: String) -> Bool {
        let characters = Array(value)
        var sum = 0

        // First 9 characters must be digits, weighted 10…2.
        for index in 0..<9 {
            guard let digit = characters[index].wholeNumberValue, characters[index].isNumber else {
                return false
            }
            sum += digit * (10 - index)
        }

        // Check digit (weight 1) may be 'X' meaning 10.
        let checkCharacter = characters[9]
        if checkCharacter == "X" {
            sum += 10
        } else if checkCharacter.isNumber, let digit = checkCharacter.wholeNumberValue {
            sum += digit
        } else {
            return false
        }

        return sum % 11 == 0
    }

    /// ISBN-13 check digit for the first 12 digits (weights 1,3,1,3…).
    private static func isbn13CheckDigit(for first12: String) -> Int {
        let sum = first12.enumerated().reduce(0) { partial, element in
            partial + (element.element.wholeNumberValue ?? 0) * (element.offset % 2 == 0 ? 1 : 3)
        }
        return (10 - sum % 10) % 10
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        let characters = Array(value)
        var sum = 0

        // All 13 characters must be digits, weighted 1,3,1,3…
        for (index, character) in characters.enumerated() {
            guard let digit = character.wholeNumberValue, character.isNumber else {
                return false
            }
            sum += digit * (index % 2 == 0 ? 1 : 3)
        }

        return sum % 10 == 0
    }
}
