import Foundation
import CoreGraphics

/// Regex pattern matching, normalization, and landmark detection for OCR text
struct TextPatternMatcher {

    // MARK: - Landmarks

    /// Known landmark strings on the Concept2 PM5 monitor
    enum Landmark {
        case viewDetail
        case time
        case meter
        case split500m
        case strokeRateHeader
        case totalTime
    }

    // MARK: - Regex Patterns

    /// Time format: "4:00.0" or "12:00.0"
    static let timePattern = #"^\d{1,2}:\d{2}\.\d$"#

    /// Split pace format: "1:41.2" or "1:41.29"
    static let splitPattern = #"^\d:\d{2}\.\d{1,2}$"#

    /// Meters format: "1179" or "5120" (3-5 digits)
    static let metersPattern = #"^\d{3,5}$"#

    /// Stroke rate format: "29" or "32" (2 digits, validated 10-60)
    static let ratePattern = #"^\d{2}$"#

    /// Date format: "Dec 20 2025" — allow variable whitespace
    static let datePattern = #"^[A-Z][a-z]{2}\s+\d{1,2}\s+\d{4}$"#

    /// Interval workout type: "3x4:00/3:00r"
    static let intervalTypePattern = #"^\d+x[\d:]+[rm]?/[\d:]+r$"#

    /// Single piece workout type: "2000m" or "4:00" or "30:00"
    static let singleTypePattern = #"^(\d+m|\d+:\d{2})$"#

    /// Total time format: "21:00.3"
    static let totalTimePattern = #"^\d{1,2}:\d{2}\.\d$"#

    // MARK: - Step 0: Context-Aware Normalization

    /// Normalize OCR text with context-aware character substitutions.
    /// Alphabetic substitutions only apply when the character is adjacent to
    /// a digit, `:`, or `.` — this prevents corrupting words like "Total" or "Dec".
    func normalize(_ text: String) -> String {
        var chars = Array(text.trimmingCharacters(in: .whitespaces))
        guard !chars.isEmpty else { return "" }

        // First pass: always replace `;` with `:`
        for i in chars.indices {
            if chars[i] == ";" { chars[i] = ":" }
        }

        // Second pass: replace `,` with `.` in numeric context
        for i in chars.indices {
            if chars[i] == "," && isNumericNeighbor(chars, at: i) {
                chars[i] = "."
            }
        }

        // Third pass: context-aware letter substitutions
        for i in chars.indices {
            let c = chars[i]
            switch c {
            case "O":
                // O → 0 when neighbor is digit, `:`, or `.`
                if isNumericNeighbor(chars, at: i) { chars[i] = "0" }
            case "l":
                // lowercase L → 1 when neighbor is digit
                if hasDigitNeighbor(chars, at: i) { chars[i] = "1" }
            case "I":
                // I → 1 when neighbor is digit
                if hasDigitNeighbor(chars, at: i) { chars[i] = "1" }
            case "S":
                // S → 5 only when BOTH neighbors are digits
                if hasBothDigitNeighbors(chars, at: i) { chars[i] = "5" }
            case "B":
                // B → 8 only when BOTH neighbors are digits
                if hasBothDigitNeighbors(chars, at: i) { chars[i] = "8" }
            default:
                break
            }
        }

        return String(chars)
    }

    // MARK: - Step 1: Fuzzy Landmark Matching

    /// Try to match text against known PM5 landmarks using fuzzy matching.
    /// Returns the landmark type if matched, nil otherwise.
    func matchLandmark(_ text: String) -> Landmark? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        // "View Detail"
        if fuzzyMatch(lower, target: "view detail", maxDistance: 2) ||
           lower.contains("view detail") || lower.contains("view detai") {
            return .viewDetail
        }

        // "Total Time"
        if fuzzyMatch(lower, target: "total time", maxDistance: 2) ||
           lower.contains("total time") || lower.contains("tota1 time") {
            return .totalTime
        }

        // "/500m" or "500m" — check before "meter" since "500m" contains "m"
        if lower.contains("500m") || lower.contains("500rn") || 
           lower.contains("/500") || fuzzyMatch(lower, target: "/500m", maxDistance: 2) {
            return .split500m
        }

        // "s/m" — stroke rate header
        if lower == "s/m" || lower == "s/ m" || lower == "s/rn" ||
           fuzzyMatch(lower, target: "s/m", maxDistance: 1) {
            return .strokeRateHeader
        }

        // "meter" or "meters"
        if fuzzyMatch(lower, target: "meter", maxDistance: 2) ||
           fuzzyMatch(lower, target: "meters", maxDistance: 2) ||
           lower.contains("meter") || lower.contains("rneter") {
            return .meter
        }

