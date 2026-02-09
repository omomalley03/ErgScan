# Heart Rate (HR) Parsing, Display, and Benchmark Instructions

## Context

The Concept2 PM5 monitor displays an optional heart rate column when a heart rate monitor is connected. The OCR correctly picks up these values (e.g., 131, 132, 144, 147, 149, 160), and the parser already has full infrastructure for HR:

- `Column.heartRate` enum case exists (TableParserService.swift line 36)
- `parseDataRow` already has the `.heartRate` assignment case (lines 549-554)
- `calculateAverageConfidence` already includes `row.heartRate` (line 641)

**The only missing piece:** `columnOrder` never includes `.heartRate` — it's always `[.time, .meters, .split, .rate]` (4 entries). HR values sit at index 4 in the values array but the assignment loop stops at index 3.

This document covers: (1) parser changes to detect and capture HR, (2) UI changes to display HR, and (3) benchmark changes to properly handle HR ground truth.

---

## Part 1: Parser Changes — Capture HR Data

### Problem Analysis from Debug Logs

**Test Case 18 (19:03 single workout) — HR values silently dropped:**

Each data row has 5 OCR fragments that become 5 values after normalization. The assignment loop iterates `columnOrder` which has 4 entries, so value at index 4 (HR) is never reached:

```
Row 6: '5:00,0 1265 1:58,5 20 144'
  Values (L-R): 5:00.0 | 1265 | 1:58.5 | 20 | 144
  Assigned '5:00.0' to TIME      ← index 0
  Assigned '1265' to METERS       ← index 1
  Assigned '1:58.5' to SPLIT      ← index 2
  Assigned '20' to RATE            ← index 3
  [144 at index 4 — NEVER REACHED] ← HR dropped!
  ✓ Row valid (4 fields)

Row 7: Values (L-R): 10:00.0 | 1267 | 1:58.3 | 20 | 147   ← 147 dropped
Row 8: Values (L-R): 15:00.0 | 1283 | 1:56.9 | 21 | 160   ← 160 dropped
Row 9: Values (L-R): 19:03.2 | 999 | 2:01.7 | 21 | 145    ← 145 dropped
```

**Test Case 19 (19:03, second capture) — Identical pattern:** Same 5 values per row, same HR values dropped.

**Test Cases 11-17 (2x20:00/1:15r) — HR present in OCR fragments:**
OCR captures HR in fragments like `'2:00.9 19 132'` (132 is HR) and `'2:00.7 19 131'` (131 is HR). When rows parse successfully, HR would be captured if `columnOrder` included `.heartRate`.

**Test Cases 1-7 (2000m) — NO HR in OCR:** Rows have 3-4 values only. No heart rate monitor.

**Test Cases 8-10 (5x1000m/7:00r) — NO HR in OCR:** Rows have 4 values only. No heart rate monitor.

### Summary of HR Data Presence

| Workout | Tests | HR in OCR? | HR Values | Current Status |
|---------|-------|------------|-----------|----------------|
| 2000m | 1-7 | No | — | Correctly nil |
| 5x1000m/7:00r | 8-10 | No | — | Correctly nil |
| 2x20:00/1:15r | 11-17 | Yes | 131, 132 | Not assigned — missing `.heartRate` in columnOrder |
| 19:03 | 18-19 | Yes | 144, 145, 147, 149, 160 | Present in values array but **never assigned** |

### Required Change

#### In `TableParserService.swift` — Add HR column detection between Phase 5 and Phase 6

**Where exactly:** After line 170 (the default column order fallback) and before line 173 (Phase 6 begins). This is after `columnOrder` is fully determined from headers + rate fallback, but before any data rows are parsed.

**Why here and not inside `determineColumnOrder`?** Because HR detection requires peeking at actual data row values, which `determineColumnOrder` (lines 404-467) doesn't have access to — it only looks at the header row.

**Why peek at data rows?** The PM5 header row shows `Time | Meters | /500m | s/m` — there is NO header for the HR column. HR values simply appear as an additional data column when a heart rate monitor is connected.

