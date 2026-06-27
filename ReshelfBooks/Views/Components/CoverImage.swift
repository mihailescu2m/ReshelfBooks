//
//  CoverImage.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 5/6/2026.
//

import UIKit

extension UIImage {
    /// Returns a copy scaled down so neither dimension exceeds `maxDimension`.
    /// Images already within bounds are returned unchanged.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let ratio = maxDimension / longestSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        // Pin scale to 1 so the output's pixel dimensions equal `newSize` — otherwise
        // a 3x-scale source would still produce 3× the pixels we asked to cap.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// JPEG data for a cover image, scaled down to a sensible storage size.
    func coverJPEGData(maxDimension: CGFloat = CoverImage.maxDimension,
                       compressionQuality: CGFloat = CoverImage.compressionQuality) -> Data? {
        resized(maxDimension: maxDimension).jpegData(compressionQuality: compressionQuality)
    }
}

/// Helpers for turning arbitrary image bytes into normalized cover-image data.
enum CoverImage {
    /// Cap on a cover's longest edge. Covers display at most ~225pt (≈675px @3x),
    /// so 600px keeps quality while bounding the size stored in Core Data/CloudKit.
    static let maxDimension: CGFloat = 600
    static let compressionQuality: CGFloat = 0.8

    /// Decodes raw bytes as an image and re-encodes a size-capped JPEG.
    /// Returns `nil` if the data isn't a valid image (e.g. an HTML error page
    /// returned with a 200 status), so junk is never persisted as a cover.
    static func normalizedData(from rawData: Data) -> Data? {
        guard let image = UIImage(data: rawData) else { return nil }
        return image.coverJPEGData()
    }
}
