//
//  ImagePicker.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import PhotosUI
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "ImagePicker")

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Prefer edited image (cropped), fall back to original
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage.resized(maxDimension: CoverImage.maxDimension)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage.resized(maxDimension: CoverImage.maxDimension)
            }

            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Photo Library Picker (iOS 14+)

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                logger.debug("No image selected or provider cannot load UIImage")
                return
            }

            // Capture parent reference before async operation to avoid weak self issues
            let parentRef = parent

            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let error = error {
                    logger.error("Failed to load image from photo library: \(error.localizedDescription)")
                    return
                }

                DispatchQueue.main.async {
                    if let uiImage = image as? UIImage {
                        parentRef.selectedImage = uiImage.resized(maxDimension: CoverImage.maxDimension)
                    } else {
                        logger.warning("Loaded object was not a UIImage")
                    }
                }
            }
        }
    }
}