**Implementation — insert this between Phase 5 and Phase 6:**

```swift
// --- HR Column Detection (between Phase 5 and Phase 6) ---
// PM5 shows HR as a 5th column when a heart rate monitor is connected.
// There is no header for HR — detect it by peeking at data row values.
if !columnOrder.contains(.heartRate) {
    log("\n--- HR COLUMN DETECTION ---")
    
    // Peek at summary row + first 2 data rows
    let peekIndices = [summaryIndex, dataStartIndex, dataStartIndex + 1]
        .filter { $0 < rows.count }
    
    var rowsWithExtraHR = 0
    var sampleHRValues: [String] = []
    
    for peekIdx in peekIndices {
        let row = rows[peekIdx]
        // Extract values using same logic as parseDataRow
        var values: [String] = []
        for fragment in row.fragments {
            let normalized = matcher.normalize(fragment.text)
            if matcher.isJunk(fragment.text) || matcher.isJunk(normalized) { continue }
            if let combined = matcher.parseCombinedSplitRate(normalized) {
                values.append(combined.split)
                values.append(combined.rate)
                continue
            }
            let split = matcher.splitSmooshedText(normalized)
            values.append(contentsOf: split)
        }
        
        log("  Row \(peekIdx): \(values.count) values, columnOrder has \(columnOrder.count) columns")
        
        if values.count > columnOrder.count {
            // Check if trailing value(s) look like HR (integer 40-220)
            let extraValues = Array(values[columnOrder.count...])
            for val in extraValues {
                if let intVal = Int(val), intVal >= 40, intVal <= 220 {
                    rowsWithExtraHR += 1
                    sampleHRValues.append(val)
                    break
                }
            }
        }
    }
    
    if rowsWithExtraHR >= 2 {
        columnOrder.append(.heartRate)
        log("  ✓ Detected heart rate column (samples: \(sampleHRValues.joined(separator: ", ")))")
    } else {
        log("  No heart rate column detected (\(rowsWithExtraHR)/\(peekIndices.count) rows had extra HR-range values)")
    }
}
```

**Note:** `summaryIndex` and `dataStartIndex` are already computed before this point:
- `summaryIndex = anchorIndex + 4` (line 174)
- `dataStartIndex = anchorIndex + 5` (line 193)

You'll need to move `dataStartIndex` computation above this block (it's currently at line 193, inside Phase 7). Just compute it earlier — it's a simple constant.

**Why require ≥2 rows?** Avoids false positives from OCR noise in a single row. Two or more rows with consistent extra values in the 40-220 range is a reliable signal.

#### No changes needed to `parseDataRow`

The existing `.heartRate` case (lines 549-554) already handles assignment correctly:
```swift
case .heartRate:
    if let val = Int(text), val >= 40, val <= 220 {
        log("      Assigned '\(text)' to HEART RATE")
        tableRow.heartRate = ocr
        fieldCount += 1
    }
```
This works automatically once `.heartRate` is in `columnOrder`.

#### Update debug logging in Phase 6 & 7

**Phase 6 summary log (around line 183):** Add HR to the output:
```swift
log("  Rate:  \(avg.strokeRate?.text ?? "-")")
log("  HR:    \(avg.heartRate?.text ?? "-")")  // ADD THIS LINE
```

**Phase 7 data row log (line 199):** Add HR:
```swift
log("✓ Row \(i): time=\(row.time?.text ?? "-"), meters=\(row.meters?.text ?? "-"), split=\(row.splitPer500m?.text ?? "-"), rate=\(row.strokeRate?.text ?? "-"), hr=\(row.heartRate?.text ?? "-")")
```

#### Optional: Add `matchHeartRate` to TextPatternMatcher

Not required (the inline check in `parseDataRow` works), but for consistency with other field types:

```swift
// In TextPatternMatcher.swift
func matchHeartRate(_ text: String) -> Bool {
    guard let val = Int(text), val >= 40, val <= 220 else { return false }
    return true
}
```

