# Intervals Variable Support

## Overview

The Concept2 PM5 supports "variable intervals" workouts where each interval can have a different duration or distance. These display differently from fixed intervals (`3x20:00/1:00r`) and need special handling in the parser.

### How variable intervals look on PM5

**Descriptor row (anchor + 1):**
```
v40:00/2:00r...4        Total Time:
```
- Starts with `v` prefix (for "variable")
- Shows the FIRST interval's work time/distance, then rest, then `...N` where N is total reps
- Often truncated because the full descriptor is too long to fit on screen
- The `...4` at the end means 4 intervals total

**Data layout (alternating data rows and rest rows):**
```
2:00:00.0  29195  2:03.3  22          ← summary/averages row
40:00.0    9737   2:03.2  22  149     ← interval 1 data
r2:00      23                          ← rest after interval 1
40:00.0    9718   2:03.4  23  152     ← interval 2 data
r2:00      13                          ← rest after interval 2
20:00.0    4860   2:03.4  23  159     ← interval 3 data
r2:00      13                          ← rest after interval 3
20:00.0    4880   2:02.9  23          ← interval 4 data
r2:00      20                          ← rest after interval 4
```

Key differences from fixed intervals:
1. **Intervals have different times/distances** (40:00, 40:00, 20:00, 20:00 — not uniform)
2. **Rest rows are interleaved** between data rows (format: `r{time}  {meters}`)
3. **The descriptor is truncated** — you can't reliably extract reps/work/rest from it
4. **The workout name is generated from the data**, not from the descriptor

### How variable intervals differ from fixed intervals in parsing

For **fixed intervals** like `3x20:00/1:00r`:
- Descriptor fully describes the workout (3 reps, 20:00 each, 1:00 rest)
- No rest rows in the data section — just summary + data rows
- Workout name = the descriptor itself

For **variable intervals** like `v40:00/2:00r...4`:
- Descriptor is truncated and unreliable for naming
- Rest rows appear between data rows and must be filtered out
- Workout name is built from the parsed interval meters (e.g., `9737m / 9718m / 4860m / 4880m`)

---

## Required Changes

### 1. Update `intervalTypePattern` in TextPatternMatcher.swift

Replace the current pattern (line 40) with one that accepts any non-digit prefix (not just `v`):

```swift
// Match fixed intervals: "3x20:00/1:00r"
// Match variable intervals: "v40:00/2:00r", "W40:00/2:00r", "и40:00/2:00r", etc.
// The key: variable intervals have non-digit prefix(es) before the time/distance
static let intervalTypePattern = #"^[^\dx]*\d{1,2}x[\d:]+[rm]?/[\d:]+r?$"#
```

`[^\dx]*` matches zero or more characters that are NOT digits and NOT `x`. This handles:
- `3x20:00/1:00r` → `[^\dx]*` matches nothing → fixed interval ✓
- `v4x40:00/2:00r` → `[^\dx]*` matches `v` → variable interval ✓  
- `W4x40:00/2:00r` → `[^\dx]*` matches `W` → variable interval ✓
- `W̵4x40:00/2:00r` → `[^\dx]*` matches `W̵` → variable interval ✓
- `и4x40:00/2:00r` → `[^\dx]*` matches `и` → variable interval ✓

### 2. Fix `parseIntervalWorkout` in TextPatternMatcher.swift (BUG)

The current code has a bug at line 328 — the regex pattern was updated but the capture groups were removed:

```swift
// BROKEN — no capture groups, so match.numberOfRanges == 4 fails
let pattern = #"^v?\d{1,2}x[\d:]+[rm]?/[\d:]+r?$"#
```

**Fix:** Use a prefix-agnostic pattern with proper capture groups:

