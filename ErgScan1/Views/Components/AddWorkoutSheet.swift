//
//  AddWorkoutSheet.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

struct AddWorkoutSheet: View {
    @Binding var isPresented: Bool
    let onScan: () -> Void
    let onUpload: () -> Void
    let onGoals: () -> Void
    @State private var offset: CGFloat = 300

    var body: some View {
        ZStack {
            // Dimmed background
            if isPresented {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissSheet()
                    }
                    .transition(.opacity)
            }

            // Bottom sheet
            VStack {
                Spacer()

                VStack(spacing: 32) {
                    // Drag indicator
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 6)
                        .padding(.top, 12)

                    // Title
                    Text("Add Workout")
                        .font(.title2)
                        .fontWeight(.bold)

                    // Action buttons
                    HStack(spacing: 28) {
                        // Scan button
                        VStack(spacing: 12) {
                            Button {
                                HapticService.shared.lightImpact()
                                dismissSheet()
                                onScan()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 80, height: 80)
                                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                }
                            }

                            Text("Scan")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        // Upload button
                        VStack(spacing: 12) {
                            Button {
                                HapticService.shared.lightImpact()
                                dismissSheet()
                                onUpload()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 80, height: 80)
                                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)

                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                }
                            }

                            Text("Upload")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        // // Goals button
                        // VStack(spacing: 12) {
                        //     Button {
                        //         HapticService.shared.lightImpact()
                        //         dismissSheet()
                        //         onGoals()
                        //     } label: {
                        //         ZStack {
                        //             Circle()
                        //                 .fill(Color.orange)
                        //                 .frame(width: 80, height: 80)
                        //                 .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)

                        //             Image(systemName: "target")
                        //                 .font(.system(size: 32))
                        //                 .foregroundColor(.white)
                        //         }
                        //     }

                        //     Text("Goals")
                        //         .font(.subheadline)
                        //         .fontWeight(.medium)
                        // }
                    }
                    .padding(.vertical, 20)

                    Spacer()
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                )
                .offset(y: isPresented ? 0 : offset)
            }
            .ignoresSafeArea()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                offset = 300
            }
        }
    }

    private func dismissSheet() {
        HapticService.shared.lightImpact()
        withAnimation {
            isPresented = false
        }
    }
}
