# Concept2 Erg Screen OCR Parsing Instructions

## Overview

You are building a parser that takes raw OCR text detections (with X/Y coordinates) from a Concept2 PM5 rowing ergometer screen and produces structured workout data. The parser must classify workouts, extract results, and present them in a scrollable UI.

---

## 1. Screen Layout & Row Detection

OCR detections arrive as text fragments with bounding box coordinates. Group them into logical rows using Y-coordinate clustering:

- **Sort** all detections by Y-coordinate (top to bottom).
- **Cluster** detections into rows: if two detections have Y-coordinates within ~5% of screen height of each other, they belong to the same row.
- **Within each row**, sort detections left to right by X-coordinate.
- **Join** the text fragments in each row with spaces to form the row's text content.

The PM5 "View Detail" screen has a consistent vertical structure:

| Zone | Typical Rows | Content |
|------|-------------|---------|
| **Header** | Rows 0–1 | "Concept 2.", "PM5" (device branding — ignore) |
| **Screen Title** | Row 2 | "View Detail" |
| **Workout Descriptor** | Row 3 | The workout definition, e.g. `3x20:00/1:15r` or `5000m` or `2:00:00` |
| **Date & Summary** | Row 4 | Date and total time/distance, e.g. `Oct 20 2024  1:03:45.0` |
| **Column Headers** | Row 5 | `time  meter  /500m  s/m  ♥` (may contain OCR errors) |
| **Data Rows** | Rows 6+ | Numeric results — one row per interval or split |
| **Footer** | Last row(s) | Rest info like `r46` (rest heart rate — optional) |

**Important:** Row indices are approximate. Use content matching, not fixed row numbers.

---

## 2. Workout Type Classification

### Step 1: Find the Workout Descriptor

Scan rows near the top of the screen (roughly rows 2–4) for the workout definition string. This is the **primary classification signal**.

### Step 2: Classify as "intervals" or "single"

**Intervals** — the descriptor contains an `x` indicating repetitions AND a trailing `r` indicating rest:

```
Pattern: {reps}x{work_target}/{rest_duration}r
```

Examples:
- `3x20:00/1:15r` → 3 intervals of 20 minutes, 1:15 rest
- `4x1000m/2:00r` → 4 intervals of 1000m, 2:00 rest
- `8x500m/1:00r` → 8 intervals of 500m, 1:00 rest
- `5x1500m/3:00r` → 5 intervals of 1500m, 3:00 rest
- `6x3:00/1:00r` → 6 intervals of 3 minutes, 1:00 rest

Regex (apply to cleaned row text):
```
/(\d+)\s*x\s*([\d:]+m?)\s*\/\s*([\d:]+)\s*r/i
```

Capture groups: (1) reps, (2) work target (time or distance), (3) rest duration.

**Single** — the descriptor is a plain distance or time with no `x` and no trailing `r`:

```
Distance: 5000m, 10000m, 2000m, 21097m (half marathon), 42195m (marathon)
Time:     30:00, 1:00:00, 2:00:00, 0:30
```

Regex options:
```
Distance: /^(\d+)\s*m$/i
Time:     /^(\d{1,2}:)?\d{1,2}:\d{2}$/
```

### Step 3: Handle OCR Noise in Descriptor

Common OCR errors to account for:
- `tirne` → `time`, `rneter` → `meter`, `rnin` → `min`
- `0` ↔ `O`, `1` ↔ `l` ↔ `I`, `5` ↔ `S`
- Missing or extra spaces around `x`, `/`, `r`
- The letter `r` at the end may be detected as a separate text fragment — look for it

If the descriptor doesn't match either pattern cleanly, fall back to counting data rows (see Section 4).

---

## 3. Extract Workout Metadata

From the header/summary zone, extract:

| Field | Source | Example |
|-------|--------|---------|
| `workout_type` | Classification above | `"intervals"` or `"single"` |
| `date` | Date row | `"2024-10-20"` (ISO format) |
| `description` | Raw descriptor string | `"3x20:00/1:15r"` |
| `total_time` | "Total Time:" value | `"1:03:45.0"` |
| `total_distance` | Sum of data row meters (or from summary) | `15004` |
| `reps` | From descriptor (intervals only) | `3` |
| `work_per_rep` | From descriptor (intervals only) | `"20:00"` or `"1000m"` |
| `rest_per_rep` | From descriptor (intervals only) | `"1:15"` |

