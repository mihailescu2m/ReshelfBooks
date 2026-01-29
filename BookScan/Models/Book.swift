//
//  Book.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import SwiftData

@Model
final class Book {
    var isbn: String
    var title: String
    var author: String
    var yearPublished: String
    var coverImageURL: String?
    var coverImageData: Data?
    var dateAdded: Date

    @Relationship(inverse: \Shelf.books)
    var shelf: Shelf?

    init(isbn: String, title: String, author: String, yearPublished: String, coverImageURL: String? = nil, coverImageData: Data? = nil, shelf: Shelf? = nil) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.yearPublished = yearPublished
        self.coverImageURL = coverImageURL
        self.coverImageData = coverImageData
        self.dateAdded = Date()
        self.shelf = shelf
    }
}
