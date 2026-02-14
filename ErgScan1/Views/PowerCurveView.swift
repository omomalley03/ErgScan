import SwiftUI
import SwiftData
import Charts

struct PowerCurveView: View {
    @Environment(\.currentUser) private var currentUser
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @State private var viewModel = PowerCurveViewModel()

    private var userWorkouts: [Workout] {
        guard let uid = currentUser?.appleUserID else { return [] }
        return allWorkouts.filter { $0.userID == uid }
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingState
            } else if viewModel.curveData.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .navigationTitle("Power Curve")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadCurve(workouts: userWorkouts)
        }
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Selected point tooltip
                if let point = viewModel.selectedPoint {
                    selectedPointDetail(point)
                }

                // Chart
                Chart(viewModel.curveData) { point in
                    LineMark(
                        x: .value("Duration", log10(point.durationSeconds)),
                        y: .value("Watts", point.watts)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue.gradient)

                    PointMark(
                        x: .value("Duration", log10(point.durationSeconds)),
                        y: .value("Watts", point.watts)
                    )
                    .symbolSize(
                        viewModel.selectedPoint?.durationSeconds == point.durationSeconds ? 80 : 30
                    )
                    .foregroundStyle(
                        viewModel.selectedPoint?.durationSeconds == point.durationSeconds
                            ? Color.blue : Color.blue.opacity(0.7)
                    )
                }
                .chartXAxis {
                    AxisMarks(values: xAxisTickValues) { value in
                        if let v = value.as(Double.self),
                           let label = xAxisTickLabel(for: v) {
                            AxisValueLabel { Text(label).font(.caption2) }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    }
                }
                .chartYAxisLabel("Watts", position: .leading)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                handleChartTap(at: location, proxy: proxy, geometry: geometry)
                            }
                    }
                }
                .frame(height: 300)
                .padding()

                // Summary stats
                summaryStats
            }
        }
    }

    // MARK: - X Axis Configuration

    private let xAxisTicks: [(logValue: Double, label: String)] = [
        (log10(10),   "10s"),
        (log10(30),   "30s"),
        (log10(60),   "1m"),
        (log10(300),  "5m"),
        (log10(600),  "10m"),
        (log10(1800), "30m"),
        (log10(3600), "1h"),
    ]

    private var xAxisTickValues: [Double] {
        xAxisTicks.map(\.logValue)
    }

    private func xAxisTickLabel(for logValue: Double) -> String? {
        xAxisTicks.first(where: { abs($0.logValue - logValue) < 0.01 })?.label
    }

    // MARK: - Chart Interaction

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let xPosition = location.x - frame.origin.x

        guard let logDuration: Double = proxy.value(atX: xPosition) else { return }

        // Find the nearest point
        let nearest = viewModel.curveData.min(by: {
            abs(log10($0.durationSeconds) - logDuration) < abs(log10($1.durationSeconds) - logDuration)
        })

        withAnimation(.easeInOut(duration: 0.2)) {
            if viewModel.selectedPoint?.durationSeconds == nearest?.durationSeconds {
                viewModel.selectedPoint = nil
            } else {
                viewModel.selectedPoint = nearest
                HapticService.shared.lightImpact()
            }
        }
    }

    // MARK: - Selected Point Detail

    @ViewBuilder
    private func selectedPointDetail(_ point: PowerCurveService.PowerCurvePoint) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(PowerCurveService.formatDuration(point.durationSeconds))
                    .font(.headline)
                    .fontWeight(.bold)
            }

            VStack(spacing: 4) {
                Text("Power")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int(point.watts))W")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            VStack(spacing: 4) {
                Text("Split")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(PowerCurveService.secondsToSplitString(point.splitSeconds))
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Summary Stats

    @ViewBuilder
    private var summaryStats: some View {
        let points = viewModel.curveData
        if let peak = points.max(by: { $0.watts < $1.watts }),
           let longest = points.max(by: { $0.durationSeconds < $1.durationSeconds }) {
            HStack(spacing: 12) {
                PowerCurveStatCard(
                    label: "Peak Power",
                    value: "\(Int(peak.watts))W",
                    subtitle: PowerCurveService.formatDuration(peak.durationSeconds)
                )
                PowerCurveStatCard(
                    label: "Longest",
                    value: PowerCurveService.formatDuration(longest.durationSeconds),
                    subtitle: "\(Int(longest.watts))W"
                )
                PowerCurveStatCard(
                    label: "Data Points",
                    value: "\(points.count)",
                    subtitle: ""
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Loading & Empty States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Building power curve...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Power Data",
            systemImage: "chart.xyaxis.line",
            description: Text("Complete workouts with splits to build your power curve")
        )
    }
}

// MARK: - Stat Card

private struct PowerCurveStatCard: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