---

## 4. Parse Data Rows

### Identify Column Headers

Find the row containing the column header labels. Fuzzy-match these terms:
- `time` (OCR may read `tirne`, `tirrie`)
- `meter` (OCR may read `rneter`, `rneler`)
- `/500m` (the split — OCR may read `/500rn`, `/S00m`)
- `s/m` (strokes per minute)
- `♥` or a heart symbol (heart rate — may be missing or garbled)

### Extract Data Rows

Every row **below** the column headers that contains numeric data is a data row. Each should have values aligning with the columns:

| Column | Type | Example | Notes |
|--------|------|---------|-------|
| `time` | Duration | `20:00.0`, `1:00:00.0` | Cumulative for singles, per-interval for intervals |
| `meter` | Integer | `5014`, `15004` | Distance in meters |
| `/500m` | Duration | `1:59.6` | Pace per 500m — always `M:SS.s` format |
| `s/m` | Integer | `19`, `28` | Stroke rate |
| `♥` | Integer | `145` | Heart rate (optional, may be absent) |

### Intervals vs Single — Data Row Interpretation

**For intervals (`workout_type: "intervals"`):**
- The **first data row** is the **overall summary** (total time, total meters, average pace, average s/m).
- Subsequent data rows are **individual interval results** (one per rep).
- Validate: number of interval rows should equal `reps` from the descriptor.
- If there's a mismatch, trust the actual data rows and adjust `reps`.

**For single pieces (`workout_type: "single"`):**
- The **first data row** is the **overall summary**.
- Subsequent data rows are **splits** (typically per-500m, per-1000m, or per-5:00 depending on distance/time).
- All splits belong to one continuous piece.

### Fallback Classification

If the descriptor was unreadable, classify based on data rows:
- If the first data row's `time` value is significantly larger than subsequent rows (e.g. 1:03:45 vs 20:00), and subsequent rows have similar `time` values → **intervals** (first row = summary, rest = reps).
- If data rows show incrementally increasing `meter` values → **single** with splits.

---

## 5. Output Data Structure

```json
{
  "workout_type": "intervals",       // "intervals" or "single"
  "date": "2024-10-20",
  "description": "3x20:00/1:15r",
  "reps": 3,                         // null for single
  "work_per_rep": "20:00",           // null for single
  "rest_per_rep": "1:15",            // null for single
  "total_time": "1:03:45.0",
  "total_distance": 15004,

  "summary": {
    "time": "1:00:00.0",
    "distance": 15004,
    "avg_split": "1:59.9",
    "avg_stroke_rate": 19,
    "avg_heart_rate": null
  },

  "intervals": [
    {
      "rep": 1,
      "time": "20:00.0",
      "distance": 5014,
      "split": "1:59.6",
      "stroke_rate": 19,
      "heart_rate": null
    },
    {
      "rep": 2,
      "time": "20:00.0",
      "distance": 5001,
      "split": "1:59.9",
      "stroke_rate": 19,
      "heart_rate": null
    },
    {
      "rep": 3,
      "time": "20:00.0",
      "distance": 4989,
      "split": "2:00.2",
      "stroke_rate": 19,
      "heart_rate": null
    }
  ]
}
```

For a **single piece**, the structure is the same but:
- `workout_type` is `"single"`
- `reps`, `work_per_rep`, `rest_per_rep` are `null`
- The array is named `"splits"` instead of `"intervals"`
- Each entry has a `"split_number"` instead of `"rep"`

---

## 6. UI Display — Scrollable Result View

### Layout

Present the parsed workout in a scrollable view with two sections:

#### A. Summary Card (sticky/top)

Always visible at the top. Shows:

```
┌─────────────────────────────────────┐
│  3x20:00 / 1:15r          INTERVALS│
│  Oct 20, 2024                       │
│─────────────────────────────────────│
│  Total Time    1:03:45.0            │
│  Total Meters  15,004               │
│  Avg Split     1:59.9 /500m         │
│  Avg S/M       19                   │
└─────────────────────────────────────┘
```

