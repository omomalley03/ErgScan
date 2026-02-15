//
//  PhotoUploadViewModel.swift
//  ErgScan1
//
//  Created by Claude on 2/15/26.
//

import SwiftUI
import Combine

@MainActor
class PhotoUploadViewModel: ObservableObject {
    @Published var state: UploadState = .ready
    @Published var parsedTable: RecognizedTable?
    @Published var finalDate: Date?

    private let visionService = VisionService()
    private let tableParser = TableParserService()

    enum UploadState {
        case ready
        case cropping
        case processing
        case complete(RecognizedTable, Date)
        case error(String)
    }

    /// Process uploaded photo with 2-tier date priority:
    /// 1. EXIF date (when photo was taken)
    /// 2. Today's date
    func processPhoto(_ image: UIImage) async {
        state = .processing

        // Priority 1: Try EXIF date (highest priority)
        let exifDate = image.photoTakenDate()

        // Use EXIF date if available, otherwise today's date
        let finalDate = exifDate ?? Date()

        if exifDate != nil {
            print("✅ Using EXIF date: \(finalDate)")
        } else {
            print("⚠️ No EXIF date, using today: \(finalDate)")
        }

        // Run OCR and parse table
        do {
            let ocrResults = try await visionService.recognizeText(in: image)

            // Convert to guide-relative coordinates (same as ScannerViewModel)
            let guideRelativeResults = ocrResults.map { result in
                let box = result.boundingBox
                // Flip axes for portrait orientation
                let flippedBox = CGRect(
                    x: box.origin.y,
                    y: box.origin.x,
                    width: box.height,
                    height: box.width
                )
                return GuideRelativeOCRResult(
                    original: result,
                    guideRelativeBox: flippedBox
                )
            }

            // Parse table (reuses existing TableParserService)
            let parseResult = tableParser.parseTable(from: guideRelativeResults)
            var table = parseResult.table

            // Override table date with EXIF or today's date
            table.date = finalDate

            parsedTable = table
            self.finalDate = finalDate
            state = .complete(table, finalDate)

        } catch {
            state = .error("Failed to process photo: \(error.localizedDescription)")
        }
    }
}