```swift
func parseIntervalWorkout(_ text: String) -> (reps: Int, workTime: String, restTime: String, isVariable: Bool)? {
    // Strip any non-digit, non-x prefix to find the core interval pattern
    // This handles "v", "W", "W̵", "и", or any other OCR misread of "v"
    var cleaned = text
    var isVariable = false
    
    // Strip leading non-digit characters (the variable prefix)
    while let first = cleaned.first, !first.isNumber {
        cleaned = String(cleaned.dropFirst())
        isVariable = true
    }
    
    // Now parse the standard interval pattern: "4x40:00/2:00r"
    let pattern = #"^(\d{1,2})x([\d:]+[rm]?)/([\d:]+)r?$"#
    
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    
    let range = NSRange(cleaned.startIndex..., in: cleaned)
    guard let match = regex.firstMatch(in: cleaned, range: range) else {
        return nil
    }
    
    guard match.numberOfRanges == 4 else { return nil }
    
    guard let repsRange = Range(match.range(at: 1), in: cleaned),
          let workTimeRange = Range(match.range(at: 2), in: cleaned),
          let restTimeRange = Range(match.range(at: 3), in: cleaned) else {
        return nil
    }
    
    let repsString = String(cleaned[repsRange])
    let workTime = String(cleaned[workTimeRange])
    let restTime = String(cleaned[restTimeRange])
    
    guard let reps = Int(repsString) else { return nil }
    
    return (reps, workTime, restTime, isVariable)
}
```

This approach is robust: instead of trying to match every possible OCR variant of `v`, it simply strips all leading non-digit characters before parsing.

### 3. Update `matchWorkoutType` to also be prefix-agnostic

The `matchWorkoutType` method (line 278) uses `intervalTypePattern`, so it will automatically work with the updated pattern. No changes needed here.

### 4. Update `detectWorkoutCategory` to be prefix-agnostic

Replace the current `hasPrefix("v")` check (line 360):

```swift
func detectWorkoutCategory(_ workoutType: String) -> WorkoutCategory {
    // Variable intervals: any non-digit prefix before the interval pattern
    if let first = workoutType.first, !first.isNumber,
       (workoutType.contains("/") || workoutType.hasSuffix("r")) {
        return .interval  // or .intervalVariable if using separate enum case
    }
    if workoutType.contains("/") || workoutType.hasSuffix("r") {
        return .interval
    }
    return .single
}
```

### 5. Update `normalizeDescriptor` in TextPatternMatcher.swift

**Detection heuristic:** The descriptor row (anchor + 1) indicates variable intervals when:
- There is ANY non-digit prefix character(s) before a time or distance pattern, then `/`
- The `v` on the PM5 is frequently misread by OCR as: `W`, `w`, `V`, `ν` (Greek nu), `W̵` (W with strikethrough), `и` (Cyrillic), or other characters
- Rather than matching a specific prefix, detect the STRUCTURE: `{any prefix}{time or distance}/{rest}r`

The key insight: **fixed intervals always start with a digit** (the rep count, e.g., `3x20:00/1:00r`), while **variable intervals always start with a non-digit character** (the `v` or its OCR variant). So the robust check is simply: does the descriptor match the interval pattern AFTER stripping any leading non-digit characters?

**In `extractDescriptor`:** The existing logic already tries to match via `normalizeDescriptor` + `matchWorkoutType`. Since `intervalTypePattern` now includes `v?`, a descriptor like `v40:00/2:00r` will match.

### 5. Update `normalizeDescriptor` in TextPatternMatcher.swift

**Add two new steps after fix #5 and before `return result`:**

```swift
// 6. Strip trailing ellipsis + count from variable interval descriptors
// e.g., "v40:00/2:00r...4" → "v40:00/2:00r"
// The "...N" or "..N" is the rep count indicator the PM5 appends when truncating
result = result.replacingOccurrences(of: #"\.{2,}\d*$"#, with: "", options: .regularExpression)

// 7. Normalize variable interval prefix to "v"
// The PM5 "v" is frequently misread as W, w, V, и, ν, etc.
// If the string starts with non-digit character(s) followed by a digit+x pattern,
// replace the prefix with "v" for consistent downstream handling.
if let firstDigitIndex = result.firstIndex(where: { $0.isNumber }) {
    let prefix = String(result[result.startIndex..<firstDigitIndex])
    if !prefix.isEmpty {
        // Check that what follows looks like an interval: digit(s) then "x"
        let afterPrefix = String(result[firstDigitIndex...])
        if afterPrefix.contains("x") {
            result = "v" + afterPrefix
        }
    }
}
```

