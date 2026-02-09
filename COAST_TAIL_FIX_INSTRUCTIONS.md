# Fix: Filter Coast/Cooldown Tail Row from Single Piece Workouts

## Problem

On single piece (non-interval) workouts, the PM5 often records a final partial row after the rower stops. For example, on a `20:11` workout where the rower stopped at 20:00, the display shows:

```
5:00.0    1280    1:57.1    19      ← real split
10:00.0   1279    1:57.2    19      ← real split
15:00.0   1275    1:57.6    19      ← real split
20:00.0   1275    1:57.6    19      ← real split
20:11.2   26      3:35.3    5       ← coast tail (stopped rowing)
```

The last row is not a real rowing split — it's the erg coasting after the rower stopped. It has:
- Very few meters (26m in 11 seconds)
- Very high split (3:35.3 /500m)
- Very low stroke rate (5 s/m)

The parser currently accepts this as a valid data row because it can assign at least 2 fields (time + split). This corrupts the workout data with a bogus final interval.

### How it gets through `parseDataRow`

Positional assignment for the coast row `20:11.2 | 26 | 3:35.3 | 5`:
- Index 0: `20:11.2` → TIME ✓ (matches time pattern)
- Index 1: `26` → METERS ✗ (`matchMeters` requires 3-5 digits)
- Index 2: `3:35.3` → SPLIT ✓ (matches split pattern `\d:\d{2}\.\d`)
- Index 3: `5` → RATE ✗ (`matchRate` requires 10-60 range, and `^\d{2}$` requires 2 digits)

Result: 2 valid fields (time + split), meets the minimum threshold of 2 → row accepted. But meters and rate are both nil, and the split is nonsensical.

## Fix

### In `TableParserService.swift` — Post-filter after Phase 7

**Location:** After the Phase 7 data row parsing loop (after line 205: `table.rows = dataRows`), add a check to remove a coast tail row.

**Logic:** If the last data row has nil stroke rate while the majority of other data rows have valid rates, drop it. This is the cleanest signal — a real rowing split always has a rate ≥ 10 s/m, while a coast tail has a rate so low (typically 0-9) that it fails the rate matcher entirely.

```swift
// --- Coast tail detection (after Phase 7) ---
// On single-piece workouts, the PM5 sometimes records a final partial row
// after the rower stops (very low rate, few meters). Drop it.
if dataRows.count >= 2 {
    let lastRow = dataRows.last!
    let otherRows = dataRows.dropLast()
    
    let lastHasRate = lastRow.strokeRate != nil
    let othersWithRate = otherRows.filter { $0.strokeRate != nil }.count
    
    if !lastHasRate && othersWithRate == otherRows.count {
        // Every other row has a valid rate, but the last one doesn't.
        // This is a coast/cooldown tail — remove it.
        log("  Removing coast tail row: time=\(lastRow.time?.text ?? "-"), rate=nil (all other rows have valid rates)")
        dataRows.removeLast()
    }
}
table.rows = dataRows
```

**Replace the existing `table.rows = dataRows` line (205) with this block.**

### Why check rate specifically?

- Rate is the strongest signal. Real rowing is always ≥ 18 s/m in practice, and the `matchRate` validator requires 10-60. A coast rate of 0-9 fails the 2-digit regex (`^\d{2}$`) and/or the range check.
- Meters can also fail (26m → 2 digits → fails `matchMeters`), but we shouldn't rely on meters alone since OCR might misread a valid meter count.
- Split technically passes validation (`3:35.3` matches the split pattern) even though it's unrealistic, so we can't filter on split alone.

### Why only drop the LAST row?

The coast tail is always the final row — it's the time between when the rower stopped and when the PM5 finalized the workout. It can't appear in the middle. Checking only the last row avoids accidentally removing a real split that happened to have an OCR misread on its rate.

### What about interval workouts?

Interval workouts won't have this issue — each interval has a fixed time/distance, and rest periods are shown on separate rest rows (which are already filtered by the `r\d+` junk detection on the meters value like `r304`). The coast tail only appears on single/just-row sessions.

However, the fix is safe for intervals too: if all interval rows have valid rates (which they will), the check would only fire if the last one didn't — which would be correct to drop in any case.

## What NOT to Change

- **`matchRate` validation** — Don't lower the minimum from 10. The 10-60 range is correct for real rowing.
- **`parseDataRow` minimum field count** — Don't raise it above 2. Other legitimate rows (like when meters fail OCR) need to pass with 2 fields.
- **Phase 7 parsing loop** — Don't try to detect coast rows during parsing. It's cleaner to post-filter after all rows are collected.