And update `matchesAnyPattern` (line 417-419) to include it:
```swift
func matchesAnyPattern(_ text: String) -> Bool {
    matchTime(text) || matchSplit(text) || matchMeters(text) ||
    matchRate(text) || matchHeartRate(text) || matchDate(text) != nil || matchWorkoutType(text)
}
```

This helps `splitSmooshedText` correctly recognize HR values when splitting space-separated text. Currently `'144'` fails the `allValid` check in `splitSmooshedText` because `matchesAnyPattern` doesn't recognize it. This hasn't caused problems because `'20'` and `'144'` typically arrive as separate OCR fragments, but adding this makes splitting more robust.

---

## Part 2: App UI Changes — Display and Save HR Data

### Display HR in the scan results table view

1. **Show the HR column conditionally:** Only display when at least one row (data or averages) has a non-nil `heartRate`. Prevents empty HR column for workouts without a monitor.

2. **Display format:** Plain integer (e.g., "144"). No units — always BPM.

3. **Column position:** Rightmost column, after Rate. Same styling as Rate.

### Save HR data

1. Save `heartRate` as `Int?`. When HR is not available, store as `nil` (not 0).
2. Add optional `heartRate: Int?` to the interval/row data model if not already present.

---

## Part 3: Benchmark Changes — Ground Truth and Evaluation

### Problem with current ground truth

Current benchmark sets `HR: 0` for ALL test cases, even ones with visible HR data. This is wrong:
- Workouts WITH HR: ground truth should be the actual values (e.g., 144)
- Workouts WITHOUT HR: ground truth should be `nil` (not 0)

### Required changes

1. **Ground truth data model:** Change HR from `Int` (default 0) to `Int?` (default nil). Display nil as "-" in reports.

2. **Update existing ground truth entries:**

   Workouts WITH HR:
   - **19:03 workout (Tests 18-19):** Interval 1 HR=144, Interval 2 HR=147, Interval 3 HR=160, Interval 4 HR=145. Summary HR=149.
   - **2x20:00/1:15r workout (Tests 11-17):** Interval 1 HR=132, Interval 2 HR=131. Summary HR≈131-132 (verify from screen).
   
   Workouts WITHOUT HR:
   - **2000m (Tests 1-7):** HR=nil for all intervals
   - **5x1000m/7:00r (Tests 8-10):** HR=nil for all intervals

3. **Scoring logic:**
   - GT=nil, Parsed=nil → ✓
   - GT=nil, Parsed=value → ✗ (false positive)
   - GT=value, Parsed=value, match → ✓
   - GT=value, Parsed=nil → ✗ (missed HR)
   - GT=value, Parsed≠value → ✗ (wrong HR)

4. **Display:** `HR: ✓ GT="144" Parsed="144"` or `HR: ✓ GT="nil" Parsed="nil"`

---

## Summary of Changes by File

| File | Change |
|------|--------|
| `TableParserService.swift` | Add HR detection block between Phase 5 and Phase 6: peek at data rows, if ≥2 have extra values in 40-220, append `.heartRate` to `columnOrder`. Update Phase 6/7 debug logs to include HR. Move `dataStartIndex` computation earlier. |
| `TextPatternMatcher.swift` | Optional: add `matchHeartRate()` and include in `matchesAnyPattern()` |
| Scan results view (UI) | Show HR column conditionally |
| Workout data model | HR stored as `Int?` (nil, not 0) |
| Benchmark ground truth model | HR from `Int` (default 0) to `Int?` (default nil) |
| Benchmark ground truth data | Real HR values where visible, nil where not |
| Benchmark scoring | nil-vs-nil = ✓, remove 0 special-casing |

## What NOT to Change

- `BoundingBoxAnalyzer.swift` — No changes needed
- `parseDataRow` — The `.heartRate` case (lines 549-554) is already correct
- `Column` enum — `.heartRate` already exists (line 36)
- `calculateAverageConfidence` — Already includes `row.heartRate` (line 641)
