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

    /// Time format: "4:00.0", "12:00.0", or "1:23:45.6"
    static let timePattern = #"^\d{1,2}:\d{2}(:\d{2})?\.\d$"#

    /// Split pace format: "1:41.2" or "1:41.29"
    static let splitPattern = #"^\d:\d{2}\.\d{1,2}$"#

    /// Meters format: "1179" or "5120" (1-5 digits)
    static let metersPattern = #"^\d{1,5}$"#

    /// Stroke rate format: "29" or "32" (1-2 digits, validated 10-60)
    static let ratePattern = #"^\d{1,2}$"#

    /// Date format: "Dec 20 2025" — relaxed to handle OCR artifacts
    static let datePattern = #"^[A-Za-z]{3}:?\s*\d{1,2}[\s.]+\d{4}$"#

    /// Interval workout type: "3x4:00/3:00r" or "12x500m/1:30r"
    static let intervalTypePattern = #"^\d{1,2}x[\d:]+[rm]?/[\d:]+r?$"#

    /// Single piece workout type: "2000m" or "4:00" or "30:00"
    static let singleTypePattern = #"^(\d+m|\d+:\d{2})$"#

    /// Total time format: "21:00.3" or "1:23:45.6"
    static let totalTimePattern = #"^\d{1,2}:\d{2}(:\d{2})?\.\d$"#

    // MARK: - Step 0: Context-Aware Normalization

    /// Normalize workout descriptor strings (e.g., "3x20:00/1:00r").
    /// This is more aggressive than general normalize() because descriptors have strict format.
    func normalizeDescriptor(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)

        // 1. Apply Cyrillic substitutions (same as normalize)
        result = result.replacingOccurrences(of: "г", with: "r")
        result = result.replacingOccurrences(of: "м", with: "m")
        result = result.replacingOccurrences(of: "а", with: "a")
        result = result.replacingOccurrences(of: "е", with: "e")
        result = result.replacingOccurrences(of: "о", with: "o")

        // 2. Replace leading B with 3 when followed by x (Bx → 3x)
        if result.hasPrefix("B") && result.count > 1 {
            let secondChar = result[result.index(result.startIndex, offsetBy: 1)]
            if secondChar == "x" {
                result = "3" + result.dropFirst()
            }
        }

        // 3. Convert comma to slash (in descriptor, comma is always misread separator)
        result = result.replacingOccurrences(of: ",", with: "/")

        // 4. Fix missing separator: detect concatenated times after 'x'
        // Pattern: after Nx, find first complete time (\d+:\d{2}) and insert / if another digit follows
        // Example: "3x4:0013:00r" → "3x4:00/3:00r"
        if let xRange = result.range(of: "x", options: .literal) {
            let afterX = String(result[xRange.upperBound...])

            // Match first time component: \d+:\d{2}
            let timePattern = #"^(\d+:\d{2})(\d)"#
            if let regex = try? NSRegularExpression(pattern: timePattern),
               let match = regex.firstMatch(in: afterX, range: NSRange(afterX.startIndex..., in: afterX)) {
                // Found pattern like "4:0013" — insert "/" after "4:00"
                if match.numberOfRanges >= 3,
                   let firstTimeRange = Range(match.range(at: 1), in: afterX) {
                    let firstTime = String(afterX[firstTimeRange])
                    let rest = String(afterX[firstTimeRange.upperBound...])
                    let beforeX = String(result[..<xRange.upperBound])
                    result = beforeX + firstTime + "/" + rest
                }
            }
        }

        // 5. Fix slash-read-as-1: After inserting "/" (or if "/" already present),
        // check if the rest portion starts with "1" that is actually a misread "/".
        // Pattern: after "NxWORK/", if rest starts with "1" followed by a valid
        // shorter rest time, strip the leading "1".
        // Example: "2x20:00/11:15r" → "2x20:00/1:15r" (the first "1" was the slash)
        // Example: "5x1000m/17:00r" → "5x1000m/7:00r"
        if let slashRange = result.range(of: "/", options: .literal) {
            let afterSlash = String(result[slashRange.upperBound...])

            // Only apply if rest part starts with "1" and the resulting rest time
            // exceeds the PM5 maximum rest time of 9:55.
            // If rest is ≥10:00, the leading "1" is definitely a misread "/".
            if afterSlash.hasPrefix("1") {
                // Parse the rest time minutes (everything before the ":")
                // e.g., "11:15r" → minutes = 11, "13:00r" → minutes = 13
                let restTimePattern = #"^(\d+):\d{2}r?$"#
                if let regex = try? NSRegularExpression(pattern: restTimePattern),
                   let match = regex.firstMatch(in: afterSlash, range: NSRange(afterSlash.startIndex..., in: afterSlash)),
                   let minutesRange = Range(match.range(at: 1), in: afterSlash),
                   let minutes = Int(afterSlash[minutesRange]),
                   minutes >= 10 {
                    // Rest ≥10:00 is impossible on PM5 (max is 9:55).
                    // Strip the leading "1" — it was the misread "/".
                    let withoutLeading1 = String(afterSlash.dropFirst())
                    let beforeSlash = String(result[..<slashRange.upperBound])
                    result = beforeSlash + withoutLeading1
                }
            }
        }

        return result
    }

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

        // Fourth pass: Cyrillic character substitutions (OCR often confuses similar-looking characters)
        for i in chars.indices {
            let c = chars[i]
            switch c {
            case "г":  // Cyrillic ge (U+0433) looks like Latin r
                chars[i] = "r"
            case "м":  // Cyrillic em (U+043C) looks like Latin m
                chars[i] = "m"
            case "а":  // Cyrillic a (U+0430) looks like Latin a
                chars[i] = "a"
            case "е":  // Cyrillic ye (U+0435) looks like Latin e
                chars[i] = "e"
            case "о":  // Cyrillic o (U+043E) looks like Latin o
                chars[i] = "o"
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

        // "s/m" — stroke rate header (OCR often reads this as "E", "s/ m", "s/rn", etc.)
        if lower == "s/m" || lower == "s/ m" || lower == "s/rn" || lower == "e" ||
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

    /// Heart rate format: integer 40-220 (BPM)
    func matchHeartRate(_ text: String) -> Bool {
        guard let val = Int(text), val >= 40, val <= 220 else { return false }
        return true
    }

    func matchDate(_ text: String) -> Date? {
        // Pre-process date string to handle OCR artifacts
        var cleaned = text.trimmingCharacters(in: .whitespaces)

        // 1. Strip colon after 3-letter month abbreviation (e.g., "Sep:" → "Sep")
        cleaned = cleaned.replacingOccurrences(of: #"^([A-Za-z]{3}):"#, with: "$1", options: .regularExpression)

        // 2. Replace period between digits with space (e.g., "14.2025" → "14 2025")
        cleaned = cleaned.replacingOccurrences(of: #"(\d)\.(\d)"#, with: "$1 $2", options: .regularExpression)

        // 3. Normalize multiple spaces to single space
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // 4. Handle concatenated day+year (e.g., "212025" → "21 2025")
        // Match pattern: "MonthAbbrev NNNNNN" where NNNNNN is concatenated day+year
        if let regex = try? NSRegularExpression(pattern: #"^([A-Za-z]{3}):?\s+(\d{5,7})$"#),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            if match.numberOfRanges >= 3,
               let monthRange = Range(match.range(at: 1), in: cleaned),
               let numberRange = Range(match.range(at: 2), in: cleaned) {
                let month = String(cleaned[monthRange])
                let number = String(cleaned[numberRange])

                // Try splitting as day (1-2 digits) + year (4 digits)
                for dayLen in 1...2 {
                    if number.count >= dayLen + 4 {
                        let dayStr = String(number.prefix(dayLen))
                        let yearStr = String(number.suffix(4))

                        if let day = Int(dayStr), day >= 1, day <= 31,
                           let year = Int(yearStr), year >= 2020, year <= 2030 {
                            cleaned = "\(month) \(dayStr) \(yearStr)"
                            break
                        }
                    }
                }
            }
        }

        // Try matching with regex pattern
        guard matches(cleaned, pattern: Self.datePattern) else { return nil }

        // Try parsing with DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.date(from: cleaned)
            ?? formatter.date(from: normalizeWhitespace(cleaned))
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

    // MARK: - Interval Workout Parsing

    /// Parse interval workout string like "3x4:00/3:00r" or "12x500m/1:30r"
    /// Returns (reps, workTime, restTime) or nil if not a valid interval format
    func parseIntervalWorkout(_ text: String) -> (reps: Int, workTime: String, restTime: String)? {
        // Pattern: capture groups for reps, work time, and rest time
        let pattern = #"^(\d{1,2})x([\d:]+[rm]?)/([\d:]+)r?$"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        // Extract captured groups
        guard match.numberOfRanges == 4 else { return nil }

        guard let repsRange = Range(match.range(at: 1), in: text),
              let workTimeRange = Range(match.range(at: 2), in: text),
              let restTimeRange = Range(match.range(at: 3), in: text) else {
            return nil
        }

        let repsString = String(text[repsRange])
        let workTime = String(text[workTimeRange])
        let restTime = String(text[restTimeRange])

        guard let reps = Int(repsString) else { return nil }

        return (reps, workTime, restTime)
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

    // MARK: - Text Splitting for Smooshed Values

    /// Split smooshed text that contains multiple patterns (e.g., "time meter" or "1:42.5 29")
    func splitSmooshedText(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // 1. Check if entire text matches a pattern - if so, don't split
        if matchesAnyPattern(trimmed) { return [trimmed] }

        // 2. Try space-separated split first (most common case)
        let spaceSplit = trimmed.split(separator: " ").map(String.init)
        if spaceSplit.count > 1 {
            // Check if all parts are valid patterns or landmarks
            let allValid = spaceSplit.allSatisfy { part in
                matchesAnyPattern(part) || isLandmarkText(part)
            }
            if allValid {
                return spaceSplit
            }
        }

        // 3. Try existing parseCombinedSplitRate for concatenated split+rate
        if let combined = parseCombinedSplitRate(trimmed) {
            return [combined.split, combined.rate]
        }

        // 4. Fallback: return original if no valid split found
        return [trimmed]
    }

    /// Check if text matches any recognized pattern
    func matchesAnyPattern(_ text: String) -> Bool {
        matchTime(text) || matchSplit(text) || matchMeters(text) ||
        matchRate(text) || matchHeartRate(text) || matchDate(text) != nil || matchWorkoutType(text)
    }

    /// Check if text is a recognized landmark
    func isLandmarkText(_ text: String) -> Bool {
        matchLandmark(text) != nil
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
