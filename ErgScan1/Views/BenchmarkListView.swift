import SwiftUI
import SwiftData

struct BenchmarkListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var benchmarks: [BenchmarkWorkout]
    @StateObject private var viewModel = BenchmarkListViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter and sort controls
                HStack {
                    // Filter picker
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        Text("All").tag(BenchmarkFilter.all)
                        Text("Approved").tag(BenchmarkFilter.approvedOnly)
                        Text("Unapproved").tag(BenchmarkFilter.unapprovedOnly)
                    }
                    .pickerStyle(.segmented)

                    // Sort picker
                    Menu {
                        Button {
                            viewModel.sortOrder = .dateDescending
                        } label: {
                            HStack {
                                Text("Newest First")
                                if viewModel.sortOrder == .dateDescending {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Button {
                            viewModel.sortOrder = .dateAscending
                        } label: {
                            HStack {
                                Text("Oldest First")
                                if viewModel.sortOrder == .dateAscending {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Button {
                            viewModel.sortOrder = .accuracyDescending
                        } label: {
                            HStack {
                                Text("Highest Accuracy")
                                if viewModel.sortOrder == .accuracyDescending {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                Divider()

                // Benchmark list
                if filteredAndSortedBenchmarks.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredAndSortedBenchmarks) { benchmark in
                            NavigationLink(destination: BenchmarkDetailView(benchmark: benchmark)) {
                                BenchmarkRowView(benchmark: benchmark)
                            }
                        }
                        .onDelete(perform: deleteBenchmarks)
                    }
                }
            }
            .navigationTitle("Benchmarks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: BenchmarkResultsView()) {
                        Label("Results", systemImage: "chart.bar")
                    }
                    .disabled(benchmarks.isEmpty)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
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
                            Label(viewModel.retestMode == .full ? "Full" : "Parse", systemImage: "gear")
                        }

                        Button {
                            Task {
                                await viewModel.retestAllImages(context: modelContext)
                            }
                        } label: {
                            Label("Retest All", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isRetesting || benchmarks.isEmpty)
                    }
                }
            }
            .overlay {
                if viewModel.isRetesting {
                    retestProgressView
                }
            }
        }
    }

    private var filteredAndSortedBenchmarks: [BenchmarkWorkout] {
        var filtered: [BenchmarkWorkout]

        switch viewModel.selectedFilter {
        case .all:
            filtered = benchmarks
        case .approvedOnly:
            filtered = benchmarks.filter { $0.isApproved }
        case .unapprovedOnly:
            filtered = benchmarks.filter { !$0.isApproved }
        }

        switch viewModel.sortOrder {
        case .dateDescending:
            return filtered.sorted { $0.createdDate > $1.createdDate }
        case .dateAscending:
            return filtered.sorted { $0.createdDate < $1.createdDate }
        case .accuracyDescending:
            return filtered.sorted {
                averageAccuracy($0) > averageAccuracy($1)
            }
        }
    }

    private func averageAccuracy(_ workout: BenchmarkWorkout) -> Double {
        let imagesWithAccuracy = workout.images.filter { $0.accuracyScore != nil }
        guard !imagesWithAccuracy.isEmpty else { return 0.0 }

        let total = imagesWithAccuracy.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) }
        return total / Double(imagesWithAccuracy.count)
    }

    private func deleteBenchmarks(at offsets: IndexSet) {
        for index in offsets {
            let benchmark = filteredAndSortedBenchmarks[index]
            modelContext.delete(benchmark)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Benchmarks")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Benchmark datasets will be created automatically when you save workouts")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var retestProgressView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: viewModel.retestProgress)
                    .progressViewStyle(.linear)

                Text(viewModel.retestStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(40)
        }
    }
}

struct BenchmarkRowView: View {
    let benchmark: BenchmarkWorkout

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: benchmark.isApproved ? "checkmark.circle.fill" : "circle")
                .foregroundColor(benchmark.isApproved ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(benchmark.workoutType ?? "Unknown Workout")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(benchmark.createdDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(benchmark.images.count) image\(benchmark.images.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Average accuracy
            if let avgAccuracy = averageAccuracy {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(avgAccuracy * 100))%")
                        .font(.headline)
                        .foregroundColor(accuracyColor(avgAccuracy))

                    Text("accuracy")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var averageAccuracy: Double? {
        let imagesWithAccuracy = benchmark.images.filter { $0.accuracyScore != nil }
        guard !imagesWithAccuracy.isEmpty else { return nil }

        let total = imagesWithAccuracy.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) }
        return total / Double(imagesWithAccuracy.count)
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.9 { return .green }
        if accuracy >= 0.7 { return .orange }
        return .red
    }
}
