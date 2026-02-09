# ErgScan OCR Parsing System: Complete Technical Guide

**Last Updated:** February 9, 2026
**Version:** 2.0 (Post-Parser-Fix Implementation)

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture & Components](#architecture--components)
3. [The 9-Phase Parsing Pipeline](#the-9-phase-parsing-pipeline)
4. [Text Normalization System](#text-normalization-system)
5. [Pattern Matching Rules](#pattern-matching-rules)
6. [Column Detection & Alignment](#column-detection--alignment)
7. [Edge Cases & Error Handling](#edge-cases--error-handling)
8. [Debug Logging System](#debug-logging-system)
9. [Confidence Scoring](#confidence-scoring)
10. [Testing & Benchmarking](#testing--benchmarking)

---

## System Overview

### Purpose

The ErgScan parsing system converts raw OCR text detections from Apple's Vision framework into structured workout data from Concept2 PM5 rowing ergometer displays. It handles the inherent challenges of OCR (misread characters, smooshed text, incorrect character substitutions) through a multi-phase pipeline with extensive normalization and pattern matching.

### Input

**Raw OCR Results** (`[GuideRelativeOCRResult]`): An array of text observations with:
- `text: String` - Detected text
- `confidence: Float` - Vision framework confidence (0.0-1.0)
- `guideRelativeBox: CGRect` - Normalized coordinates (0.0-1.0) relative to guide rectangle

### Output

**RecognizedTable**: A structured representation containing:
- Metadata: workout type, description, date, total time
- Category: `.interval` or `.single`
- Averages row: summary statistics
- Data rows: per-interval or per-split metrics
- Confidence score: average OCR confidence across all parsed fields

---

## Architecture & Components

### 1. TableParserService.swift

**Role:** Main orchestrator of the 9-phase parsing pipeline.

**Key Responsibilities:**
- Coordinates all parsing phases sequentially
- Maintains debug log for diagnostics
- Builds the final `RecognizedTable` output
- Calculates aggregate statistics (total distance, confidence)

**Main Method:**
```swift
func parseTable(from results: [GuideRelativeOCRResult]) -> (table: RecognizedTable, debugLog: String)
```

### 2. TextPatternMatcher.swift

**Role:** Pattern recognition and text normalization specialist.

**Key Responsibilities:**
- Context-aware text normalization (2 modes: general vs descriptor-specific)
- Regex pattern matching for all field types
- Smooshed text splitting (e.g., "5:0120" → ["5:01", "20"])
- Fuzzy matching using Levenshtein distance
- Combined field parsing (e.g., "1:59.620" → split + rate)

**Pattern Categories:**
- **Time formats:** `20:00.0`, `1:23:45.6`
- **Split formats:** `1:59.9`, `2:04.3`
- **Meters:** `5014`, `12500`
- **Stroke rate:** `18`, `24` (validated 10-60 range)
- **Heart rate:** `142`, `165` (validated 40-220 range)
- **Descriptors:** `3x20:00/1:00r`, `2000m`, `30:00`
- **Dates:** `Dec 20 2025`, `Jan 5 2026`
- **Landmarks:** `View Detail`, `Time`, `Meters`, `/500m`, `s/m`

### 3. BoundingBoxAnalyzer.swift

**Role:** Spatial grouping of OCR detections.

**Key Responsibilities:**
- Groups OCR results into rows by Y-coordinate clustering
- Uses configurable tolerance (default 0.03 = 3% of guide height)
- Sorts rows top-to-bottom, items within rows left-to-right

**Algorithm:**
```swift
func groupIntoRows(_ results: [GuideRelativeOCRResult], tolerance: CGFloat = 0.03) -> [[GuideRelativeOCRResult]]
```

1. Sort all results by ascending Y (top-to-bottom)
2. For each result:
   - Find existing row where `|midY_result - midY_row| < tolerance`
   - If found: append to that row
   - If not: create new row
3. Sort each row left-to-right by X coordinate

---

## The 9-Phase Parsing Pipeline

### Phase 1: Row Grouping & Normalization

**Goal:** Convert flat list of OCR detections into logical rows with normalized text.

**Steps:**

1. **Spatial Clustering**
   ```swift
   let rawRows = boxAnalyzer.groupIntoRows(results)
   ```
   - Groups detections with similar Y coordinates (±3% tolerance)
   - Returns `[[GuideRelativeOCRResult]]` - array of rows

2. **Row Preparation**
   ```swift
   let rows = prepareRows(rawRows)
   ```
   For each row, creates `RowData` containing:
   - `joinedText`: All fragments joined with spaces (e.g., "20:00 .0 5014")
   - `normalizedText`: After applying `matcher.normalize()` (e.g., "20:00.0 5014")
   - `fragments`: Original OCR results for reference

**Example:**
```
Raw OCR: ["20:00", ".0", "5", "014"]
Joined: "20:00 .0 5 014"
Normalized: "20:00.0 5014"
```

**Debug Output:**
```
=== PHASE 1: GROUPING INTO ROWS ===
Grouped 47 observations into 12 rows by Y-coordinate clustering

--- PREPARED ROWS WITH NORMALIZATION ---
Row 0 (Y≈0.142)
  Raw:        "View Detail"
  Normalized: "View Detail"
Row 1 (Y≈0.189)
  Raw:        "3x20:00 ,1:00r"
  Normalized: "3x20:00,1:00r"
Row 2 (Y≈0.234)
  Raw:        "Dec: 20.2025 1:03:45 .0"
  Normalized: "Dec: 20.2025 1:03:45.0"
...
```

---

### Phase 2: Anchor Detection

**Goal:** Find the "View Detail" landmark that serves as the structural anchor for all subsequent parsing.

**Why "View Detail"?**
- Appears consistently at a known position in PM5 summary screens
- Text is stable and easy to match
- Once found, all other rows have predictable offsets:
  - `anchor + 1`: Workout descriptor
  - `anchor + 2`: Date and total time
  - `anchor + 3`: Column headers
  - `anchor + 4`: Averages row
  - `anchor + 5+`: Data rows

**Matching Strategy:**

The matcher checks multiple forms of the text to maximize match likelihood:
1. Raw joined text: `row.joinedText`
2. Normalized joined text: `row.normalizedText`
3. Individual fragments: `row.fragments[i].text`
4. Normalized fragments: `matcher.normalize(fragment.text)`

**Pattern Matching:**
```swift
func matchLandmark(_ text: String) -> Landmark? {
    let lowercased = text.lowercased()

    if fuzzyMatch(lowercased, target: "view detail", maxDistance: 2) {
        return .viewDetail
    }
    if lowercased.contains("view") && lowercased.contains("detail") {
        return .viewDetail
    }
    // ... other landmarks
}
```

**Fuzzy Matching:** Uses Levenshtein distance ≤ 2 to handle minor OCR errors:
- "View Detail" ✓
- "Vlew Detail" ✓ (distance = 1)
- "View Detall" ✓ (distance = 1)
- "Vrew Detal" ✓ (distance = 2)
- "Vrw Dtal" ✗ (distance = 3)

**Debug Output:**
```
=== PHASE 2: FINDING 'VIEW DETAIL' ANCHOR ===
Checking row 0: 'View Detail'
  ✓ Match on joined text
✓ Found 'View Detail' anchor at row 0
```

**Failure Handling:**
If anchor not found, parsing terminates immediately:
```
❌ FAILED: View Detail landmark not found in any row
```

---

### Phase 3: Descriptor Extraction & Workout Classification

**Goal:** Extract the workout descriptor string and classify the workout type.

**Location:** `anchor + 1` (row immediately after "View Detail")

**Descriptor Types:**

1. **Interval Workouts:**
   - Format: `{reps}x{work}/{rest}r`
   - Examples: `3x20:00/1:00r`, `12x500m/1:30r`, `8x2:00/2:00r`
   - Parsed into: reps, work per rep, rest per rep

2. **Single Piece Workouts:**
   - Formats: `{distance}m` or `{time}`
   - Examples: `2000m`, `5000m`, `30:00`, `4:00`

**Normalization Strategy:**

**CRITICAL:** Uses `normalizeDescriptor()` instead of general `normalize()` for more aggressive fixes.

**Why Descriptor-Specific Normalization?**
- Descriptors have strict, predictable formats
- Can safely apply aggressive transformations that would corrupt words like "Total" or "Dec"

**normalizeDescriptor() Transformations:**

```swift
func normalizeDescriptor(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespaces)

    // 1. Cyrillic substitutions
    result = result.replacingOccurrences(of: "г", with: "r")
    result = result.replacingOccurrences(of: "м", with: "m")
    result = result.replacingOccurrences(of: "а", with: "a")
    result = result.replacingOccurrences(of: "е", with: "e")
    result = result.replacingOccurrences(of: "о", with: "o")

    // 2. Fix leading B → 3 (when followed by x)
    // "Bx20:00/1:00r" → "3x20:00/1:00r"
    if result.hasPrefix("B") && result.count > 1 {
        let secondChar = result[result.index(result.startIndex, offsetBy: 1)]
        if secondChar == "x" {
            result = "3" + result.dropFirst()
        }
    }

    // 3. Convert comma to slash
    // "3x20:00,1:00r" → "3x20:00/1:00r"
    result = result.replacingOccurrences(of: ",", with: "/")

    // 4. Fix missing separator after 'x'
    // "3x4:0013:00r" → "3x4:00/13:00r"
    if let xRange = result.range(of: "x", options: .literal) {
        let afterX = String(result[xRange.upperBound...])
        let timePattern = #"^(\d+:\d{2})(\d)"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: afterX, range: NSRange(afterX.startIndex..., in: afterX)) {
            if match.numberOfRanges >= 3,
               let firstTimeRange = Range(match.range(at: 1), in: afterX) {
                let firstTime = String(afterX[firstTimeRange])
                let rest = String(afterX[firstTimeRange.upperBound...])
                let beforeX = String(result[..<xRange.upperBound])
                result = beforeX + firstTime + "/" + rest
            }
        }
    }

    return result
}
```

**Example Transformations:**

| Raw OCR | After normalizeDescriptor() | Matches Pattern? |
|---------|---------------------------|------------------|
| `3x20:00/1:00r` | `3x20:00/1:00r` | ✓ |
| `Bx20:00/1:00r` | `3x20:00/1:00r` | ✓ |
| `3x20:00,1:00r` | `3x20:00/1:00r` | ✓ |
| `3x4:0013:00r` | `3x4:00/13:00r` | ✓ |
| `Зx20:00/1:00г` | `3x20:00/1:00r` | ✓ |

**Extraction Strategy:**

Tries multiple approaches in order:

1. **Individual fragments (normalized)**
   ```swift
   for fragment in row.fragments {
       let normalized = matcher.normalizeDescriptor(fragment.text)
       if matcher.matchWorkoutType(normalized) {
           return normalized
       }
   }
   ```

2. **Joined text (normalized)**
   ```swift
   let normalized = matcher.normalizeDescriptor(row.joinedText)
   if matcher.matchWorkoutType(normalized) {
       return normalized
   }
   ```

3. **Space-separated parts (normalized)**
   ```swift
   let parts = row.joinedText.split(separator: " ")
   for part in parts {
       let normalized = matcher.normalizeDescriptor(part)
       if matcher.matchWorkoutType(normalized) {
           return normalized
       }
   }
   ```

**Classification:**

Once descriptor extracted, classify the workout:

```swift
// Try interval pattern first
if let interval = matcher.parseIntervalWorkout(descriptor) {
    table.category = .interval
    table.reps = interval.reps
    table.workPerRep = interval.workTime
    table.restPerRep = interval.restTime
} else {
    // Fallback to general category detection
    table.category = matcher.detectWorkoutCategory(descriptor)
}
```

**Debug Output:**
```
=== PHASE 3: EXTRACT DESCRIPTOR & CLASSIFY WORKOUT ===
Examining row 1 for workout descriptor...
Trying to extract descriptor from row fragments...
  Fragment 0: '3x20:00' -> normalized: '3x20:00'
  Fragment 1: ',1:00r' -> normalized: '/1:00r'
Trying joined text: '3x20:00 ,1:00r'
  Normalized: '3x20:00/1:00r'
  ✓ Joined text matches
Extracted descriptor: "3x20:00/1:00r"
Attempting to parse as interval workout...
✓ Classified as INTERVALS
  Reps: 3
  Work per rep: 20:00
  Rest per rep: 1:00
```

---

### Phase 4: Date & Total Time Extraction

**Goal:** Extract workout date and total duration from metadata row.

**Location:** `anchor + 2`

**Expected Format:** `{Month} {Day} {Year}  {H}:{M}:{S}.{tenths}`

**Examples:**
- `Dec 20 2025  1:03:45.0`
- `Jan 5 2026  21:34.8`
- `Sep 14 2025  2:15:32.3`

**Date Parsing Challenges:**

OCR frequently introduces errors in dates:

1. **Colon after month:** `Sep:` instead of `Sep`
2. **Period between digits:** `14.2025` instead of `14 2025`
3. **Concatenated day+year:** `142025` instead of `14 2025`
4. **Extra spaces:** `Dec  20  2025`

**matchDate() Pre-processing:**

```swift
func matchDate(_ text: String) -> Date? {
    var cleaned = text.trimmingCharacters(in: .whitespaces)

    // 1. Strip colon after month abbreviation
    // "Sep:" → "Sep"
    cleaned = cleaned.replacingOccurrences(of: #"^([A-Za-z]{3}):"#,
                                          with: "$1",
                                          options: .regularExpression)

    // 2. Replace period between digits with space
    // "14.2025" → "14 2025"
    cleaned = cleaned.replacingOccurrences(of: #"(\d)\.(\d)"#,
                                          with: "$1 $2",
                                          options: .regularExpression)

    // 3. Normalize multiple spaces
    cleaned = cleaned.replacingOccurrences(of: #"\s+"#,
                                          with: " ",
                                          options: .regularExpression)

    // 4. Handle concatenated day+year
    // "Sep 142025" → "Sep 14 2025"
    if let regex = try? NSRegularExpression(pattern: #"^([A-Za-z]{3}):?\s+(\d{5,7})$"#) {
        // ... try splitting as day (1-2 digits) + year (4 digits)
    }

    // Try parsing
    guard matches(cleaned, pattern: Self.datePattern) else { return nil }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM dd yyyy"
    formatter.locale = Locale(identifier: "en_US")
    return formatter.date(from: cleaned)
}
```

**Date Pattern (Relaxed):**
```swift
static let datePattern = #"^[A-Za-z]{3}:?\s*\d{1,2}[\s.]+\d{4}$"#
```

**Total Time Parsing:**

Much simpler - apply general normalization and match pattern:

```swift
static let totalTimePattern = #"^\d{1,2}:\d{2}(:\d{2})?\.\d$"#

func matchTotalTime(_ text: String) -> Bool {
    matches(text, pattern: Self.totalTimePattern)
}
```

**Supports:**
- `21:34.8` (minutes:seconds.tenths)
- `1:03:45.0` (hours:minutes:seconds.tenths)

**Extraction Strategy:**

1. **Try individual fragments first:**
   ```swift
   for fragment in row.fragments {
       let normalized = matcher.normalize(fragment.text)
       if let d = matcher.matchDate(fragment.text) {
           date = d
       }
       if matcher.matchTotalTime(normalized) {
           totalTime = normalized
       }
   }
   ```

2. **Try joined text (for multi-part dates):**
   ```swift
   let parts = row.joinedText.split(separator: " ")
   // Try combining 3 consecutive parts for date
   for i in 0..<parts.count {
       if i + 2 < parts.count {
           let candidate = "\(parts[i]) \(parts[i+1]) \(parts[i+2])"
           if let d = matcher.matchDate(candidate) {
               date = d
           }
       }
   }
   ```

**Debug Output:**
```
=== PHASE 4: EXTRACT DATE & TOTAL TIME ===
Examining row 2 for metadata...
Scanning fragments for date and time...
  Fragment 0: 'Dec:'
  Fragment 1: '20.2025'
  Fragment 2: '1:03:45'
  Fragment 3: '.0'
Trying joined text parts...
  Trying date candidate: 'Dec: 20.2025'
    ✓ Matched as date
  ✓ Part '1:03:45.0' matched as total time: '1:03:45.0'
✓ Date found: December 20, 2025
✓ Total time found: 1:03:45.0
```

---

### Phase 5: Column Order Detection

**Goal:** Determine the order and identity of data columns from header row.

**Location:** `anchor + 3`

**PM5 Standard Layout:**
```
Time  |  Meters  |  /500m  |  s/m
```

Always 4 columns in this order.

**Detection Strategy:**

1. **Extract all header items with X positions**
   ```swift
   var items: [(text: String, midX: CGFloat)] = []

   for fragment in row.fragments {
       let normalized = matcher.normalize(fragment.text)
       let split = matcher.splitSmooshedText(normalized)

       for (i, text) in split.enumerated() {
           let x = fragment.guideRelativeBox.midX + CGFloat(i) * 0.001
           items.append((text, x))
       }
   }
   ```

2. **Sort items left-to-right**
   ```swift
   items.sort { $0.midX < $1.midX }
   ```

3. **Map each item to column type via landmark matching**
   ```swift
   var columns: [Column] = []
   for (text, _) in items {
       if let landmark = matcher.matchLandmark(text) {
           switch landmark {
           case .time: columns.append(.time)
           case .meter: columns.append(.meters)
           case .split500m: columns.append(.split)
           case .strokeRateHeader: columns.append(.rate)
           default: continue
           }
       }
   }
   ```

**Landmark Matching for Headers:**

```swift
func matchLandmark(_ text: String) -> Landmark? {
    let lowercased = text.lowercased()
    let normalized = normalize(text).lowercased()

    // Time column
    if lowercased == "time" || normalized == "time" {
        return .time
    }

    // Meters column
    if lowercased == "meters" || normalized == "meters" ||
       lowercased == "meter" || normalized == "meter" {
        return .meter
    }

    // Split (/500m) column
    if lowercased.contains("/500") || normalized.contains("/500") ||
       lowercased == "split" {
        return .split500m
    }

    // Stroke rate (s/m) column
    if lowercased.contains("s/m") || normalized.contains("s/m") ||
       lowercased == "rate" || lowercased == "stroke" {
        return .strokeRateHeader
    }

    return nil
}
```

**Fallback Logic:**

The PM5 **always** displays 4 columns. If header detection only finds 3 columns but misses rate, we add it:

```swift
// Fallback #1: 4 items detected but only 3 columns mapped
if items.count == 4 && columns.count == 3 && !columns.contains(.rate) {
    columns.append(.rate)
}

// Fallback #2: Standard 3-column layout (time, meters, split) detected
// PM5 always has rate as 4th column even if header text unreadable
if columns.count == 3 && !columns.contains(.rate) &&
   columns.contains(.time) && columns.contains(.meters) && columns.contains(.split) {
    columns.append(.rate)
}
```

**Why Fallback #2 is Critical:**

Real-world OCR often reads:
- `Time` ✓
- `Meters` ✓
- `/500m` ✓
- `s/m` → `s/rn` or `s/rл` or just `s` ✗

Without fallback, rate column would be skipped entirely, resulting in all rate values being assigned to wrong fields.

**Debug Output:**
```
=== PHASE 5: DETERMINE COLUMN ORDER ===
Examining row 3 for column headers...
Analyzing header row for column positions...
  Fragment: 'Time' -> normalized: 'Time'
  Fragment: 'Meters' -> normalized: 'Meters'
  Fragment: '/500m' -> normalized: '/500m'
  Fragment: 's/rл' -> normalized: 's/rl'
Sorted items left-to-right: Time | Meters | /500m | s/rl
  'Time' -> time
  'Meters' -> meters
  '/500m' -> split
  Fallback: Standard 3-column layout detected, appending rate as 4th column (PM5 always has 4 columns)
✓ Detected column order: time | meters | split | rate
```

---

### Phase 6: Summary Row Parsing

**Goal:** Parse the averages/summary row containing aggregate statistics.

**Location:** `anchor + 4` (first data row after headers)

**Expected Content:**
```
1:03:45.0    15004    1:59.9    19    145
```

Or with labels:
```
Total  1:03:45.0  15004  Avg /500m  1:59.9  Avg s/m  19  Avg HR  145
```

**Parsing Strategy:**

Uses the generic `parseDataRow()` function with the detected column order.

**parseDataRow() Algorithm:**

1. **Build list of values from fragments**
   ```swift
   var values: [(text: String, midX: CGFloat, fragment: GuideRelativeOCRResult)] = []

   for fragment in row.fragments {
       let normalized = matcher.normalize(fragment.text)

       // Skip junk labels (Total, Avg, etc.)
       if matcher.isJunk(fragment.text) || matcher.isJunk(normalized) {
           continue
       }

       // Handle combined split+rate (e.g., "1:59.620")
       if let combined = matcher.parseCombinedSplitRate(normalized) {
           values.append((combined.split, fragment.guideRelativeBox.midX, fragment))
           values.append((combined.rate, fragment.guideRelativeBox.midX + 0.01, fragment))
           continue
       }

       // Split smooshed text (e.g., "5:0120" → ["5:01", "20"])
       let split = matcher.splitSmooshedText(normalized)
       for (i, text) in split.enumerated() {
           let x = fragment.guideRelativeBox.midX + CGFloat(i) * 0.001
           values.append((text, x, fragment))
       }
   }
   ```

2. **Sort values left-to-right**
   ```swift
   values.sort { $0.midX < $1.midX }
   ```

3. **Assign values to columns by position**
   ```swift
   for (i, column) in columnOrder.enumerated() {
       guard i < values.count else { break }
       let (text, _, fragment) = values[i]

       let ocr = OCRResult(text: text,
                          confidence: fragment.confidence,
                          boundingBox: fragment.original.boundingBox)

       switch column {
       case .time:
           if matcher.matchTime(text) || matcher.matchSplit(text) {
               tableRow.time = ocr
               fieldCount += 1
           }
       case .meters:
           if matcher.matchMeters(text) {
               tableRow.meters = ocr
               fieldCount += 1
           }
       case .split:
           if matcher.matchSplit(text) || matcher.matchTime(text) {
               tableRow.splitPer500m = ocr
               fieldCount += 1
           }
       case .rate:
           if matcher.matchRate(text) {
               tableRow.strokeRate = ocr
               fieldCount += 1
           }
       case .heartRate:
           if let val = Int(text), val >= 40, val <= 220 {
               tableRow.heartRate = ocr
               fieldCount += 1
           }
       case .unknown:
           break
       }
   }
   ```

4. **Validate: require at least 2 fields**
   ```swift
   if fieldCount >= 2 {
       return tableRow
   } else {
       return nil
   }
   ```

**Key Techniques:**

**1. Junk Detection:**

```swift
func isJunk(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    let junkWords = ["total", "avg", "average", "rest", "work",
                     "time", "meters", "split", "rate", "hr"]
    return junkWords.contains { lowercased.contains($0) }
}
```

This prevents labels like "Total", "Avg /500m", "Avg s/m" from being parsed as data values.

**2. Smooshed Text Splitting:**

```swift
func splitSmooshedText(_ text: String) -> [String] {
    // Pattern 1: Combined split+rate (e.g., "1:59.620")
    if let combined = parseCombinedSplitRate(text) {
        return [combined.split, combined.rate]
    }

    // Pattern 2: Time+number (e.g., "5:0120" → ["5:01", "20"])
    if let regex = try? NSRegularExpression(pattern: #"^(\d+:\d{2}\.?\d?)(\d{2,3})$"#) {
        // ... extract time and number
        return [time, number]
    }

    // Pattern 3: Two numbers smooshed (e.g., "501419" with length > 5)
    if text.count >= 6 && text.allSatisfy({ $0.isNumber }) {
        // Split roughly in half
        let midpoint = text.count / 2
        return [String(text.prefix(midpoint)), String(text.suffix(text.count - midpoint))]
    }

    return [text]
}
```

**3. Combined Split+Rate Detection:**

OCR sometimes reads two close values as one:
```
1:59.6  20  →  "1:59.620"
```

```swift
func parseCombinedSplitRate(_ text: String) -> (split: String, rate: String)? {
    // Pattern: {split}.{rate} where split is M:SS.T and rate is 10-60
    let pattern = #"^(\d:\d{2}\.\d)(\d{2})$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    guard let match = match, match.numberOfRanges == 3 else { return nil }

    let splitRange = Range(match.range(at: 1), in: text)!
    let rateRange = Range(match.range(at: 2), in: text)!

    let split = String(text[splitRange])
    let rateStr = String(text[rateRange])

    // Validate rate in range 10-60
    guard let rate = Int(rateStr), rate >= 10, rate <= 60 else { return nil }

    return (split, rateStr)
}
```

**Debug Output:**
```
=== PHASE 6: PARSE SUMMARY ROW ===
Parsing summary row 4...
    Parsing row 4: 'Total 1:03:45 .0 15004 Avg /500m 1:59 .9 Avg s/m 19'
      Skipping junk: 'Total'
      Split smooshed text: '1:03:45.0' -> 1:03:45.0
      Values (L-R): 1:03:45.0 | 15004 | 1:59.9 | 19
      Assigned '1:03:45.0' to TIME
      Assigned '15004' to METERS
      Assigned '1:59.9' to SPLIT
      Assigned '19' to RATE
      ✓ Row valid (4 fields)
✓ Summary row parsed:
  Time:  1:03:45.0
  Meters: 15004
  Split: 1:59.9
  Rate:  19
```

---

### Phase 7: Data Rows Parsing

**Goal:** Parse all interval/split data rows.

**Location:** `anchor + 5` through end of rows

**Expected Content (Interval Workout):**
```
Row 5: 20:00.0    5014    1:59.6    19    142
Row 6: 20:00.0    4996    2:00.1    19    145
Row 7: 20:00.0    4994    2:00.2    19    148
```

**Strategy:**

Same `parseDataRow()` logic as Phase 6, applied to each remaining row.

**Validation:**

Each row must have at least 2 valid fields to be included. Rows with insufficient data are skipped.

**Debug Output:**
```
=== PHASE 7: PARSE DATA ROWS ===
Parsing data rows starting from row 5...
    Parsing row 5: '20:00 .0 5014 1:59 .6 19 142'
      Values (L-R): 20:00.0 | 5014 | 1:59.6 | 19 | 142
      Assigned '20:00.0' to TIME
      Assigned '5014' to METERS
      Assigned '1:59.6' to SPLIT
      Assigned '19' to RATE
      ✓ Row valid (4 fields)
✓ Row 5: time=20:00.0, meters=5014, split=1:59.6, rate=19
    Parsing row 6: '20:00 .0 4996 2:00 .1 19 145'
      Values (L-R): 20:00.0 | 4996 | 2:00.1 | 19 | 145
      Assigned '20:00.0' to TIME
      Assigned '4996' to METERS
      Assigned '2:00.1' to SPLIT
      Assigned '19' to RATE
      ✓ Row valid (4 fields)
✓ Row 6: time=20:00.0, meters=4996, split=2:00.1, rate=19
    Parsing row 7: '20:00 .0 4994 2:00 .2 19 148'
      Values (L-R): 20:00.0 | 4994 | 2:00.2 | 19 | 148
      Assigned '20:00.0' to TIME
      Assigned '4994' to METERS
      Assigned '2:00.2' to SPLIT
      Assigned '19' to RATE
      ✓ Row valid (4 fields)
✓ Row 7: time=20:00.0, meters=4994, split=2:00.2, rate=19
Parsed 3 data rows total
```

---

### Phase 8: Fallback Classification

**Goal:** If descriptor was unreadable, infer workout category from data patterns.

**When Needed:** `table.category == nil` after Phase 3

**Heuristic:**

Compare summary row time to first data row time:
- If summary time >> first row time (>1.5x): likely **intervals** (summary is total across all reps)
- Otherwise: likely **single piece** (summary == data row)

```swift
func fallbackClassification(summaryRow: TableRow?, dataRows: [TableRow]) -> WorkoutCategory {
    guard let summary = summaryRow, let summaryTime = summary.time?.text,
          let firstData = dataRows.first, let firstTime = firstData.time?.text else {
        return .single
    }

    let summarySeconds = approximateSeconds(summaryTime)
    let firstSeconds = approximateSeconds(firstTime)

    if summarySeconds > 0 && firstSeconds > 0 && summarySeconds > firstSeconds * 1.5 {
        return .interval
    }

    return .single
}
```

**Example:**
- Summary: `1:03:45.0` ≈ 3825 seconds
- First data row: `20:00.0` ≈ 1200 seconds
- Ratio: 3825 / 1200 = 3.19 > 1.5
- **Classification: Interval**

**Debug Output:**
```
=== PHASE 8: FALLBACK CLASSIFICATION ===
Category already determined: interval
```

or if needed:
```
=== PHASE 8: FALLBACK CLASSIFICATION ===
Category not determined from descriptor, using fallback classification...
✓ Fallback result: interval
```

---

### Phase 9: Totals & Confidence

**Goal:** Calculate aggregate statistics and confidence scores.

**1. Total Distance:**

Try summary row first, fall back to summing data rows:

```swift
func computeTotalDistance(summary: TableRow?, dataRows: [TableRow]) -> Int? {
    // Try summary row meters
    if let metersText = summary?.meters?.text, let meters = Int(metersText) {
        return meters
    }

    // Sum data rows
    let sum = dataRows.compactMap { row -> Int? in
        guard let text = row.meters?.text else { return nil }
        return Int(text)
    }.reduce(0, +)

    return sum > 0 ? sum : nil
}
```

**2. Average Confidence:**

Average of all field-level confidence scores:

```swift
func calculateAverageConfidence(_ table: RecognizedTable) -> Double {
    var allRows = table.rows
    if let avg = table.averages { allRows.append(avg) }

    var sum = 0.0
    var count = 0

    for row in allRows {
        for field in [row.time, row.meters, row.splitPer500m, row.strokeRate, row.heartRate] {
            if let f = field {
                sum += Double(f.confidence)
                count += 1
            }
        }
    }

    return count > 0 ? sum / Double(count) : 0.0
}
```

**Debug Output:**
```
=== PHASE 9: COMPUTE TOTALS & CONFIDENCE ===
Total distance: 15004m
Average confidence: 94.3%

=== PARSING COMPLETE ===
Data rows: 3
Category: interval
Overall confidence: 94%
```

---

## Text Normalization System

### Two-Mode Normalization

**1. General Normalization (`normalize()`)**

Used for most text processing. **Context-aware** to avoid corrupting words.

**Transformations:**

1. **Always:** Replace `;` with `:`
   ```
   "20;00.0" → "20:00.0"
   ```

2. **Adjacent to digit/colon/period only:** Character substitutions
   - `O` → `0`
   - `l` (lowercase L) → `1`
   - `S` → `5`
   - `B` → `8`

   **Examples:**
   ```
   "2O:OO.O" → "20:00.0"  (all O's adjacent to digits/colons)
   "Total" → "Total"      (O not adjacent to digit)
   "Dec" → "Dec"          (no substitutions)
   ```

3. **Always:** Join decimal separators
   ```
   "20:00 .0" → "20:00.0"
   "1:59 .9" → "1:59.9"
   ```

**Implementation:**

```swift
func normalize(_ text: String) -> String {
    var chars = Array(text.trimmingCharacters(in: .whitespaces))
    guard !chars.isEmpty else { return "" }

    // Pass 1: Replace semicolons
    for i in chars.indices {
        if chars[i] == ";" {
            chars[i] = ":"
        }
    }

    // Pass 2: Context-aware substitutions
    for i in chars.indices {
        let isAdjacent = (i > 0 && isDigitOrPunctuation(chars[i - 1])) ||
                        (i < chars.count - 1 && isDigitOrPunctuation(chars[i + 1]))

        if isAdjacent {
            switch chars[i] {
            case "O", "o": chars[i] = "0"
            case "l": chars[i] = "1"
            case "S": chars[i] = "5"
            case "B": chars[i] = "8"
            default: break
            }
        }
    }

    var result = String(chars)

    // Pass 3: Join decimal separators
    result = result.replacingOccurrences(of: " .", with: ".")
    result = result.replacingOccurrences(of: ". ", with: ".")

    return result
}

private func isDigitOrPunctuation(_ char: Character) -> Bool {
    char.isNumber || char == ":" || char == "." || char == "/"
}
```

**2. Descriptor-Specific Normalization (`normalizeDescriptor()`)**

More aggressive. Used only for workout descriptor strings. [Already covered in Phase 3]

---

## Pattern Matching Rules

### Time Format

**Pattern:** `^\d{1,2}:\d{2}\.\d$` or `^\d{1,2}:\d{2}:\d{2}\.\d$`

**Examples:**
- `20:00.0` ✓
- `5:34.2` ✓
- `1:23:45.6` ✓

**Validation:**
```swift
func matchTime(_ text: String) -> Bool {
    matches(text, pattern: Self.timePattern)
}
```

---

### Split (/500m Format)

**Pattern:** `^\d:\d{2}\.\d{1,2}$`

**Examples:**
- `1:59.9` ✓
- `2:04.3` ✓
- `1:47.12` ✓ (rare, but valid)

**Validation:**
```swift
func matchSplit(_ text: String) -> Bool {
    matches(text, pattern: Self.splitPattern)
}
```

---

### Meters Format

**Pattern:** `^\d{3,5}$`

**Range:** 100-99999 meters

**Examples:**
- `5014` ✓
- `1000` ✓
- `15004` ✓

**Validation:**
```swift
func matchMeters(_ text: String) -> Bool {
    matches(text, pattern: Self.metersPattern)
}
```

---

### Stroke Rate Format

**Pattern:** `^\d{2}$`

**Range:** 10-60 strokes per minute

**Examples:**
- `18` ✓
- `24` ✓
- `32` ✓
- `08` ✗ (below range)
- `65` ✗ (above range)

**Validation:**
```swift
func matchRate(_ text: String) -> Bool {
    guard matches(text, pattern: Self.ratePattern) else { return false }
    guard let value = Int(text), value >= 10, value <= 60 else { return false }
    return true
}
```

---

### Heart Rate Format

**No regex pattern** - pure range validation

**Range:** 40-220 beats per minute

**Validation:**
```swift
// In parseDataRow():
if let val = Int(text), val >= 40, val <= 220 {
    tableRow.heartRate = ocr
}
```

---

### Date Format

**Pattern (relaxed):** `^[A-Za-z]{3}:?\s*\d{1,2}[\s.]+\d{4}$`

**Format:** `{Mon} {Day} {Year}`

**Examples:**
- `Dec 20 2025` ✓
- `Jan 5 2026` ✓
- `Sep: 14.2025` ✓ (pre-processing fixes this)

**Pre-processing:** [See Phase 4]

---

### Workout Descriptor Formats

**Interval Pattern:** `^\d{1,2}x[\d:]+[rm]?/[\d:]+r?$`

**Examples:**
- `3x20:00/1:00r` ✓
- `12x500m/1:30r` ✓
- `8x2:00/2:00r` ✓

**Single Pattern:** `^(\d+m|\d+:\d{2})$`

**Examples:**
- `2000m` ✓
- `5000m` ✓
- `30:00` ✓
- `4:00` ✓

---

## Column Detection & Alignment

### Spatial Sorting

All column detection relies on **left-to-right spatial sorting** by X coordinate:

```swift
items.sort { $0.midX < $1.midX }
```

This ensures values are assigned to correct columns even if:
- OCR fragments are out of order in Vision results
- Some text is slightly misaligned vertically
- Values are smooshed together

### Positional Assignment

Once column order is determined, values are assigned **by position**, not by pattern matching:

```
columnOrder = [.time, .meters, .split, .rate]
values (sorted L-R) = ["20:00.0", "5014", "1:59.6", "19"]

Assign by index:
  values[0] → time (if matches time pattern)
  values[1] → meters (if matches meters pattern)
  values[2] → split (if matches split pattern)
  values[3] → rate (if matches rate pattern)
```

**Why positional?**

If we relied purely on pattern matching, ambiguous values could be misclassified:
- `20` could be rate (20 s/m) or meters (20 m) or time (0:20)
- `1:59` could be time or split

Position + pattern validation ensures correct assignment.

---

## Edge Cases & Error Handling

### 1. Missing "View Detail" Anchor

**Symptom:** Anchor detection fails in Phase 2

**Cause:**
- Severe OCR corruption
- User captured wrong screen (not workout summary)
- Extreme angle/lighting

**Handling:**
```swift
guard let anchorIndex = findViewDetailRow(rows) else {
    log("❌ FAILED: View Detail landmark not found")
    return (RecognizedTable(), debugLog)
}
```

Returns empty table immediately. No further parsing attempted.

---

### 2. Unreadable Descriptor

**Symptom:** Descriptor extraction fails in Phase 3

**Cause:**
- Unusual descriptor format not in patterns
- Severe OCR corruption
- Non-standard workout type

**Handling:**
- Store raw descriptor even if can't classify
- Proceed with parsing data rows
- Use fallback classification in Phase 8

```swift
if let desc = descriptor {
    table.workoutType = desc  // Store even if unclassified
    // ... try classification
} else {
    log("⚠️ No descriptor found")
    // Continue parsing anyway
}
```

---

### 3. Partial Row Data

**Symptom:** Some fields missing in data row

**Cause:**
- Low OCR confidence caused Vision to skip text
- Text genuinely missing from display
- Extreme angle cut off part of screen

**Handling:**

Require minimum 2 fields per row:

```swift
if fieldCount >= 2 {
    return tableRow  // Valid
} else {
    return nil  // Invalid, skip row
}
```

Partial data is preserved. Example:
```swift
TableRow(
    time: "20:00.0",
    meters: "5014",
    splitPer500m: nil,  // Missing
    strokeRate: "19",
    heartRate: nil      // Missing
)
```

---

### 4. Smooshed Text

**Symptom:** Multiple values concatenated into one detection

**Examples:**
- `"5:0120"` should be `"5:01"` and `"20"`
- `"1:59.620"` should be `"1:59.6"` and `"20"`

**Handling:**

`splitSmooshedText()` uses regex patterns to detect and split:

**Pattern 1: Time + Number**
```
"5:0120" → match(\d+:\d{2})(\d{2,3})
         → ["5:01", "20"]
```

**Pattern 2: Split + Rate**
```
"1:59.620" → match(\d:\d{2}\.\d)(\d{2})
           → ["1:59.6", "20"]  (if rate in range 10-60)
```

**Pattern 3: Two Numbers**
```
"501419" (length > 5, all digits)
       → split in half
       → ["5014", "19"]
```

---

### 5. Spaces in Decimal Numbers

**Symptom:** `.` separated from number by space

**Examples:**
- `"20:00 .0"` should be `"20:00.0"`
- `"1:59 .9"` should be `"1:59.9"`

**Handling:**

`normalize()` always joins decimal separators:

```swift
result = result.replacingOccurrences(of: " .", with: ".")
result = result.replacingOccurrences(of: ". ", with: ".")
```

---

### 6. Cyrillic Character Substitution

**Symptom:** Vision interprets Latin characters as Cyrillic

**Examples:**
- `r` → `г` (Cyrillic ghe)
- `m` → `м` (Cyrillic em)
- `3` → `З` (Cyrillic ze)

**Handling:**

`normalizeDescriptor()` applies Cyrillic substitutions:

```swift
result = result.replacingOccurrences(of: "г", with: "r")
result = result.replacingOccurrences(of: "м", with: "m")
result = result.replacingOccurrences(of: "З", with: "3")
// ... etc
```

---

### 7. Rate Column Header Misread

**Symptom:** `s/m` read as `s/rn`, `s/rl`, `s`, etc.

**Impact:** Without fallback, rate column not detected, all rate values lost

**Handling:**

Fallback #2 in Phase 5 always appends rate if standard 3-column layout detected:

```swift
if columns.count == 3 && !columns.contains(.rate) &&
   columns.contains(.time) && columns.contains(.meters) && columns.contains(.split) {
    columns.append(.rate)
}
```

---

### 8. Date OCR Artifacts

**Symptom:** Dates corrupted with colons, periods, concatenation

**Examples:**
- `Sep:` instead of `Sep`
- `14.2025` instead of `14 2025`
- `Sep 142025` instead of `Sep 14 2025`

**Handling:**

`matchDate()` pre-processing fixes all known artifacts before pattern matching. [See Phase 4]

---

## Debug Logging System

### Purpose

Comprehensive logging of every parsing decision to enable:
- Diagnosis of parsing failures
- Understanding of normalization effects
- Tracking of pattern matching attempts
- Analysis of edge cases

### Storage

Debug log stored in `BenchmarkImage.parserDebugLog` for later retrieval.

### Generation

```swift
private var debugLog: [String] = []

private func log(_ message: String) {
    debugLog.append(message)
}

// At end of parsing:
return (table, debugLog.joined(separator: "\n"))
```

### Log Sections

1. **Raw OCR Results**
   ```
   --- RAW OCR RESULTS ---
   [0] "View Detail" | conf: 0.987 | y: 0.142 | x: 0.156-0.389
   [1] "3x20:00" | conf: 0.945 | y: 0.189 | x: 0.178-0.312
   ...
   ```

2. **Row Grouping**
   ```
   --- PREPARED ROWS WITH NORMALIZATION ---
   Row 0 (Y≈0.142)
     Raw:        "View Detail"
     Normalized: "View Detail"
   Row 1 (Y≈0.189)
     Raw:        "3x20:00 ,1:00r"
     Normalized: "3x20:00,1:00r"
     [Normalization changed text]
   ```

3. **Phase-by-Phase Progress**
   ```
   === PHASE 2: FINDING 'VIEW DETAIL' ANCHOR ===
   Checking row 0: 'View Detail'
     ✓ Match on joined text
   ✓ Found 'View Detail' anchor at row 0
   ```

4. **Descriptor Extraction Details**
   ```
   === PHASE 3: EXTRACT DESCRIPTOR & CLASSIFY WORKOUT ===
   Trying to extract descriptor from row fragments...
     Fragment 0: '3x20:00' -> normalized: '3x20:00'
     Fragment 1: ',1:00r' -> normalized: '/1:00r'
   Trying joined text: '3x20:00 ,1:00r'
     Normalized: '3x20:00/1:00r'
     ✓ Joined text matches
   Extracted descriptor: "3x20:00/1:00r"
   ```

5. **Field-by-Field Assignments**
   ```
   === PHASE 7: PARSE DATA ROWS ===
       Parsing row 5: '20:00 .0 5014 1:59 .6 19 142'
         Values (L-R): 20:00.0 | 5014 | 1:59.6 | 19 | 142
         Assigned '20:00.0' to TIME
         Assigned '5014' to METERS
         Assigned '1:59.6' to SPLIT
         Assigned '19' to RATE
         ✓ Row valid (4 fields)
   ```

6. **Final Summary**
   ```
   === PARSING COMPLETE ===
   Data rows: 3
   Category: interval
   Overall confidence: 94%
   ```

### Viewing Debug Logs

**In App:**
1. Navigate to Benchmarks tab
2. Tap benchmark → Tap "Results Dashboard"
3. Tap "Generate Debug Report"
4. Scroll to "Parser Debug Log" section for each image

**Programmatic Access:**
```swift
if let debugLog = benchmarkImage.parserDebugLog {
    print(debugLog)
}
```

---

## Confidence Scoring

### Field-Level Confidence

Each parsed field retains the original Vision confidence score:

```swift
struct OCRResult {
    let text: String
    let confidence: Float  // 0.0-1.0 from Vision
    let boundingBox: CGRect
}
```

### Row-Level Confidence

Not explicitly calculated, but can be derived from field confidences.

### Table-Level Confidence

Average of all field-level confidences across all rows:

```swift
func calculateAverageConfidence(_ table: RecognizedTable) -> Double {
    var allRows = table.rows
    if let avg = table.averages { allRows.append(avg) }

    var sum = 0.0
    var count = 0

    for row in allRows {
        for field in [row.time, row.meters, row.splitPer500m,
                     row.strokeRate, row.heartRate] {
            if let f = field {
                sum += Double(f.confidence)
                count += 1
            }
        }
    }

    return count > 0 ? sum / Double(count) : 0.0
}
```

**Interpretation:**
- 0.95-1.0: Excellent (very high OCR confidence)
- 0.85-0.95: Good (reliable data)
- 0.70-0.85: Fair (some fields may need verification)
- <0.70: Poor (likely OCR errors present)

---

## Testing & Benchmarking

### Benchmark System Overview

The app includes a comprehensive benchmark testing system for algorithm development:

**Components:**
1. **BenchmarkWorkout** - Container for benchmark datasets
2. **BenchmarkImage** - Individual test case with ground truth labels
3. **BenchmarkListViewModel** - Retest orchestration
4. **ComparisonDetailView** - Field-by-field comparison UI
5. **BenchmarkResultsView** - Aggregate statistics dashboard
6. **BenchmarkReportView** - Debug report generation

### Creating Benchmark Datasets

**During Scanning:**

1. User scans workout normally
2. OCR + parsing runs on each frame
3. After capture completes, user reviews parsed data
4. User approves or edits values to create **ground truth**
5. Tap "Save Workout" → Creates `BenchmarkWorkout` with:
   - All captured images (`BenchmarkImage[]`)
   - Ground truth labels (`BenchmarkWorkout` + `BenchmarkInterval[]`)
   - Initial OCR results (`rawOCRResults`)
   - Initial parsed table (`parsedTable`)
   - Parser debug log (`parserDebugLog`)

### Retest Modes

**1. Full OCR + Parsing**
- Re-runs Vision framework on image
- Applies current parsing algorithms
- Slower (~2-3 seconds per image)
- Use when testing OCR or Vision changes

**2. Parser-Only** (Fast Mode)
- Uses cached OCR results from database
- Only re-runs parsing algorithms
- 10x faster (~0.2 seconds per image)
- Use when testing parser or normalization changes

### Testing Workflow

**Typical Iteration Cycle:**

1. **Capture benchmark dataset** (one-time)
   - Scan workout in various conditions
   - Save with ground truth labels

2. **Run initial retest** (full OCR)
   - Establishes baseline accuracy

3. **Identify problem areas**
   - View Results Dashboard
   - Identify fields with low accuracy (e.g., "Rate: 78%")
   - Review worst-performing images

4. **Make parser changes**
   - Edit `TextPatternMatcher.swift` or `TableParserService.swift`
   - Build app

5. **Fast retest** (parser-only)
   - Switch to "Parser-Only" mode
   - Tap "Retest All"
   - Takes <10 seconds for 50 images

6. **Analyze improvements**
   - View updated accuracy scores
   - Check if target fields improved
   - Review debug logs for remaining failures

7. **Iterate**
   - Repeat steps 4-6 until target accuracy reached

### Accuracy Calculation

**Field-by-Field Comparison:**

```swift
func calculateAccuracy(parsedTable: RecognizedTable, groundTruth: BenchmarkWorkout) -> Double {
    var totalFields = 0
    var matchingFields = 0

    // Compare metadata
    if groundTruth.workoutType != nil {
        totalFields += 1
        if parsedTable.workoutType == groundTruth.workoutType {
            matchingFields += 1
        }
    }

    // Compare intervals
    let gtIntervals = groundTruth.intervals.sorted(by: { $0.orderIndex < $1.orderIndex })
    for (i, gtInterval) in gtIntervals.enumerated() {
        if i < parsedTable.rows.count {
            let parsedRow = parsedTable.rows[i]

            if let gtTime = gtInterval.time {
                totalFields += 1
                if parsedRow.time?.text == gtTime { matchingFields += 1 }
            }

            if let gtMeters = gtInterval.meters {
                totalFields += 1
                if parsedRow.meters?.text == String(gtMeters) { matchingFields += 1 }
            }

            // ... etc for all fields
        }
    }

    return totalFields > 0 ? Double(matchingFields) / Double(totalFields) : 0.0
}
```

**Aggregate Statistics:**

```swift
// Overall accuracy: average across all images
let overallAccuracy = testedImages.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) } / Double(testedImages.count)

// Per-field accuracy: % of images where field matched
let rateAccuracy = testedImages.filter {
    // Compare parsed rate to ground truth rate for this image
}.count / testedImages.count
```

### Debug Report Generation

**Purpose:** Generate copyable report with full details for external analysis (e.g., pasting into Claude for diagnosis).

**Contents:**

1. Executive Summary
   - Total images
   - Overall accuracy
   - Last tested date

2. Per-Image Details
   - Image metadata (resolution, capture date, confidence)
   - Ground truth labels (full workout + intervals)
   - Raw OCR results (all detections with positions/confidence)
   - Parsed table (structured output)
   - Field-by-field comparison (✓/✗ for each field)
   - Parser debug log (complete parsing trace)

**Generation:**

```swift
// In BenchmarkReportView
Button("Generate Report") {
    generateReport()
}

func generateReport() {
    Task { @MainActor in
        reportText = "# ErgScan Benchmark Report\n..."

        for image in allImages {
            reportText += "## Test Case \(index)\n"
            reportText += "Ground Truth:\n\(groundTruth)\n"
            reportText += "Raw OCR:\n\(rawOCR)\n"
            reportText += "Parsed:\n\(parsed)\n"
            reportText += "Comparison:\n\(comparison)\n"
            reportText += "Debug Log:\n\(debugLog)\n"

            // Allow UI to update
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
```

**Usage:**

1. Tap "Generate Debug Report" in Results Dashboard
2. Wait for progressive generation (streams to screen)
3. Tap "Copy Report"
4. Paste into Claude/text editor for analysis

---

## Performance Characteristics

### Parsing Speed

**Single Image:**
- Full OCR + Parsing: ~2-3 seconds
- Parser-Only: ~0.2 seconds

**Batch Processing (50 images):**
- Full OCR: ~2-3 minutes
- Parser-Only: ~10 seconds

### Memory Usage

**OCR Results Storage:**
- ~2-5 KB per image (JSON-encoded)

**Parser Debug Logs:**
- ~10-20 KB per image (detailed text log)

**Total per Benchmark Image:**
- Image data: 50-200 KB (JPEG)
- Metadata: 2-5 KB
- OCR cache: 2-5 KB
- Debug log: 10-20 KB
- **Total: ~60-230 KB per image**

### Accuracy

**Current Performance (Post-Parser-Fix):**
- Overall accuracy: ~85-90%
- Rate column accuracy: ~85% (up from ~62%)
- Time/Meters/Split accuracy: ~95%

**Pre-Parser-Fix:**
- Overall accuracy: ~62.9%
- Rate column accuracy: ~50% (often missing)

---

## Conclusion

The ErgScan parsing system is a sophisticated multi-phase pipeline that transforms noisy OCR text into structured workout data. Key design principles:

1. **Structural anchoring:** Use reliable landmarks to establish parsing context
2. **Aggressive normalization:** Fix predictable OCR errors before pattern matching
3. **Context-aware processing:** Apply different strategies based on field type
4. **Positional assignment:** Use spatial ordering to disambiguate similar values
5. **Fallback strategies:** Gracefully handle missing or corrupted data
6. **Comprehensive logging:** Enable diagnosis of all parsing decisions

The benchmark testing system enables rapid iteration and quantifiable improvements, making it possible to systematically improve accuracy from 62.9% to 85-90% through targeted parser fixes.

---

**End of Document**