        // "time" — check last to avoid false positives with "Total Time"
        if lower == "time" || lower == "tirne" || lower == "tlme" || lower == "tirrie" ||
           (lower.count <= 6 && fuzzyMatch(lower, target: "time", maxDistance: 2)) {
            return .time
        }

        return nil
    }

    // MARK: - Validation Methods

    func matchTime(_ text: String) -> Bool {
        matches(text, pattern: Self.timePattern)
    }

    func matchSplit(_ text: String) -> Bool {
        matches(text, pattern: Self.splitPattern)
    }

    func matchMeters(_ text: String) -> Bool {
        matches(text, pattern: Self.metersPattern)
    }

    func matchRate(_ text: String) -> Bool {
        guard matches(text, pattern: Self.ratePattern) else { return false }
        // Range validation: 10-60
        guard let value = Int(text), value >= 10, value <= 60 else { return false }
        return true
    }

    func matchDate(_ text: String) -> Date? {
        guard matches(text, pattern: Self.datePattern) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.date(from: text)
            ?? formatter.date(from: normalizeWhitespace(text))
    }

    func matchWorkoutType(_ text: String) -> Bool {
        matches(text, pattern: Self.intervalTypePattern) ||
        matches(text, pattern: Self.singleTypePattern)
    }

    func matchTotalTime(_ text: String) -> Bool {
        matches(text, pattern: Self.totalTimePattern)
    }

    // MARK: - Combined Split + Rate Parsing

    /// Parse strings like "1:42.5 29" or "1:42.529" into (split, rate).
    /// Returns nil if the string doesn't contain a combined split+rate.
    func parseCombinedSplitRate(_ text: String) -> (split: String, rate: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Case 1: space-separated "1:42.5 29"
        let parts = trimmed.split(separator: " ")
        if parts.count == 2 {
            let splitPart = String(parts[0])
            let ratePart = String(parts[1])
            if matchSplit(splitPart), matchRate(ratePart) {
                return (splitPart, ratePart)
            }
        }

        // Case 2: concatenated "1:42.529" — last 2 chars form a valid rate
        if trimmed.count >= 7 {
            let splitEnd = trimmed.index(trimmed.endIndex, offsetBy: -2)
            let splitPart = String(trimmed[trimmed.startIndex..<splitEnd])
            let ratePart = String(trimmed[splitEnd...])
            if matchSplit(splitPart), matchRate(ratePart) {
                return (splitPart, ratePart)
            }
        }

        return nil
    }

    // MARK: - Workout Category Detection

    func detectWorkoutCategory(_ workoutType: String) -> WorkoutCategory {
        if workoutType.contains("/") || workoutType.hasSuffix("r") {
            return .interval
        }
        return .single
    }

    // MARK: - Junk Detection

    private static let junkLabels: Set<String> = [
        "view detail", "total time", "total time:", "time", "meter", "meters",
        "/500m", "500m", "s/m", "concept 2", "concept2", "pm5",
        "units", "display", "menu", "avg", "average", "split", "rate", "pace",
        "total", "rest"
    ]

    /// Returns true if the text is junk that should be discarded.
    func isJunk(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Single characters
        if lower.count <= 1 { return true }

        // Known labels
        if Self.junkLabels.contains(lower) { return true }

        // Rest meter count like "r704"
        if matches(lower, pattern: #"^r\d+"#) { return true }

        return false
    }

    // MARK: - Private Helpers

    func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Neighbor Context Checks

    /// At least one immediate neighbor is a digit, `:`, or `.`
    private func isNumericNeighbor(_ chars: [Character], at index: Int) -> Bool {
        let numericChars: Set<Character> = Set("0123456789:.")
        if index > 0 && numericChars.contains(chars[index - 1]) { return true }
        if index < chars.count - 1 && numericChars.contains(chars[index + 1]) { return true }
        return false
    }

    /// At least one immediate neighbor is a digit
    private func hasDigitNeighbor(_ chars: [Character], at index: Int) -> Bool {
        if index > 0 && chars[index - 1].isNumber { return true }
        if index < chars.count - 1 && chars[index + 1].isNumber { return true }
        return false
    }

    /// Both neighbors are digits (character must not be first or last)
    private func hasBothDigitNeighbors(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0, index < chars.count - 1 else { return false }
        return chars[index - 1].isNumber && chars[index + 1].isNumber
    }

    // MARK: - Levenshtein Distance

    /// Compute Levenshtein edit distance between two strings.
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost  // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }

    /// Fuzzy match: true if Levenshtein distance ≤ maxDistance
    private func fuzzyMatch(_ text: String, target: String, maxDistance: Int) -> Bool {
        levenshteinDistance(text, target) <= maxDistance
    }
}
