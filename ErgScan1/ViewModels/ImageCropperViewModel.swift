//
//  ImageCropperViewModel.swift
//  ErgScan1
//
//  Created by Claude on 2/15/26.
//

import SwiftUI
import UIKit
import Combine

@MainActor
class ImageCropperViewModel: ObservableObject {
    @Published var cropCenter: CGPoint = .zero
    @Published var cropSize: CGFloat = 0

    private(set) var maxCropSize: CGFloat = 300

    private var imageSize: CGSize = .zero
    private var viewSize: CGSize = .zero
    private var displayedImageSize: CGSize = .zero
    private var displayedImageOffset: CGPoint = .zero

    // Drag state
    private enum DragMode {
        case idle
        case moving(startCenter: CGPoint)
        case resizing(corner: Int, anchor: CGPoint)
    }
    private var dragMode: DragMode = .idle

    private let cornerHitRadius: CGFloat = 44
    private let minCropSize: CGFloat = 80

    func initializeCrop(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize

        // Calculate how the image is displayed with .aspectRatio(contentMode: .fit)
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        let fitScale: CGFloat

        if imageAspect > viewAspect {
            // Image is wider relative to view — width is the constraining axis
            fitScale = viewSize.width / imageSize.width
        } else {
            // Image is taller relative to view — height is the constraining axis
            fitScale = viewSize.height / imageSize.height
        }

        displayedImageSize = CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )

        // Offset of displayed image within view (centered)
        displayedImageOffset = CGPoint(
            x: (viewSize.width - displayedImageSize.width) / 2,
            y: (viewSize.height - displayedImageSize.height) / 2
        )

        maxCropSize = min(displayedImageSize.width, displayedImageSize.height)
        cropSize = maxCropSize * 0.8
        cropCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    // MARK: - Corner positions

    func cornerPositions() -> [CGPoint] {
        let half = cropSize / 2
        return [
            CGPoint(x: cropCenter.x - half, y: cropCenter.y - half), // 0: TL
            CGPoint(x: cropCenter.x + half, y: cropCenter.y - half), // 1: TR
            CGPoint(x: cropCenter.x - half, y: cropCenter.y + half), // 2: BL
            CGPoint(x: cropCenter.x + half, y: cropCenter.y + half), // 3: BR
        ]
    }

    // MARK: - Drag handling

    func handleDragChanged(startLocation: CGPoint, currentLocation: CGPoint, translation: CGSize) {
        // Determine mode on first call of this gesture
        if case .idle = dragMode {
            let corners = cornerPositions()
            for (i, corner) in corners.enumerated() {
                if hypot(startLocation.x - corner.x, startLocation.y - corner.y) < cornerHitRadius {
                    dragMode = .resizing(corner: i, anchor: corners[3 - i])
                    break
                }
            }
            if case .idle = dragMode {
                dragMode = .moving(startCenter: cropCenter)
            }
        }

        switch dragMode {
        case .idle:
            break
        case .moving(let startCenter):
            let newCenter = CGPoint(
                x: startCenter.x + translation.width,
                y: startCenter.y + translation.height
            )
            cropCenter = constrainCenter(newCenter, forSize: cropSize)
        case .resizing(let corner, let anchor):
            performResize(corner: corner, anchor: anchor, dragLocation: currentLocation)
        }
    }

    func handleDragEnded() {
        dragMode = .idle
    }

    // MARK: - Resize logic

    private func performResize(corner: Int, anchor: CGPoint, dragLocation: CGPoint) {
        let dx = abs(dragLocation.x - anchor.x)
        let dy = abs(dragLocation.y - anchor.y)
        var newSize = max(dx, dy)

        // Clamp to allowed range
        let maxAllowed = maxSizeForCorner(corner, anchor: anchor)
        newSize = max(minCropSize, min(newSize, maxAllowed))

        // Direction from anchor toward the dragged corner
        let (dirX, dirY): (CGFloat, CGFloat) = {
            switch corner {
            case 0: return (-1, -1) // TL: left & up from anchor (BR)
            case 1: return ( 1, -1) // TR: right & up from anchor (BL)
            case 2: return (-1,  1) // BL: left & down from anchor (TR)
            case 3: return ( 1,  1) // BR: right & down from anchor (TL)
            default: return (0, 0)
            }
        }()

        cropSize = newSize
        cropCenter = CGPoint(
            x: anchor.x + dirX * newSize / 2,
            y: anchor.y + dirY * newSize / 2
        )
    }

    private func maxSizeForCorner(_ corner: Int, anchor: CGPoint) -> CGFloat {
        let imgLeft   = displayedImageOffset.x
        let imgTop    = displayedImageOffset.y
        let imgRight  = displayedImageOffset.x + displayedImageSize.width
        let imgBottom = displayedImageOffset.y + displayedImageSize.height

        switch corner {
        case 0: return min(anchor.x - imgLeft,  anchor.y - imgTop)
        case 1: return min(imgRight - anchor.x, anchor.y - imgTop)
        case 2: return min(anchor.x - imgLeft,  imgBottom - anchor.y)
        case 3: return min(imgRight - anchor.x, imgBottom - anchor.y)
        default: return maxCropSize
        }
    }

    // MARK: - Constraint

    private func constrainCenter(_ position: CGPoint, forSize size: CGFloat) -> CGPoint {
        let halfSize = size / 2
        let minX = displayedImageOffset.x + halfSize
        let maxX = displayedImageOffset.x + displayedImageSize.width - halfSize
        let minY = displayedImageOffset.y + halfSize
        let maxY = displayedImageOffset.y + displayedImageSize.height - halfSize

        return CGPoint(
            x: max(minX, min(maxX, position.x)),
            y: max(minY, min(maxY, position.y))
        )
    }

    // MARK: - Crop

    func performCrop(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Scale from displayed image to actual image pixels
        let scaleX = CGFloat(cgImage.width) / displayedImageSize.width
        let scaleY = CGFloat(cgImage.height) / displayedImageSize.height

        // Convert crop center from view coords to displayed-image-local coords
        let displayedX = cropCenter.x - displayedImageOffset.x
        let displayedY = cropCenter.y - displayedImageOffset.y

        // Convert to actual image pixel coords
        let imageCropWidth  = cropSize * scaleX
        let imageCropHeight = cropSize * scaleY
        let imageCropCenterX = displayedX * scaleX
        let imageCropCenterY = displayedY * scaleY

        let cropRect = CGRect(
            x: imageCropCenterX - imageCropWidth / 2,
            y: imageCropCenterY - imageCropHeight / 2,
            width: imageCropWidth,
            height: imageCropHeight
        )

        let clampedRect = cropRect.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )

        guard let croppedCG = cgImage.cropping(to: clampedRect) else { return nil }

        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
