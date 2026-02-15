//
//  ImageCropperView.swift
//  ErgScan1
//
//  Created by Claude on 2/15/26.
//

import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let onCropComplete: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = ImageCropperViewModel()

    private let handleLength: CGFloat = 24
    private let handleLineWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // Full image with dimmed overlay
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    // Dimming overlay with cutout for crop area
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .mask(
                            Rectangle()
                                .fill(Color.white)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.black)
                                        .frame(width: viewModel.cropSize, height: viewModel.cropSize)
                                        .position(viewModel.cropCenter)
                                        .blendMode(.destinationOut)
                                )
                        )
                }

                // Crop guide frame
                Rectangle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    .frame(width: viewModel.cropSize, height: viewModel.cropSize)
                    .position(viewModel.cropCenter)

                // L-shaped corner handles
                cornerHandles

                // Instruction banner
                VStack {
                    Text("Crop to edges of LCD display")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    Spacer()
                }
                .padding(.top, 80)
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        viewModel.handleDragChanged(
                            startLocation: gesture.startLocation,
                            currentLocation: gesture.location,
                            translation: gesture.translation
                        )
                    }
                    .onEnded { _ in
                        viewModel.handleDragEnded()
                    }
            )
            .onAppear {
                viewModel.initializeCrop(imageSize: image.size, viewSize: geometry.size)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Crop Workout")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.white)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    if let cropped = viewModel.performCrop(image: image) {
                        onCropComplete(cropped)
                    }
                }
                .foregroundColor(.white)
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Corner handles

    @ViewBuilder
    private var cornerHandles: some View {
        let half = viewModel.cropSize / 2
        let cx = viewModel.cropCenter.x
        let cy = viewModel.cropCenter.y
        let len = handleLength
        let lw = handleLineWidth

        // Top-left
        Path { p in
            p.move(to: CGPoint(x: cx - half, y: cy - half + len))
            p.addLine(to: CGPoint(x: cx - half, y: cy - half))
            p.addLine(to: CGPoint(x: cx - half + len, y: cy - half))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Top-right
        Path { p in
            p.move(to: CGPoint(x: cx + half - len, y: cy - half))
            p.addLine(to: CGPoint(x: cx + half, y: cy - half))
            p.addLine(to: CGPoint(x: cx + half, y: cy - half + len))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Bottom-left
        Path { p in
            p.move(to: CGPoint(x: cx - half, y: cy + half - len))
            p.addLine(to: CGPoint(x: cx - half, y: cy + half))
            p.addLine(to: CGPoint(x: cx - half + len, y: cy + half))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // Bottom-right
        Path { p in
            p.move(to: CGPoint(x: cx + half, y: cy + half - len))
            p.addLine(to: CGPoint(x: cx + half, y: cy + half))
            p.addLine(to: CGPoint(x: cx + half - len, y: cy + half))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }
}
