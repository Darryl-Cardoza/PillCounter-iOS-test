//
//  PhotoHelper.swift
//  PillCounter
//
//  Created by HC on 10/12/25.
//

import SwiftUI

struct PhotoFileManager {
    
    // Singleton instance for easy access
    static let shared = PhotoFileManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Save Image
    /// Saves a UIImage to the App's Documents Directory.
    /// - Parameter image: The UIImage to save.
    /// - Returns: The fileName (String) if successful, nil otherwise.
    func saveImage(_ image: UIImage) -> String? {
        // Generate a unique name
        let fileName = "\(UUID().uuidString).jpg"
        
        // Convert to Data
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Error: Could not convert image to JPEG data.")
            return nil
        }
        
        // Get path
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Error: Could not find documents directory.")
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        // Write to disk
        do {
            try data.write(to: fileURL)
            return fileName
        } catch {
            print("❌ Error saving image to disk: \(error)")
            return nil
        }
    }
    
    // MARK: - Load Image
    /// Loads a UIImage from the Documents Directory using the file name.
    /// - Parameter fileName: The name of the file (e.g., "uuid.jpg").
    /// - Returns: The UIImage if found, nil otherwise.
    func loadImage(from fileName: String) -> Image? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        if let data = try? Data(contentsOf: fileURL),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        
        return nil
    }
    
    // MARK: - Load UIImage
    /// Returns the raw UIImage — use this when you need to pass to fullScreenCover(item:)
    /// or anywhere a UIImage reference is required.
    func loadUIImage(from fileName: String) -> UIImage? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Delete Image
    /// Deletes an image file from the Documents Directory.
    /// - Parameter fileName: The name of the file to delete.
    func deleteImage(fileName: String) {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                print("🗑️ Deleted image: \(fileName)")
            } catch {
                print("❌ Error deleting image: \(error)")
            }
        }
    }
}
