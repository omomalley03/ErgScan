import SwiftUI
import SwiftData

struct BenchmarkReportView: View {
    @Query private var benchmarks: [BenchmarkWorkout]
    @StateObject private var viewModel = BenchmarkListViewModel()

    @State private var reportText: String = ""
    @State private var isGenerating: Bool = false
    @State private var showCopiedAlert: Bool = false

    var body: some View {
        Group {
            if reportText.isEmpty && !isGenerating {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // Scrollable text view with monospaced font
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if isGenerating {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating report...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.bottom, 8)
                            }

                            Text(reportText)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }

                    // Bottom toolbar with copy button
                    HStack {
                        Spacer()

                        Button {
                            UIPasteboard.general.string = reportText
                            showCopiedAlert = true
                            print("📋 Copied report to clipboard: \(reportText.count) characters")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Report")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .cornerRadius(10)
                        }
                        .disabled(reportText.isEmpty)

                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                }
            }
        }
        .navigationTitle("Debug Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    generateReport()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isGenerating)
            }
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Report copied to clipboard. You can now paste it into Claude for analysis.")
        }
        .onAppear {
            if reportText.isEmpty {
                generateReport()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Report Data")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Run benchmark tests first, then generate a debug report")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                generateReport()
            } label: {
                Text("Generate Report")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Report Generation

    private func generateReport() {
        print("📝 Starting report generation...")

        // Capture data from SwiftData on main thread
        let allImages = benchmarks.flatMap { ($0.images ?? []) }
        print("📝 Found \(allImages.count) images in \(benchmarks.count) benchmarks")

        guard !allImages.isEmpty else {
            print("⚠️ No images found")
            reportText = "No benchmark images found. Please create benchmark datasets first."
            return
        }

        isGenerating = true
        reportText = "" // Clear any existing content

        // Generate report progressively
        Task { @MainActor in
            print("📝 Generating report on main thread...")

            // Start with header
            reportText = """
            # ErgScan OCR/Parser Benchmark Test Report
            Generated: \(Date().formatted(date: .long, time: .standard))

            ## Executive Summary

            """

            let testedImages = allImages.filter { $0.accuracyScore != nil }
            let totalAccuracy = testedImages.isEmpty ? 0.0 : testedImages.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) } / Double(testedImages.count)

            reportText += """
            - Total Images: \(allImages.count)
            - Tested Images: \(testedImages.count)
            - Overall Accuracy: \(String(format: "%.1f%%", totalAccuracy * 100))


            """

            reportText += "## Detailed Test Results\n\n"

            // Process each image and update UI progressively
            for (index, image) in allImages.enumerated() {
                reportText += "### Test Case \(index + 1): \(image.angleDescription ?? "Unknown")\n\n"

                // Image metadata
                reportText += "**Image Info:**\n"
                reportText += "- Resolution: \(image.resolution ?? "Unknown")\n"
                reportText += "- Captured: \(image.capturedDate.formatted(date: .abbreviated, time: .shortened))\n"
                if let lastTest = image.lastTestedDate {
                    reportText += "- Last Tested: \(lastTest.formatted(date: .abbreviated, time: .shortened))\n"
                }
                reportText += "- OCR Confidence: \(String(format: "%.1f%%", (image.ocrConfidence ?? 0) * 100))\n"
                if let accuracy = image.accuracyScore {
                    reportText += "- Accuracy Score: \(String(format: "%.1f%%", accuracy * 100))\n"
                }
                reportText += "\n"

                // Ground truth
                if let workout = image.workout {
                    reportText += "**Ground Truth:**\n```\n"
                    reportText += "Workout Type: \(workout.workoutType ?? "nil")\n"
                    reportText += "Description: \(workout.workoutDescription ?? "nil")\n"
                    reportText += "Total Time: \(workout.totalTime ?? "nil")\n"
                    if let dist = workout.totalDistance {
                        reportText += "Total Distance: \(dist)m\n"
                    }
                    if let reps = workout.reps {
                        reportText += "Reps: \(reps)\n"
                    }
                    reportText += "\nIntervals:\n"
                    let sortedIntervals = (workout.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                    for (i, interval) in sortedIntervals.enumerated() {
                        reportText += "  [\(i + 1)] Time: \(interval.time ?? "nil")"
                        if let m = interval.meters { reportText += ", Meters: \(m)" }
                        if let s = interval.splitPer500m { reportText += ", Split: \(s)" }
                        if let r = interval.strokeRate { reportText += ", Rate: \(r)" }
                        if let h = interval.heartRate { reportText += ", HR: \(h)" }
                        reportText += "\n"
                    }
                    reportText += "```\n\n"
                }

                // Raw OCR data
                if let rawOCRData = image.rawOCRResults,
                   let ocrResults = try? JSONDecoder().decode([GuideRelativeOCRResult].self, from: rawOCRData) {
                    reportText += "**Raw OCR Results (\(ocrResults.count) items):**\n```\n"
                    for (i, result) in ocrResults.enumerated() {
                        let box = result.guideRelativeBox
                        reportText += "[\(i + 1)] \"\(result.text)\" (conf: \(String(format: "%.2f", result.confidence)))"
                        reportText += " @ y=\(String(format: "%.3f", box.origin.y)) x=[\(String(format: "%.3f", box.origin.x))-\(String(format: "%.3f", box.maxX))]\n"
                    }
                    reportText += "```\n\n"
                }

                // Parsed table
                if let parsedTableData = image.parsedTable,
                   let parsedTable = try? JSONDecoder().decode(RecognizedTable.self, from: parsedTableData) {
                    reportText += "**Parsed Table:**\n```\n"
                    reportText += "Workout Type: \(parsedTable.workoutType ?? "nil")\n"
                    reportText += "Description: \(parsedTable.description ?? "nil")\n"
                    reportText += "Total Time: \(parsedTable.totalTime ?? "nil")\n"
                    if let dist = parsedTable.totalDistance {
                        reportText += "Total Distance: \(dist)m\n"
                    }
                    if let reps = parsedTable.reps {
                        reportText += "Reps: \(reps)\n"
                    }
                    reportText += "Category: \(parsedTable.category?.rawValue ?? "nil")\n"
                    reportText += "\nData Rows (\(parsedTable.rows.count)):\n"
                    for (i, row) in parsedTable.rows.enumerated() {
                        reportText += "  [\(i + 1)] Time: \(row.time?.text ?? "nil")"
                        if let m = row.meters?.text { reportText += ", Meters: \(m)" }
                        if let s = row.splitPer500m?.text { reportText += ", Split: \(s)" }
                        if let r = row.strokeRate?.text { reportText += ", Rate: \(r)" }
                        if let h = row.heartRate?.text { reportText += ", HR: \(h)" }
                        reportText += "\n"
                    }
                    reportText += "```\n\n"

                    // Field-by-field comparison
                    if let workout = image.workout {
                        reportText += "**Field-by-Field Comparison:**\n```\n"

                        // Metadata
                        reportText += "Workout Type: \(parsedTable.workoutType == workout.workoutType ? "✓" : "✗") "
                        reportText += "GT=\"\(workout.workoutType ?? "nil")\" Parsed=\"\(parsedTable.workoutType ?? "nil")\"\n"

                        reportText += "Total Time: \(parsedTable.totalTime == workout.totalTime ? "✓" : "✗") "
                        reportText += "GT=\"\(workout.totalTime ?? "nil")\" Parsed=\"\(parsedTable.totalTime ?? "nil")\"\n"

                        reportText += "Description: \(parsedTable.description == workout.workoutDescription ? "✓" : "✗") "
                        reportText += "GT=\"\(workout.workoutDescription ?? "nil")\" Parsed=\"\(parsedTable.description ?? "nil")\"\n"

                        // Intervals
                        let gtIntervals = (workout.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                        for (i, gtInterval) in gtIntervals.enumerated() {
                            if i < parsedTable.rows.count {
                                let parsedRow = parsedTable.rows[i]
                                reportText += "\nInterval \(i + 1):\n"

                                if let gtTime = gtInterval.time {
                                    let match = parsedRow.time?.text == gtTime
                                    reportText += "  Time: \(match ? "✓" : "✗") GT=\"\(gtTime)\" Parsed=\"\(parsedRow.time?.text ?? "nil")\"\n"
                                }

                                if let gtMeters = gtInterval.meters {
                                    let match = parsedRow.meters?.text == String(gtMeters)
                                    reportText += "  Meters: \(match ? "✓" : "✗") GT=\"\(gtMeters)\" Parsed=\"\(parsedRow.meters?.text ?? "nil")\"\n"
                                }

                                if let gtSplit = gtInterval.splitPer500m {
                                    let match = parsedRow.splitPer500m?.text == gtSplit
                                    reportText += "  Split: \(match ? "✓" : "✗") GT=\"\(gtSplit)\" Parsed=\"\(parsedRow.splitPer500m?.text ?? "nil")\"\n"
                                }

                                if let gtRate = gtInterval.strokeRate {
                                    let match = parsedRow.strokeRate?.text == String(gtRate)
                                    reportText += "  Rate: \(match ? "✓" : "✗") GT=\"\(gtRate)\" Parsed=\"\(parsedRow.strokeRate?.text ?? "nil")\"\n"
                                }

                                if let gtHR = gtInterval.heartRate {
                                    let match = parsedRow.heartRate?.text == String(gtHR)
                                    reportText += "  HR: \(match ? "✓" : "✗") GT=\"\(gtHR)\" Parsed=\"\(parsedRow.heartRate?.text ?? "nil")\"\n"
                                }
                            } else {
                                reportText += "\nInterval \(i + 1): ✗ Missing in parsed table\n"
                            }
                        }
                        reportText += "```\n\n"
                    }
                }

                // Parser debug log
                if let debugLog = image.parserDebugLog {
                    reportText += "**Parser Debug Log:**\n```\n"
                    reportText += debugLog
                    reportText += "\n```\n\n"
                }

                reportText += "---\n\n"

                // Small delay to allow UI to update
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }

            isGenerating = false
            print("📝 Report complete: \(reportText.count) characters")
        }
    }
}