This ensures that regardless of what OCR reads the `v` as, the normalized descriptor always starts with `v` — making all downstream checks consistent.

### 6. Classify as variable intervals in Phase 3 (TableParserService.swift)

After extracting and matching the descriptor, use the `isVariable` flag returned by `parseIntervalWorkout`:

```swift
if let desc = descriptor {
    log("Attempting to parse as interval workout...")
    if let interval = matcher.parseIntervalWorkout(desc) {
        table.category = .interval
        table.isVariableInterval = interval.isVariable  // NEW FIELD — see section 9
        table.workoutType = desc  // Temporary — will be replaced after parsing for variable
        table.reps = interval.reps
        table.workPerRep = interval.isVariable ? nil : interval.workTime
        table.restPerRep = interval.restTime
        log("✓ Classified as \(interval.isVariable ? "VARIABLE " : "")INTERVALS")
        log("  Reps: \(interval.reps)")
        if !interval.isVariable {
            log("  Work per rep: \(interval.workTime)")
        }
        log("  Rest per rep: \(interval.restTime)")
    }
    // ... rest of existing classification logic
}
```

### 7. Filter rest rows in Phase 7 (TableParserService.swift)

Rest rows look like `r2:00  23` — they have `r` prefixed on the time and only 1-2 values. The existing junk detection catches `r\d+` patterns (like `r704` for rest meters), but rest rows have a different format: `rN:NN` for the rest duration.

