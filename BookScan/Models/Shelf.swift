//
//  Shelf.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import Foundation
import SwiftData

@Model
final class Shelf {
    var name: String
    var dateCreated: Date
    var sortOrder: Int

    @Relationship
    var books: [Book] = []

    init(name: String, sortOrder: Int = 0) {
        self.name = name
        self.dateCreated = Date()
        self.sortOrder = sortOrder
    }
}
