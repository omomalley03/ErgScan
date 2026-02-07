import Foundation
import CoreGraphics

/// Regex pattern matching and validation for OCR text
struct TextPatternMatcher {

    // MARK: - Data Type Classification

    /// Classified type of an OCR text element
    enum DataType {
        case workoutType     // "3x4:00/3:00r", "2000m"
        case date            // "Dec 20 2025"
        case headerLabel     // "Time", "Meters", "/500m", "s/m"
        case timeLikeSplit   // "4:00.0", "1:41.2" — ambiguous, needs X-position to disambiguate
        case meters          // "1179", "5120"
        case strokeRate      // "29", "32"
        case unknown
    }

    /// Classify a single text string into its data type.
    /// For time-like values (which could be time or split), returns `.timeLikeSplit`.
    /// The caller must use X-position to disambiguate.
    func classify(_ text: String) -> DataType {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Workout type is most distinctive — try first
        if matchWorkoutType(trimmed) || matchWorkoutType(cleanText(trimmed)) {
            return .workoutType
        }

        // Date is alphabetic + numeric, very distinctive
        if matchDate(trimmed) != nil {
            return .date
        }

        // Header labels
        if isHeaderLabel(trimmed) {
            return .headerLabel
        }

        // Clean for numeric matching
        let cleaned = cleanText(trimmed)

        // Time/split pattern (d:dd.d or dd:dd.d) — ambiguous
        if matchTime(cleaned) || matchSplit(cleaned) {
            return .timeLikeSplit
        }

        // Meters (3-5 digits)
        if matchMeters(cleaned) {
            return .meters
        }

        // Stroke rate (exactly 2 digits)
        if matchRate(cleaned) {
            return .strokeRate
        }

        return .unknown
    }

    // MARK: - Header Detection

    private static let headerLabels: Set<String> = [
        "time", "meters", "/500m", "s/m", "avg", "average",
        "split", "rate", "pace", "total", "rest", "500m"
    ]

    func isHeaderLabel(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return Self.headerLabels.contains(lower)
    }

    // MARK: - Regex Patterns

    /// Time format: "4:00.0" or "12:00.0"
    static let timePattern = #"^\d{1,2}:\d{2}\.\d$"#

    /// Split pace format: "1:41.2" or "1:41.29"
    static let splitPattern = #"^\d:\d{2}\.\d{1,2}$"#

    /// Meters format: "1179" or "5120" (3-5 digits)
    static let metersPattern = #"^\d{3,5}$"#

    /// Stroke rate format: "29" or "32" (2 digits)
    static let ratePattern = #"^\d{2}$"#

    /// Date format: "Dec 20 2025" — allow variable whitespace
    static let datePattern = #"^[A-Z][a-z]{2}\s+\d{1,2}\s+\d{4}$"#

    /// Interval workout type: "3x4:00/3:00r" or "5x500m/2:00r" or "3x4:00/3:00r"
    /// FIX: After "x", allow time-based intervals (digits with colons) before "/"
    static let intervalTypePattern = #"^\d+x[\d:]+[rm]?/[\d:]+r$"#

    /// Single piece workout type: "2000m" or "4:00" or "30:00"
    static let singleTypePattern = #"^(\d+m|\d+:\d{2})$"#

    /// Total time format: "21:00.3"
    static let totalTimePattern = #"^\d{1,2}:\d{2}\.\d$"#

    // MARK: - Validation Methods

    func matchTime(_ text: String) -> Bool {
        return matches(text, pattern: Self.timePattern)
    }

    func matchSplit(_ text: String) -> Bool {
        return matches(text, pattern: Self.splitPattern)
    }

    func matchMeters(_ text: String) -> Bool {
        return matches(text, pattern: Self.metersPattern)
    }

    func matchRate(_ text: String) -> Bool {
        return matches(text, pattern: Self.ratePattern)
    }

    func matchDate(_ text: String) -> Date? {
        // Use the ORIGINAL text for date matching — don't run cleanText on dates
        guard matches(text, pattern: Self.datePattern) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.date(from: text)
            ?? formatter.date(from: normalizeWhitespace(text))
    }

    func matchWorkoutType(_ text: String) -> Bool {
        return matches(text, pattern: Self.intervalTypePattern) ||
               matches(text, pattern: Self.singleTypePattern)
    }

    func matchTotalTime(_ text: String) -> Bool {
        return matches(text, pattern: Self.totalTimePattern)
    }

    // MARK: - Workout Category Detection

    func detectWorkoutCategory(_ workoutType: String) -> WorkoutCategory {
        if workoutType.contains("/") || workoutType.hasSuffix("r") {
            return .interval
        }
        return .single
    }

    // MARK: - Disambiguation

    /// Disambiguate time vs split when both patterns match.
    /// Uses column position (guide-relative X) to decide.
    /// - Parameters:
    ///   - text: The matched text (e.g. "1:42.5")
    ///   - midX: Guide-relative X midpoint of the bounding box
    /// - Returns: .time if in left column, .split if in right column
    enum TimeOrSplit {
        case time
        case split
    }

    func disambiguateTimeVsSplit(midX: CGFloat) -> TimeOrSplit {
        // Time column: 0.04–0.34, Split column: 0.51–0.72
        // If midX < 0.42 → time; otherwise → split
        return midX < 0.42 ? .time : .split
    }

    // MARK: - Helper Methods

    private func matches(_ text: String, pattern: String) -> Bool {
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

    /// Clean OCR text — ONLY apply numeric corrections to text that looks numeric.
    /// This avoids corrupting alphabetic text like "Dec", "Total", "View Detail".
    func cleanText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespaces)

        // Only apply O→0, l→1, I→1 substitutions if the text looks like
        // it's meant to be numeric (contains digits and punctuation, few letters)
        let digits = cleaned.filter { $0.isNumber }
        let letters = cleaned.filter { $0.isLetter }

        // Heuristic: if more than half the characters are digits, or the text
        // matches a numeric-ish pattern (contains ":" or "." with digits),
        // apply numeric cleaning
        let looksNumeric = digits.count > letters.count ||
            (digits.count > 0 && (cleaned.contains(":") || cleaned.contains(".")))

        if looksNumeric {
            cleaned = cleaned.replacingOccurrences(of: "O", with: "0")
            cleaned = cleaned.replacingOccurrences(of: "o", with: "0")
            cleaned = cleaned.replacingOccurrences(of: "l", with: "1")
            cleaned = cleaned.replacingOccurrences(of: "I", with: "1")
            cleaned = cleaned.replacingOccurrences(of: "S", with: "5")
            cleaned = cleaned.replacingOccurrences(of: ";", with: ":")  // common OCR swap
        }

        return cleaned
    }
}