**The rest row time `r2:00` will fail `matchTime` because of the `r` prefix**, so `parseDataRow` will likely reject these rows anyway (the time field won't validate). But to be explicit and avoid edge cases, add rest row detection.

**In `parseDataRow` (or before calling it in the Phase 7 loop), check if the row is a rest row:**

```swift
// In the Phase 7 loop, before calling parseDataRow:
for i in dataStartIndex..<rows.count {
    // Skip rest rows (variable intervals have rest rows interleaved)
    // Rest rows start with "r" followed by a time, e.g., "r2:00  23"
    let rowText = rows[i].normalizedText.trimmingCharacters(in: .whitespaces)
    if rowText.hasPrefix("r") && rowText.count >= 4 {
        // Check if it's "rN:NN" pattern (rest duration)
        let afterR = String(rowText.dropFirst())
        if matcher.matchTime(afterR) || matcher.matches(afterR, pattern: #"^\d{1,2}:\d{2}"#) {
            log("  Row \(i): skipped (rest row: '\(rows[i].joinedText)')")
            continue
        }
    }
    
    // Also check individual fragments — the "r2:00" might be a single fragment
    if let firstFragment = rows[i].fragments.first {
        let text = firstFragment.text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("r") && text.count >= 4 {
            let afterR = String(text.dropFirst())
            if matcher.matchTime(afterR) || matcher.matches(afterR, pattern: #"^\d{1,2}:\d{2}"#) {
                log("  Row \(i): skipped (rest row fragment: '\(text)')")
                continue
            }
        }
    }
    
    if let row = parseDataRow(rows[i], columnOrder: columnOrder) {
        dataRows.append(row)
        // ... existing logging
    }
}
```

**Note:** This rest row filtering is safe for ALL workout types, not just variable intervals. Fixed intervals don't have interleaved rest rows, so this code would never trigger. Single pieces don't have rest rows either.

### 8. Generate workout name after parsing (new step between Phase 7 and Phase 8)

For variable intervals, the workout name is generated from the parsed data rows' meters, not from the descriptor.

**Add after Phase 7 data row parsing, before Phase 8 fallback classification:**

```swift
// --- Variable Interval Naming ---
// For variable intervals, the descriptor is truncated and unreliable.
// Generate the workout name from the parsed interval meters.
if table.isVariableInterval == true && !dataRows.isEmpty {
    log("\n--- VARIABLE INTERVAL NAMING ---")
    let metersComponents = dataRows.compactMap { row -> String? in
        guard let meters = row.meters?.text else { return nil }
        return "\(meters)m"
    }
    if !metersComponents.isEmpty {
        let generatedName = metersComponents.joined(separator: " / ")
        table.workoutType = generatedName
        table.description = generatedName
        log("✓ Generated variable interval name: \"\(generatedName)\"")
    } else {
        log("⚠️ Could not generate variable interval name (no meters parsed)")
    }
}
```

**Example output:** For the image shown, this would produce:
```
✓ Generated variable interval name: "9737m / 9718m / 4860m / 4880m"
```

### 9. Data model changes

**Add `isVariableInterval` to `RecognizedTable`:**

```swift
struct RecognizedTable {
    // ... existing fields ...
    var isVariableInterval: Bool? = nil  // true for variable intervals, nil/false otherwise
}
```

**Or** add a new case to `WorkoutCategory`:

```swift
enum WorkoutCategory: String {
    case single
    case interval
    case intervalVariable  // NEW
}
```

The second approach (new enum case) is cleaner if the rest of the app needs to distinguish variable from fixed intervals (e.g., for display or export). If you go this route, update `detectWorkoutCategory`:

```swift
func detectWorkoutCategory(_ workoutType: String) -> WorkoutCategory {
    if workoutType.hasPrefix("v") && (workoutType.contains("/") || workoutType.hasSuffix("r")) {
        return .intervalVariable
    }
    if workoutType.contains("/") || workoutType.hasSuffix("r") {
        return .interval
    }
    return .single
}
```

**Recommendation:** Use whichever approach fits your existing UI/data model better. The `isVariableInterval` boolean is simpler if you just need a flag; the enum case is better if you want type-safe branching.

### 10. Update `parseIntervalWorkout` reps from data rows

For variable intervals, the `reps` extracted from the descriptor may not be reliable (the descriptor is truncated). The actual number of reps should come from the count of parsed data rows after Phase 7:

```swift
// After Phase 7, correct reps count for variable intervals
if table.isVariableInterval == true {
    table.reps = dataRows.count
    log("  Updated variable interval reps from data rows: \(dataRows.count)")
}
```

---

## Summary of Changes by File

| File | Change |
|------|--------|
| `TextPatternMatcher.swift` | Update `intervalTypePattern` to `[^\dx]*` prefix (any non-digit, non-x chars). Rewrite `parseIntervalWorkout` to strip non-digit prefix before parsing, return `isVariable` flag. Update `detectWorkoutCategory` to check first char instead of `hasPrefix("v")`. Add ellipsis stripping + prefix normalization to `normalizeDescriptor`. |
| `TableParserService.swift` | Phase 3: use `interval.isVariable` from return tuple. Phase 7: filter rest rows (`rN:NN` pattern). After Phase 7: generate workout name from interval meters for variable intervals. Correct reps count from data row count. |
| Data model (`RecognizedTable` or `WorkoutCategory`) | Add `isVariableInterval: Bool?` field OR add `.intervalVariable` enum case. |

## What NOT to Change

- `BoundingBoxAnalyzer.swift` — No changes needed
- `matchRate`, `matchMeters`, `matchSplit` — No changes needed
- Existing fixed interval parsing — The `v?` in the regex makes the `v` prefix optional, so fixed intervals continue to work identically
- Rest row junk detection (`r\d+`) — Keep this as-is for rest meters values like `r304`; the new rest row detection handles the `rN:NN` time format separately

## Testing

With the image shown (`v40:00/2:00r...4`), the expected result:

```
Category: interval (or intervalVariable)
isVariableInterval: true
Workout name: "9737m / 9718m / 4860m / 4880m"
Reps: 4
Rest per rep: 2:00

Summary: time=2:00:00.0, meters=29195, split=2:03.3, rate=22
Interval 1: time=40:00.0, meters=9737, split=2:03.2, rate=22, hr=149
Interval 2: time=40:00.0, meters=9718, split=2:03.4, rate=23, hr=152
Interval 3: time=20:00.0, meters=4860, split=2:03.4, rate=23, hr=159
Interval 4: time=20:00.0, meters=4880, split=2:02.9, rate=23
```

The rest rows (`r2:00  23`, `r2:00  13`, etc.) should be skipped entirely.