- For **intervals**: badge/label says "INTERVALS" with rep count, e.g. "3 × 20:00"
- For **single**: badge/label says "SINGLE" with the target, e.g. "5,000m" or "30:00"
- Use the description string prominently
- Display the date

#### B. Scrollable Rep/Split List (below summary)

A vertically scrollable list of cards or rows, one per interval or split:

**For intervals:**
```
┌─ Rep 1 ─────────────────────────────┐
│  Time: 20:00.0    Distance: 5,014m  │
│  Split: 1:59.6    S/M: 19           │
├─ Rep 2 ─────────────────────────────┤
│  Time: 20:00.0    Distance: 5,001m  │
│  Split: 1:59.9    S/M: 19           │
├─ Rep 3 ─────────────────────────────┤
│  Time: 20:00.0    Distance: 4,989m  │
│  Split: 2:00.2    S/M: 19           │
└─────────────────────────────────────┘
```

**For single piece splits:**
```
┌─ Split 1 ────────────────────────────┐
│  Time: 5:00.0     Distance: 2,512m   │
│  Split: 1:59.4    S/M: 20            │
├─ Split 2 ────────────────────────────┤
│  ...                                  │
```

### Visual Cues

- **Highlight fastest/slowest** rep or split (green for fastest pace, red for slowest).
- **Color-code the workout type**: e.g. blue badge for intervals, green badge for single.
- Show heart rate column only if heart rate data is present.
- Number formatting: commas for meters (5,014), colon-separated for times.

---

## 7. Parsing Priority & Error Handling

1. **Always trust the descriptor first** for classification. It's the most reliable signal.
2. **Cross-validate** with data row count: if descriptor says 3 reps, expect 3 data rows after the summary.
3. **If descriptor is unreadable**, fall back to data row analysis (see Section 4 fallback).
4. **If data rows don't match expected count**, flag a warning but still display what was found.
5. **Apply OCR corrections** liberally: common substitutions for `m`/`rn`, `0`/`O`, `1`/`l`/`I`, `5`/`S`.
6. **Validate numeric ranges**: split should be `0:30–4:00`, stroke rate `14–50`, heart rate `40–220`, distance > 0.
7. **If a field can't be parsed**, set it to `null` and still display the rest.

---

## 8. Test Cases to Support

| Descriptor | Type | Reps | Work | Rest |
|-----------|------|------|------|------|
| `3x20:00/1:15r` | intervals | 3 | 20:00 | 1:15 |
| `4x1000m/2:00r` | intervals | 4 | 1000m | 2:00 |
| `8x500m/1:00r` | intervals | 8 | 500m | 1:00 |
| `10x1:00/1:00r` | intervals | 10 | 1:00 | 1:00 |
| `5000m` | single | — | — | — |
| `10000m` | single | — | — | — |
| `2000m` | single | — | — | — |
| `30:00` | single | — | — | — |
| `1:00:00` | single | — | — | — |
| `42195m` | single | — | — | — |

---

## 9. Example: Parsing the 3x20:00 Workout

Given these OCR rows:

```
Row 0: "LIVE"
Row 1: "Iconcept 2.", "PM5"
Row 2: "View Detail"
Row 3: "3x20:00/1:15r", "Total Time:"
Row 4: "0d", "20 2024", "1:03:45.0"
Row 5: "tirne", "meter", "1500m", "E"
Row 6: "1:00:00.0", "15004", "1:59.9", "19"
Row 7: "20:00:0", "5014", "1:59.6", "19"
Row 8: "20:00.0", "5001", "1:59.9", "19"
Row 9: "20:00.0", "4989", "2:00.2", "19"
```

**Parsing steps:**

1. Find descriptor in Row 3: `3x20:00/1:15r` → matches interval pattern → `type: "intervals"`, `reps: 3`, `work: "20:00"`, `rest: "1:15"`
2. Find date in Row 4: reconstruct as `Oct 20 2024` (OCR mangled `Oct` to `0d`)
3. Find total time in Row 3–4: `1:03:45.0`
4. Row 5 is column headers (fuzzy match `tirne` → `time`)
5. Row 6 is summary row (total): time `1:00:00.0`, meters `15004`, split `1:59.9`, s/m `19`
6. Rows 7–9 are the 3 interval results
7. Confirm: 3 data rows = 3 reps ✓
8. Output structured JSON and render the scrollable UI
