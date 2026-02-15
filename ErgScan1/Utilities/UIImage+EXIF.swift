//
//  UIImage+EXIF.swift
//  ErgScan1
//
//  Created by Claude on 2/15/26.
//

import UIKit
import ImageIO

extension UIImage {
    /// Extract EXIF metadata from image
    func exifData() -> [String: Any]? {
        guard let imageData = self.jpegData(compressionQuality: 1.0),
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        return metadata
    }

    /// Extract date photo was taken from EXIF metadata
    /// Returns nil if no date found (e.g., screenshots don't have EXIF dates)
    func photoTakenDate() -> Date? {
        guard let exif = exifData(),
              let exifDict = exif[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
            return nil
        }

        // EXIF date format: "2024:02:15 14:23:45"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}
