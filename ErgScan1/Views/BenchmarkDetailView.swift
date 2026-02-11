import SwiftUI
import SwiftData

struct BenchmarkDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BenchmarkListViewModel()

    let benchmark: BenchmarkWorkout

    @State private var selectedImage: BenchmarkImage?
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Ground Truth Section
                groundTruthSection

                Divider()

                // Images Section
                imagesSection

                // Delete Button
                deleteButton
            }
            .padding()
        }
        .navigationTitle("Benchmark Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedImage) { image in
            NavigationStack {
                ComparisonDetailView(image: image)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                selectedImage = nil
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button {
                                    Task {
                                        viewModel.retestMode = .full
                                        await viewModel.retestImage(image, context: modelContext)
                                    }
                                } label: {
                                    Label("Full OCR Retest", systemImage: "arrow.clockwise")
                                }

                                Button {
                                    Task {
                                        viewModel.retestMode = .parsingOnly
                                        await viewModel.retestParsingOnly(image, context: modelContext)
                                    }
                                } label: {
                                    Label("Parser-Only Retest", systemImage: "arrow.clockwise.circle")
                                }
                            } label: {
                                Label("Retest", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isRetesting)
                        }
                    }
            }
        }
        .alert("Delete Benchmark?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteBenchmark()
            }
        } message: {
            Text("This will permanently delete this benchmark and all \((benchmark.images ?? []).count) associated images.")
        }
    }

    private var groundTruthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ground Truth Labels")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if benchmark.isApproved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Approved")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                }
            }

            // Workout metadata
            LabelValueRow(label: "Workout Type", value: benchmark.workoutType ?? "—")
            LabelValueRow(label: "Description", value: benchmark.workoutDescription ?? "—")
            LabelValueRow(label: "Total Time", value: benchmark.totalTime ?? "—")
            LabelValueRow(label: "Total Distance", value: benchmark.totalDistance != nil ? "\(benchmark.totalDistance!)m" : "—")

            if let reps = benchmark.reps {
                LabelValueRow(label: "Reps", value: "\(reps)")
            }

            // Interval data
            if !(benchmark.intervals ?? []).isEmpty {
                Text("Intervals (\((benchmark.intervals ?? []).count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                ForEach((benchmark.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }), id: \.id) { interval in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interval \(interval.orderIndex + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if let time = interval.time {
                                Text(time)
                                    .font(.caption.monospacedDigit())
                            }
                            if let meters = interval.meters {
                                Text("\(meters)m")
                                    .font(.caption.monospacedDigit())
                            }
                            if let split = interval.splitPer500m {
                                Text(split)
                                    .font(.caption.monospacedDigit())
                            }
                            if let rate = interval.strokeRate {
                                Text("\(rate) s/m")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captured Images (\((benchmark.images ?? []).count))")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Retest mode picker
                Menu {
                    Button {
                        viewModel.retestMode = .full
                    } label: {
                        HStack {
                            Text("Full OCR + Parsing")
                            if viewModel.retestMode == .full {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        viewModel.retestMode = .parsingOnly
                    } label: {
                        HStack {
                            Text("Parsing Only (Fast)")
                            if viewModel.retestMode == .parsingOnly {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                        Text(viewModel.retestMode == .full ? "Full" : "Parse")
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }

                Button {
                    Task {
                        await viewModel.retestAllImages(context: modelContext)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retest All")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
                .disabled(viewModel.isRetesting)
            }

            // Images grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach((benchmark.images ?? []).sorted(by: { $0.capturedDate < $1.capturedDate }), id: \.id) { image in
                    ImageThumbnailView(image: image)
                        .onTapGesture {
                            selectedImage = image
                        }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text("Delete Benchmark")
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.red)
            .cornerRadius(10)
        }
        .padding(.top, 20)
    }

    private func deleteBenchmark() {
        modelContext.delete(benchmark)
        dismiss()
    }
}

struct LabelValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

struct ImageThumbnailView: View {
    let image: BenchmarkImage

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            if let data = image.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                    )
            }

            // Accuracy badge
            if let accuracy = image.accuracyScore {
                Text("\(Int(accuracy * 100))%")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accuracyColor(accuracy))
                    .cornerRadius(4)
            } else {
                Text("Not tested")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.9 { return .green }
        if accuracy >= 0.7 { return .orange }
        return .red
    }
}

struct ImageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let image: BenchmarkImage
    let viewModel: BenchmarkListViewModel

    var body: some View {
        NavigationStack {
            VStack {
                if let data = image.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Failed to load image")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(image.angleDescription ?? "Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.retestImage(image, context: modelContext)
                        }
                    } label: {
                        Label("Retest", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
