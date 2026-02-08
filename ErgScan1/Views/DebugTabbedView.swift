import SwiftUI

/// Tabs: Workout result view (default), raw OCR results, parsed JSON, and debug logs
struct DebugTabbedView: View {
    let debugResults: [GuideRelativeOCRResult]
    let parsedTable: RecognizedTable?
    let debugLog: String

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    tabButton(title: "Workout", index: 0)
                    tabButton(title: "Raw Sorted", index: 1)
                    tabButton(title: "JSON", index: 2)
                    tabButton(title: "Debug Log", index: 3)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)
            .background(Color(.secondarySystemBackground))

            // Tab content
            TabView(selection: $selectedTab) {
                if let table = parsedTable {
                    WorkoutResultView(table: table)
                        .tag(0)
                } else {
                    emptyView
                        .tag(0)
                }

                rawSortedView
                    .tag(1)

                if let table = parsedTable {
                    ParsedTableDisplayView(table: table)
                        .tag(2)
                } else {
                    emptyView
                        .tag(2)
                }

                debugLogView
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button {
            withAnimation {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(selectedTab == index ? .semibold : .regular)
                    .foregroundColor(selectedTab == index ? .accentColor : .secondary)

                if selectedTab == index {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
        }
        .frame(minWidth: 80)
    }

    private var rawSortedView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Conf")
                        .frame(width: 45, alignment: .trailing)
                    Text("X")
                        .frame(width: 45, alignment: .trailing)
                    Text("Y")
                        .frame(width: 45, alignment: .trailing)
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))

                // Results sorted by Y first, then X
                ForEach(
                    Array(debugResults
                        .sorted {
                            if abs($0.guideRelativeBox.midY - $1.guideRelativeBox.midY) < 0.03 {
                                return $0.guideRelativeBox.midX < $1.guideRelativeBox.midX
                            }
                            return $0.guideRelativeBox.midY < $1.guideRelativeBox.midY
                        }
                        .enumerated()),
                    id: \.offset
                ) { _, result in
                    HStack {
                        Text(result.text)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.0f%%", result.confidence * 100))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(confidenceColor(result.confidence))
                            .frame(width: 45, alignment: .trailing)
                        Text(String(format: "%.2f", result.guideRelativeBox.midX))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                        Text(String(format: "%.2f", result.guideRelativeBox.midY))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)

                    Divider()
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var debugLogView: some View {
        VStack(spacing: 0) {
            // Copy button bar
            HStack {
                Text("Debug Log")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    UIPasteboard.general.string = debugLog
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(debugLog.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(8)
                }
                .disabled(debugLog.isEmpty)
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            Divider()

            // Log content
            ScrollView {
                Text(debugLog.isEmpty ? "No debug log available" : debugLog)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(debugLog.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(.systemBackground))
        }
    }

    private var emptyView: some View {
        Text("No parsed data")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 { return .green }
        if confidence > 0.5 { return .orange }
        return .red
    }
}

#Preview {
    DebugTabbedView(
        debugResults: [],
        parsedTable: nil,
        debugLog: "Sample debug log\nLine 2\nLine 3"
    )
}
