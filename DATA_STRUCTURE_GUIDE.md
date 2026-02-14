# ErgScan Data Structure Guide

This document explains how workout data is saved in the ErgScan app, with detailed focus on distance, time, and splits for different workout types.

---

## Table of Contents

1. [Overview](#overview)
2. [Data Models](#data-models)
3. [Data Flow](#data-flow)
4. [Workout Types](#workout-types)
5. [Storage Details](#storage-details)
6. [CloudKit Sync](#cloudkit-sync)

---

## Overview

ErgScan uses a hierarchical data structure where:

- **Workout** = The top-level entity representing a rowing session
- **Interval** = A row of data from the erg monitor (intervals, splits, or averages)

The key insight is that **the Interval model is used for three different types of data**:
1. **Averages row** (orderIndex = 0) - Summary statistics for the entire workout
2. **Interval rows** (orderIndex ≥ 1) - For interval workouts (e.g., 3x4:00/3:00r)
3. **Split rows** (orderIndex ≥ 1) - For single piece workouts (e.g., 2000m, 30:00)

---

## Data Models

### Workout Model

Located in: `ErgScan1/Models/Workout.swift`

```swift
@Model
final class Workout {
    var id: UUID                      // Unique identifier
    var date: Date                    // Workout date (from OCR or user-selected)
    var workoutType: String           // e.g., "3x4:00/3:00r", "2000m", "30:00"
    var category: WorkoutCategory     // .single or .interval
    var totalTime: String             // Total elapsed time including rest (e.g., "33:00.0")
    var totalDistance: Int?           // Total meters (e.g., 2000, 3845)
    var imageData: Data?              // Compressed JPEG of erg monitor screen
    var intervals: [Interval]?        // All interval/split data (including averages)
    var ocrConfidence: Double         // Average OCR confidence (0.0-1.0)
    var wasManuallyEdited: Bool       // Whether user corrected OCR data
    var isErgTest: Bool               // Whether this is a test piece
    var intensityZone: String?        // Training zone (UT2, UT1, AT, TR, AN, Max)

    // User relationship
    var user: User?
    var userID: String?

    // CloudKit sync metadata
    var syncedToCloud: Bool
    var cloudKitRecordID: String?
    var lastSyncedAt: Date?
}
```

#### Computed Properties

The Workout model has two critical computed properties:

```swift
// Average split from the averages interval (orderIndex == 0)
var averageSplit: String? {
    intervals?.first(where: { $0.orderIndex == 0 })?.splitPer500m
}

// Work time (excluding rest) from the averages interval (orderIndex == 0)
var workTime: String {
    intervals?.first(where: { $0.orderIndex == 0 })?.time ?? totalTime
}
```

**Important distinction:**
- `totalTime` = Total elapsed time including rest periods (e.g., "33:00" for 3x10:00 with 1:00 rest)
- `workTime` = Actual work time excluding rest (e.g., "30:00" for the same workout)

---

### Interval Model

Located in: `ErgScan1/Models/Interval.swift`

```swift
@Model
final class Interval {
    var id: UUID
    var workout: Workout?             // Parent workout relationship
    var orderIndex: Int               // Position in the table (0 = averages, ≥1 = intervals/splits)

    // Data fields (all stored as strings to preserve OCR formatting)
    var time: String                  // e.g., "4:00.0", "6:30.5"
    var meters: String                // e.g., "1179", "500"
    var splitPer500m: String          // e.g., "1:41.2", "2:05.3"
    var strokeRate: String            // e.g., "29", "24"
    var heartRate: String?            // e.g., "145" (optional, only when HR monitor connected)

    // OCR confidence scores (0.0-1.0) for each field
    var timeConfidence: Double
    var metersConfidence: Double
    var splitConfidence: Double
    var rateConfidence: Double
    var heartRateConfidence: Double

    // CloudKit sync metadata
    var syncedToCloud: Bool
}
```

**Key Notes:**
- All data fields are stored as **strings** to preserve the exact OCR output formatting
- `orderIndex = 0` is **always** reserved for the averages/summary row
- `orderIndex ≥ 1` contains actual intervals or splits
- For **interval workouts**: each row is a separate interval
- For **single pieces**: each row is a split of the continuous piece

**Important: Time Field Behavior**
- For **distance pieces** (e.g., 2000m): `time` = duration of that split (e.g., "1:38.2")
- For **time pieces** (e.g., 30:00): `time` = **cumulative elapsed time** at split marker (e.g., "5:00.0", "10:00.0", "15:00.0")
- This matches what the erg monitor displays on screen

---

## Data Flow

### 1. OCR Scanning → RecognizedTable

When scanning an erg monitor, the OCR system produces a `RecognizedTable`:

```swift
struct RecognizedTable {
    var workoutType: String?          // e.g., "3x4:00/3:00r"
    var category: WorkoutCategory?    // .single or .interval
    var date: Date?                   // Extracted from monitor
    var totalTime: String?            // Total elapsed time
    var totalDistance: Int?           // Total meters
    var averages: TableRow?           // Summary row from monitor
    var rows: [TableRow]              // Individual intervals or splits
    var averageConfidence: Double     // Overall OCR confidence
}

struct TableRow {
    var time: OCRResult?
    var meters: OCRResult?
    var splitPer500m: OCRResult?
    var strokeRate: OCRResult?
    var heartRate: OCRResult?
}

struct OCRResult {
    let text: String                  // Recognized text
    let confidence: Float             // OCR confidence (0.0-1.0)
    let boundingBox: CGRect           // Location on screen
}
```

### 2. RecognizedTable → Workout + Intervals

When the user saves the workout, the data is converted:

**Step 1: Create Workout**
```swift
let workout = Workout(
    date: table.date ?? Date(),
    workoutType: table.workoutType ?? "Unknown",
    category: table.category ?? .single,
    totalTime: table.totalTime ?? "",
    totalDistance: table.totalDistance,
    ocrConfidence: table.averageConfidence
)
```

**Step 2: Create Averages Interval (orderIndex = 0)**
```swift
if let averages = table.averages {
    let averagesInterval = Interval(
        orderIndex: 0,
        time: averages.time?.text ?? "",          // Work time (no rest)
        meters: averages.meters?.text ?? "",      // Total distance
        splitPer500m: averages.splitPer500m?.text ?? "",
        strokeRate: averages.strokeRate?.text ?? "",
        heartRate: averages.heartRate?.text,
        timeConfidence: Double(averages.time?.confidence ?? 0),
        metersConfidence: Double(averages.meters?.confidence ?? 0),
        splitConfidence: Double(averages.splitPer500m?.confidence ?? 0),
        rateConfidence: Double(averages.strokeRate?.confidence ?? 0),
        heartRateConfidence: Double(averages.heartRate?.confidence ?? 0)
    )
    averagesInterval.workout = workout
}
```

**Step 3: Create Data Intervals/Splits (orderIndex ≥ 1)**
```swift
for (index, row) in table.rows.enumerated() {
    let interval = Interval(
        orderIndex: index + 1,                     // Start at 1
        time: row.time?.text ?? "",
        meters: row.meters?.text ?? "",
        splitPer500m: row.splitPer500m?.text ?? "",
        strokeRate: row.strokeRate?.text ?? "",
        heartRate: row.heartRate?.text,
        timeConfidence: Double(row.time?.confidence ?? 0),
        metersConfidence: Double(row.meters?.confidence ?? 0),
        splitConfidence: Double(row.splitPer500m?.confidence ?? 0),
        rateConfidence: Double(row.strokeRate?.confidence ?? 0),
        heartRateConfidence: Double(row.heartRate?.confidence ?? 0)
    )
    interval.workout = workout
}
```

---

## Workout Types

### 1. Interval Workout

**Example:** `3x4:00/3:00r` (3 intervals of 4 minutes, 3 minutes rest between)

**Data Structure:**
```
Workout {
    workoutType: "3x4:00/3:00r"
    category: .interval
    totalTime: "21:00.3"        // 12:00 work + 9:00 rest
    totalDistance: 3845
    intervals: [
        Interval(orderIndex: 0) {    // AVERAGES ROW
            time: "12:00.0"          // Work time only (no rest)
            meters: "3845"           // Total distance
            splitPer500m: "1:33.5"   // Average split
            strokeRate: "28"         // Average stroke rate
            heartRate: "152"         // Average heart rate
        },
        Interval(orderIndex: 1) {    // INTERVAL 1
            time: "4:00.2"
            meters: "1285"
            splitPer500m: "1:33.4"
            strokeRate: "29"
            heartRate: "148"
        },
        Interval(orderIndex: 2) {    // INTERVAL 2
            time: "4:00.1"
            meters: "1280"
            splitPer500m: "1:33.6"
            strokeRate: "28"
            heartRate: "153"
        },
        Interval(orderIndex: 3) {    // INTERVAL 3
            time: "4:00.0"
            meters: "1280"
            splitPer500m: "1:33.6"
            strokeRate: "27"
            heartRate: "156"
        }
    ]
}
```

**Key Points:**
- `totalTime` includes rest periods (21 minutes total)
- `workout.workTime` (from averages) excludes rest (12 minutes)
- Each interval is a separate `Interval` object
- `orderIndex = 0` contains the averages
- `orderIndex ≥ 1` contains individual interval data

---

### 2. Single Distance Piece

**Example:** `2000m`

**Data Structure:**
```
Workout {
    workoutType: "2000m"
    category: .single
    totalTime: "6:42.5"
    totalDistance: 2000
    intervals: [
        Interval(orderIndex: 0) {    // AVERAGES ROW
            time: "6:42.5"           // Total time
            meters: "2000"           // Total distance
            splitPer500m: "1:40.6"   // Average split
            strokeRate: "30"         // Average stroke rate
            heartRate: "178"         // Average heart rate
        },
        Interval(orderIndex: 1) {    // SPLIT 1 (0-500m)
            time: "1:38.2"
            meters: "500"
            splitPer500m: "1:38.2"
            strokeRate: "32"
            heartRate: "165"
        },
        Interval(orderIndex: 2) {    // SPLIT 2 (500-1000m)
            time: "1:40.1"
            meters: "500"
            splitPer500m: "1:40.1"
            strokeRate: "31"
            heartRate: "175"
        },
        Interval(orderIndex: 3) {    // SPLIT 3 (1000-1500m)
            time: "1:41.5"
            meters: "500"
            splitPer500m: "1:41.5"
            strokeRate: "30"
            heartRate: "180"
        },
        Interval(orderIndex: 4) {    // SPLIT 4 (1500-2000m)
            time: "1:42.7"
            meters: "500"
            splitPer500m: "1:42.7"
            strokeRate: "28"
            heartRate: "182"
        }
    ]
}
```

**Key Points:**
- `totalTime` and `workTime` are the same (no rest periods)
- Each split is a `500m` segment
- Splits show progression through the piece
- Erg monitors typically auto-split every 500m for distance pieces

---

### 3. Single Time Piece

**Example:** `30:00` (30 minute row)

**Data Structure:**
```
Workout {
    workoutType: "30:00"
    category: .single
    totalTime: "30:00.0"
    totalDistance: 7845
    intervals: [
        Interval(orderIndex: 0) {    // AVERAGES ROW
            time: "30:00.0"          // Total time
            meters: "7845"           // Total distance
            splitPer500m: "1:54.6"   // Average split
            strokeRate: "22"         // Average stroke rate
            heartRate: "145"         // Average heart rate
        },
        Interval(orderIndex: 1) {    // SPLIT 1 (at 5-minute mark)
            time: "5:00.0"           // Cumulative time marker (5 minutes elapsed)
            meters: "1310"
            splitPer500m: "1:54.2"
            strokeRate: "23"
            heartRate: "142"
        },
        Interval(orderIndex: 2) {    // SPLIT 2 (at 10-minute mark)
            time: "10:00.0"          // Cumulative time marker (10 minutes elapsed)
            meters: "1308"
            splitPer500m: "1:54.5"
            strokeRate: "22"
            heartRate: "145"
        },
        Interval(orderIndex: 3) {    // SPLIT 3 (at 15-minute mark)
            time: "15:00.0"          // Cumulative time marker (15 minutes elapsed)
            meters: "1305"
            splitPer500m: "1:54.8"
            strokeRate: "22"
            heartRate: "146"
        },
        // ... (continues: 20:00.0, 25:00.0, 30:00.0)
    ]
}
```

**Key Points:**
- `totalTime` and `workTime` are the same (no rest periods)
- Splits are time-based (typically 5-minute intervals)
- **Time values are cumulative markers** (5:00, 10:00, 15:00...), NOT split durations
- Distance varies per split based on pace
- Useful for steady-state training

---

## Storage Details

### SwiftData Storage

All data is stored locally using **SwiftData** (Apple's modern persistence framework):

- **Database:** SQLite database managed by SwiftData
- **Location:** App's container directory
- **Relationships:** Automatic cascade deletion (deleting a Workout deletes all its Intervals)
- **Queries:** Efficient predicate-based queries with indexes

**Example Query:**
```swift
@Query(sort: \Workout.date, order: .reverse)
private var allWorkouts: [Workout]

// Filter by user
let userWorkouts = allWorkouts.filter { $0.userID == currentUser.appleUserID }
```

### Field Storage Format

All numeric values are stored as **strings** to preserve OCR formatting:

| Field | Example Values | Notes |
|-------|---------------|-------|
| `time` | `"4:00.0"`, `"6:42.5"`, `"21:30.8"` | Minutes:Seconds.Tenths |
| `meters` | `"1179"`, `"2000"`, `"500"` | Integer meters |
| `splitPer500m` | `"1:33.5"`, `"2:05.3"` | Minutes:Seconds.Tenths per 500m |
| `strokeRate` | `"29"`, `"24"`, `"32"` | Strokes per minute |
| `heartRate` | `"145"`, `"178"`, `nil` | Beats per minute (optional) |

**Why strings?**
- Preserves exact OCR output
- Avoids rounding errors in time conversion
- Maintains decimal precision (e.g., "1:33.5" not 93.5 seconds)
- Allows easy display without reformatting

---

## CloudKit Sync

### Publishing to CloudKit

When a workout is saved, it's automatically published to CloudKit Public Database as a `SharedWorkout` record:

**CloudKit Record Structure:**
```
SharedWorkout {
    recordID: CKRecord.ID
    ownerID: String                    // User's Apple ID
    ownerUsername: String
    ownerDisplayName: String
    workoutType: String
    workoutDate: Date
    totalTime: String
    totalDistance: Int
    averageSplit: String
    intensityZone: String
    isErgTest: Bool
    localWorkoutID: String             // Maps to local Workout.id

    // Intervals stored as JSON arrays
    intervalsJSON: String              // JSON array of interval data
    ergImageData: Data?                // Compressed image
}
```

**Intervals JSON Format:**
```json
[
  {
    "orderIndex": 0,
    "time": "12:00.0",
    "meters": "3845",
    "splitPer500m": "1:33.5",
    "strokeRate": "28",
    "heartRate": "152"
  },
  {
    "orderIndex": 1,
    "time": "4:00.2",
    "meters": "1285",
    "splitPer500m": "1:33.4",
    "strokeRate": "29",
    "heartRate": "148"
  },
  // ...
]
```

### Friend Activity Feed

Friends can view each other's workouts through the CloudKit Public Database:

1. **Friend requests** create `FriendRequest` records with status "accepted"
2. **Load friends** queries for all accepted friendships
3. **Activity feed** queries `SharedWorkout` records for each friend
4. **Workout details** fetches full interval data from JSON when viewing a friend's workout

**Security:**
- Only metadata is publicly visible
- Full workout details require friendship
- Users control their own data via CloudKit permissions

---

## Summary

### Data Hierarchy

```
User
  └─ Workout (1 per rowing session)
       ├─ Metadata (type, date, distance, time)
       ├─ Image (JPEG of monitor screen)
       └─ Intervals (array of Interval objects)
            ├─ Interval (orderIndex=0) → AVERAGES
            ├─ Interval (orderIndex=1) → First interval/split
            ├─ Interval (orderIndex=2) → Second interval/split
            └─ ...
```

### Key Takeaways

1. **Averages are stored separately** as `orderIndex = 0`
2. **Intervals and splits use the same model** (Interval)
3. **All values are strings** to preserve OCR formatting
4. **Work time ≠ Total time** for interval workouts
5. **CloudKit sync is automatic** for sharing with friends
6. **Confidence scores track OCR quality** per field

---

## Related Files

- **Models:**
  - `ErgScan1/Models/Workout.swift`
  - `ErgScan1/Models/Interval.swift`
  - `ErgScan1/Models/OCRResult.swift`

- **Data Flow:**
  - `ErgScan1/ViewModels/ScannerViewModel.swift` (saveWorkout function)
  - `ErgScan1/Services/SocialService.swift` (CloudKit publishing)

- **Display:**
  - `ErgScan1/Views/EnhancedWorkoutDetailView.swift`
  - `ErgScan1/Views/Components/WorkoutFeedCard.swift`

---

*Last updated: February 2026*
