# Power Curve Implementation for ErgScan

## Overview

Implement a power-duration curve feature in the ErgScan iOS app. The power curve tracks a rower's best wattage output at every duration they've rowed, built by analyzing all saved workouts and their splits/intervals. This is a core analytics feature that lets rowers see their peak performance across all durations.

---

## What Is a Power Curve?

A power curve maps **duration (seconds) → best average watts** across all workouts. It answers: "What is the best average power I've sustained for X seconds?"

For **single piece workouts** (category `.single`), it is built by examining **every contiguous combination of splits** within the piece. For example, a piece with 4 splits produces combinations of 1 consecutive split, 2 consecutive splits, 3 consecutive splits, and 4 consecutive splits — each representing a different duration. For each combination, we compute the average watts over that time window and keep only the best value for each duration.

For **interval workouts** (category `.interval`), each interval is treated as an **independent single-split piece** — intervals are never combined with each other because there is rest between them.

The curve must be **monotonically decreasing** — you cannot sustain more power for a longer duration than a shorter one. Any violations are cleaned up by removing dominated points.

---

## Data Flow: ErgScan Workouts → Power Curve

### Source Data: Workout + Interval Models

Each `Workout` has an array of `Interval` objects. Recall:
- `orderIndex == 0` → **Averages row** (summary — skip this for power curve building)
- `orderIndex >= 1` → **Individual splits/intervals** (use these)

Each `Interval` has these relevant string fields:
- `time` — e.g. `"4:00.2"` (format: `M:SS.s` or `MM:SS.s`)
- `meters` — e.g. `"1285"`
- `splitPer500m` — e.g. `"1:33.4"` (split pace per 500m)
- `strokeRate` — e.g. `"29"`
- `heartRate` — e.g. `"148"` (optional)

### CRITICAL: Cumulative vs Per-Split Data

The erg monitor reports data differently depending on workout type, and the `time` and `meters` fields as stored in the `Interval` model reflect the **raw OCR output from the monitor**. This means:

#### Single Distance Workouts (e.g. `2000m`)
- **`meters` is CUMULATIVE** — each split shows the running total of meters rowed so far
- **`time` is PER-SPLIT** — each split shows the time for that chunk only
- Example for a 2000m with 500m splits:
  ```
  orderIndex 1: time="1:38.2"  meters="500"    ← 0–500m chunk
  orderIndex 2: time="1:40.1"  meters="1000"   ← 500–1000m chunk
  orderIndex 3: time="1:41.5"  meters="1500"   ← 1000–1500m chunk
  orderIndex 4: time="1:42.7"  meters="2000"   ← 1500–2000m chunk
  ```
- To get per-split distance: `split_distance = current_meters - previous_meters`
- The time values are already per-split, use them directly

#### Single Time Workouts (e.g. `30:00`)
- **`time` is CUMULATIVE** — each split shows the elapsed time so far
- **`meters` is PER-SPLIT** — each split shows the meters rowed in that chunk only
- Example for a 30:00 with 6-minute splits:
  ```
  orderIndex 1: time="6:00.0"   meters="1571"   ← 0:00–6:00 chunk
  orderIndex 2: time="12:00.0"  meters="1568"   ← 6:00–12:00 chunk
  orderIndex 3: time="18:00.0"  meters="1572"   ← 12:00–18:00 chunk
  orderIndex 4: time="24:00.0"  meters="1565"   ← 18:00–24:00 chunk
  orderIndex 5: time="30:00.0"  meters="1569"   ← 24:00–30:00 chunk
  ```
- To get per-split time: `split_time = current_time - previous_time`
- The meters values are already per-split, use them directly

#### Interval Workouts (e.g. `3x4:00/3:00r`)
- Each interval is a standalone row — **neither field is cumulative across intervals**
- `time` = the time for that interval
- `meters` = the distance for that interval
- **Do NOT combine intervals** — there is rest between them that is not captured in the data
- Each interval becomes a single independent power curve point

### Conversion Formulas

These are critical. Use the standard Concept2 erg power formula:

```swift
/// Convert a /500m split (in seconds) to watts
func splitToWatts(_ splitSeconds: Double) -> Double {
    return 2.80 / pow(splitSeconds / 500.0, 3)
}

/// Convert watts back to a /500m split (in seconds)
func wattsToSplit(_ watts: Double) -> Double {
    return 500.0 * pow(2.80 / watts, 1.0 / 3.0)
}

/// Parse a time/split string like "1:33.4" or "12:00.0" into total seconds
func timeStringToSeconds(_ timeStr: String) -> Double? {
    let parts = timeStr.split(separator: ":")
    guard parts.count == 2,
          let minutes = Double(parts[0]),
          let seconds = Double(parts[1]) else {
        return nil
    }
    return minutes * 60.0 + seconds
}

/// Format seconds back to split string "M:SS.s"
func secondsToSplitString(_ totalSeconds: Double) -> String {
    let minutes = Int(totalSeconds / 60.0)
    let seconds = totalSeconds.truncatingRemainder(dividingBy: 60.0)
    return String(format: "%d:%04.1f", minutes, seconds)
}
```

---

## The Power Curve Algorithm

### Step 1: Parse Splits Into Per-Split (time, distance) Pairs

This is the most important step and varies by workout category and type. The goal is to produce an array of `(timeSeconds: Double, distanceM: Double)` tuples where both values represent **that split only** (not cumulative).

```swift
struct ParsedSplit {
    let timeSeconds: Double
    let distanceM: Double
}

/// Determine if a workout type string represents a distance workout.
/// Distance types look like "2000m", "5000m", "500m", etc.
/// Time types look like "30:00", "20:00", "60:00", etc.
func isDistanceWorkoutType(_ workoutType: String) -> Bool {
    return workoutType.lowercased().hasSuffix("m")
}

func parseSplits(from workout: Workout) -> [ParsedSplit] {
    let intervals = (workout.intervals ?? [])
        .filter { $0.orderIndex >= 1 }
        .sorted { $0.orderIndex < $1.orderIndex }
    
    guard !intervals.isEmpty else { return [] }
    
    if workout.category == .interval {
        // ----- INTERVAL WORKOUT -----
        // Each interval is independent. time and meters are per-interval, not cumulative.
        return intervals.compactMap { interval in
            guard let timeSeconds = timeStringToSeconds(interval.time),
                  let distanceM = Double(interval.meters),
                  timeSeconds > 0, distanceM > 0 else {
                return nil
            }
            return ParsedSplit(timeSeconds: timeSeconds, distanceM: distanceM)
        }
    }
    
    // ----- SINGLE PIECE WORKOUT -----
    if isDistanceWorkoutType(workout.workoutType) {
        // SINGLE DISTANCE (e.g., "2000m"):
        //   meters is CUMULATIVE, time is PER-SPLIT
        var previousCumulativeMeters: Double = 0
        return intervals.compactMap { interval in
            guard let timeSeconds = timeStringToSeconds(interval.time),
                  let cumulativeMeters = Double(interval.meters),
                  timeSeconds > 0 else {
                return nil
            }
            let splitDistance = cumulativeMeters - previousCumulativeMeters
            previousCumulativeMeters = cumulativeMeters
            guard splitDistance > 0 else { return nil }
            return ParsedSplit(timeSeconds: timeSeconds, distanceM: splitDistance)
        }
    } else {
        // SINGLE TIME (e.g., "30:00"):
        //   time is CUMULATIVE, meters is PER-SPLIT
        var previousCumulativeTime: Double = 0
        return intervals.compactMap { interval in
            guard let cumulativeTime = timeStringToSeconds(interval.time),
                  let distanceM = Double(interval.meters),
                  distanceM > 0 else {
                return nil
            }
            let splitTime = cumulativeTime - previousCumulativeTime
            previousCumulativeTime = cumulativeTime
            guard splitTime > 0 else { return nil }
            return ParsedSplit(timeSeconds: splitTime, distanceM: distanceM)
        }
    }
}
```

### Step 2: Generate Power Curve Points From Parsed Splits

The logic differs by workout category:

**For single piece workouts (`category == .single`):** Generate all contiguous split combinations. A workout with `n` splits produces blocks of length 1 through n:

```
for block_length in 1...n {
    for start_index in 0...(n - block_length) {
        let block = splits[start_index ..< start_index + block_length]
        
        let totalTime = sum of timeSeconds in block
        let totalDistance = sum of distanceM in block
        
        if totalDistance == 0 { continue }
        
        let avgSplitSeconds = totalTime / totalDistance * 500.0
        let avgWatts = splitToWatts(avgSplitSeconds)
        
        // Update the power curve at duration = totalTime with avgWatts
    }
}
```

This is O(n²) per workout which is fine — workouts rarely have more than ~20 splits.

**For interval workouts (`category == .interval`):** Each interval is a single independent point. Do NOT combine intervals:

```
for split in parsedSplits {
    let avgSplitSeconds = split.timeSeconds / split.distanceM * 500.0
    let avgWatts = splitToWatts(avgSplitSeconds)
    
    // Update the power curve at duration = split.timeSeconds with avgWatts
}
```

### Step 3: Update the Power Curve

The power curve is a dictionary: `[Double: Double]` mapping `duration_seconds → best_watts`.

When inserting a new (duration, watts) point:

1. **Check if dominated:** If there already exists a point in the curve with a duration >= this duration AND watts >= this watts, then this new point is dominated and should be skipped.

2. **Update:** If not dominated, check if the exact duration key exists. If it does, keep the higher watts. If not, insert the new point.

```swift
func isDominated(duration: Double, watts: Double, curve: [Double: Double]) -> Bool {
    for (existingDuration, existingWatts) in curve {
        if existingDuration >= duration && existingWatts >= watts {
            return true
        }
    }
    return false
}

func updatePowerCurve(duration: Double, watts: Double, curve: inout [Double: Double]) {
    if isDominated(duration: duration, watts: watts, curve: curve) {
        return
    }
    
    let key = (duration * 100).rounded() / 100  // Round to 2 decimal places
    if let existing = curve[key] {
        if watts > existing {
            curve[key] = watts
        }
    } else {
        curve[key] = watts
    }
}
```

### Step 4: Enforce Monotonicity

After building the full curve, clean it so power is monotonically decreasing with duration. Walk from the **longest duration to the shortest**, tracking the max power seen. Any shorter-duration point with power less than the max so far is dominated and should be removed.

```swift
func enforceMonotonicity(_ curve: [Double: Double]) -> [Double: Double] {
    // Sort by duration descending (longest first)
    let sorted = curve.sorted { $0.key > $1.key }
    
    var cleaned: [Double: Double] = [:]
    var maxPowerSoFar: Double = 0
    
    for (duration, watts) in sorted {
        if watts >= maxPowerSoFar {
            cleaned[duration] = watts
            maxPowerSoFar = watts
        }
        // else: shorter duration is weaker than a longer one → skip
    }
    
    return cleaned
}
```

### Full Rebuild Function

```swift
func rebuildPowerCurve(from workouts: [Workout]) -> [Double: Double] {
    var curve: [Double: Double] = [:]
    
    for workout in workouts {
        let parsedSplits = parseSplits(from: workout)
        let n = parsedSplits.count
        guard n > 0 else { continue }
        
        if workout.category == .interval {
            // INTERVAL: each interval is an independent single point
            for split in parsedSplits {
                guard split.distanceM > 0 else { continue }
                let avgSplitSeconds = split.timeSeconds / split.distanceM * 500.0
                let avgWatts = splitToWatts(avgSplitSeconds)
                updatePowerCurve(duration: split.timeSeconds, watts: avgWatts, curve: &curve)
            }
        } else {
            // SINGLE PIECE: iterate all contiguous blocks of splits
            for blockLength in 1...n {
                for startIndex in 0...(n - blockLength) {
                    let block = Array(parsedSplits[startIndex ..< startIndex + blockLength])
                    
                    let totalTime = block.reduce(0) { $0 + $1.timeSeconds }
                    let totalDistance = block.reduce(0) { $0 + $1.distanceM }
                    
                    guard totalDistance > 0 else { continue }
                    
                    let avgSplitSeconds = totalTime / totalDistance * 500.0
                    let avgWatts = splitToWatts(avgSplitSeconds)
                    
                    updatePowerCurve(duration: totalTime, watts: avgWatts, curve: &curve)
                }
            }
        }
    }
    
    return enforceMonotonicity(curve)
}
```

---

## Implementation Plan for ErgScan Xcode Project

### File Structure

Create these new files:

```
ErgScan1/
├── Models/
│   └── PowerCurve.swift              // PowerCurvePoint model (if persisting with SwiftData)
├── Services/
│   └── PowerCurveService.swift       // All power curve logic
├── Views/
│   └── PowerCurveView.swift          // Chart view for the power curve
└── ViewModels/
    └── PowerCurveViewModel.swift     // Drives the view
```

### 1. `PowerCurveService.swift`

This is the core service. It should contain:

- All the conversion functions (`splitToWatts`, `wattsToSplit`, `timeStringToSeconds`, `secondsToSplitString`)
- The `ParsedSplit` struct
- `parseSplits(from:)` — the de-cumulation logic described above
- `isDistanceWorkoutType(_:)` — checks if `workoutType` ends with "m"
- `rebuildPowerCurve(from:)` — the full rebuild function
- `updatePowerCurve(duration:watts:curve:)`
- `isDominated(duration:watts:curve:)`
- `enforceMonotonicity(_:)`

Make this a class or an actor if you need thread safety. The rebuild can be expensive if there are many workouts, so consider running it on a background thread.

```swift
import Foundation

class PowerCurveService {
    
    // MARK: - Parsed Split
    
    struct ParsedSplit {
        let timeSeconds: Double
        let distanceM: Double
    }
    
    // MARK: - Conversion Utilities
    
    static func splitToWatts(_ splitSeconds: Double) -> Double {
        return 2.80 / pow(splitSeconds / 500.0, 3)
    }
    
    static func wattsToSplit(_ watts: Double) -> Double {
        return 500.0 * pow(2.80 / watts, 1.0 / 3.0)
    }
    
    static func timeStringToSeconds(_ timeStr: String) -> Double? {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        return minutes * 60.0 + seconds
    }
    
    static func secondsToSplitString(_ totalSeconds: Double) -> String {
        let minutes = Int(totalSeconds / 60.0)
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60.0)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
    
    // MARK: - Workout Type Detection
    
    /// Distance types end with "m" (e.g., "2000m", "5000m").
    /// Time types are formatted as time (e.g., "30:00", "20:00").
    static func isDistanceWorkoutType(_ workoutType: String) -> Bool {
        return workoutType.lowercased().hasSuffix("m")
    }
    
    // MARK: - Split Parsing (De-cumulation)
    
    static func parseSplits(from workout: Workout) -> [ParsedSplit] {
        let intervals = (workout.intervals ?? [])
            .filter { $0.orderIndex >= 1 }
            .sorted { $0.orderIndex < $1.orderIndex }
        
        guard !intervals.isEmpty else { return [] }
        
        if workout.category == .interval {
            // INTERVAL: each row is independent, nothing is cumulative
            return intervals.compactMap { interval in
                guard let timeSeconds = timeStringToSeconds(interval.time),
                      let distanceM = Double(interval.meters),
                      timeSeconds > 0, distanceM > 0 else {
                    return nil
                }
                return ParsedSplit(timeSeconds: timeSeconds, distanceM: distanceM)
            }
        }
        
        // SINGLE PIECE
        if isDistanceWorkoutType(workout.workoutType) {
            // SINGLE DISTANCE: meters is cumulative, time is per-split
            var prevCumulativeMeters: Double = 0
            return intervals.compactMap { interval in
                guard let timeSeconds = timeStringToSeconds(interval.time),
                      let cumulativeMeters = Double(interval.meters),
                      timeSeconds > 0 else {
                    return nil
                }
                let splitDistance = cumulativeMeters - prevCumulativeMeters
                prevCumulativeMeters = cumulativeMeters
                guard splitDistance > 0 else { return nil }
                return ParsedSplit(timeSeconds: timeSeconds, distanceM: splitDistance)
            }
        } else {
            // SINGLE TIME: time is cumulative, meters is per-split
            var prevCumulativeTime: Double = 0
            return intervals.compactMap { interval in
                guard let cumulativeTime = timeStringToSeconds(interval.time),
                      let distanceM = Double(interval.meters),
                      distanceM > 0 else {
                    return nil
                }
                let splitTime = cumulativeTime - prevCumulativeTime
                prevCumulativeTime = cumulativeTime
                guard splitTime > 0 else { return nil }
                return ParsedSplit(timeSeconds: splitTime, distanceM: distanceM)
            }
        }
    }
    
    // MARK: - Power Curve Building
    
    static func isDominated(duration: Double, watts: Double, curve: [Double: Double]) -> Bool {
        for (existingDuration, existingWatts) in curve {
            if existingDuration >= duration && existingWatts >= watts {
                return true
            }
        }
        return false
    }
    
    static func updatePowerCurve(duration: Double, watts: Double, curve: inout [Double: Double]) {
        if isDominated(duration: duration, watts: watts, curve: curve) {
            return
        }
        let key = (duration * 100).rounded() / 100
        if let existing = curve[key] {
            if watts > existing {
                curve[key] = watts
            }
        } else {
            curve[key] = watts
        }
    }
    
    static func enforceMonotonicity(_ curve: [Double: Double]) -> [Double: Double] {
        let sorted = curve.sorted { $0.key > $1.key }
        var cleaned: [Double: Double] = [:]
        var maxPowerSoFar: Double = 0
        for (duration, watts) in sorted {
            if watts >= maxPowerSoFar {
                cleaned[duration] = watts
                maxPowerSoFar = watts
            }
        }
        return cleaned
    }
    
    static func rebuildPowerCurve(from workouts: [Workout]) -> [Double: Double] {
        var curve: [Double: Double] = [:]
        
        for workout in workouts {
            let parsedSplits = parseSplits(from: workout)
            let n = parsedSplits.count
            guard n > 0 else { continue }
            
            if workout.category == .interval {
                // Each interval is independent — one point per interval
                for split in parsedSplits {
                    guard split.distanceM > 0 else { continue }
                    let avgSplitSeconds = split.timeSeconds / split.distanceM * 500.0
                    let avgWatts = splitToWatts(avgSplitSeconds)
                    updatePowerCurve(duration: split.timeSeconds, watts: avgWatts, curve: &curve)
                }
            } else {
                // Single piece — all contiguous blocks of splits
                for blockLength in 1...n {
                    for startIndex in 0...(n - blockLength) {
                        let block = Array(parsedSplits[startIndex ..< startIndex + blockLength])
                        
                        let totalTime = block.reduce(0) { $0 + $1.timeSeconds }
                        let totalDistance = block.reduce(0) { $0 + $1.distanceM }
                        
                        guard totalDistance > 0 else { continue }
                        
                        let avgSplitSeconds = totalTime / totalDistance * 500.0
                        let avgWatts = splitToWatts(avgSplitSeconds)
                        
                        updatePowerCurve(duration: totalTime, watts: avgWatts, curve: &curve)
                    }
                }
            }
        }
        
        return enforceMonotonicity(curve)
    }
}
```

### 2. `PowerCurveViewModel.swift`

```swift
import SwiftUI
import SwiftData

@Observable
class PowerCurveViewModel {
    var curveData: [(duration: Double, watts: Double)] = []
    var isLoading = false
    
    func loadCurve(workouts: [Workout]) {
        isLoading = true
        
        Task {
            let curve = PowerCurveService.rebuildPowerCurve(from: workouts)
            let sorted = curve.sorted { $0.key < $1.key }
                .map { (duration: $0.key, watts: $0.value) }
            
            await MainActor.run {
                self.curveData = sorted
                self.isLoading = false
            }
        }
    }
    
    /// Format duration for display on chart axis
    func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let min = Int(seconds) / 60
            let sec = Int(seconds) % 60
            return sec == 0 ? "\(min)m" : "\(min)m\(sec)s"
        } else {
            let hr = Int(seconds) / 3600
            let min = (Int(seconds) % 3600) / 60
            return min == 0 ? "\(hr)h" : "\(hr)h\(min)m"
        }
    }
}
```

### 3. `PowerCurveView.swift`

Use Swift Charts (`import Charts`) to render the power curve. The X axis should be logarithmic since power curve durations span from ~10 seconds to ~3600+ seconds. The Y axis is watts.

Key UI requirements:
- **X axis:** Duration (log scale, labeled in human-readable format: "12s", "1m", "5m", "30m", "1h")
- **Y axis:** Watts
- **Line chart** connecting all points
- Optionally show the equivalent /500m split on a secondary Y axis or as tooltip info
- Tapping a point could show: duration, watts, and equivalent split

```swift
import SwiftUI
import Charts

struct PowerCurveView: View {
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var viewModel = PowerCurveViewModel()
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Building power curve...")
            } else if viewModel.curveData.isEmpty {
                ContentUnavailableView("No Data", 
                    systemImage: "chart.xyaxis.line",
                    description: Text("Add workouts to build your power curve"))
            } else {
                Chart(viewModel.curveData, id: \.duration) { point in
                    LineMark(
                        x: .value("Duration", log10(point.duration)),
                        y: .value("Watts", point.watts)
                    )
                    PointMark(
                        x: .value("Duration", log10(point.duration)),
                        y: .value("Watts", point.watts)
                    )
                }
                .chartXAxisLabel("Duration")
                .chartYAxisLabel("Power (Watts)")
                .chartXAxis {
                    let ticks: [(Double, String)] = [
                        (log10(10), "10s"),
                        (log10(30), "30s"),
                        (log10(60), "1m"),
                        (log10(300), "5m"),
                        (log10(600), "10m"),
                        (log10(1800), "30m"),
                        (log10(3600), "1h"),
                    ]
                    AxisMarks(values: ticks.map(\.0)) { value in
                        if let v = value.as(Double.self),
                           let label = ticks.first(where: { abs($0.0 - v) < 0.01 })?.1 {
                            AxisValueLabel { Text(label) }
                            AxisGridLine()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadCurve(workouts: workouts)
        }
        .navigationTitle("Power Curve")
    }
}
```

### 4. Persistence (Optional Enhancement)

You have two options for storing the power curve:

**Option A — Rebuild on demand (simpler, recommended to start):**
Every time the user opens the power curve view, rebuild from all workouts. Cache the result in memory. This is fine for up to ~100 workouts with moderate split counts.

**Option B — Persist with SwiftData:**
Create a `PowerCurvePoint` model and save the curve, rebuilding only when new workouts are added.

```swift
@Model
final class PowerCurvePoint {
    var durationSeconds: Double
    var watts: Double
    var user: User?
    
    init(durationSeconds: Double, watts: Double) {
        self.durationSeconds = durationSeconds
        self.watts = watts
    }
}
```

Then rebuild incrementally when a workout is saved — or just do a full rebuild and replace all points.

---

## Edge Cases to Handle

1. **Missing or unparseable fields:** `timeStringToSeconds` and `Double(interval.meters)` can fail. Use `compactMap` to skip bad data gracefully.

2. **Workouts with only 1 split:** Totally valid — produces one power curve point.

3. **Zero distance splits:** Skip any block where `totalDistance == 0`.

4. **Very short durations:** Some OCR errors might produce unrealistic values. Consider filtering out durations < 5 seconds or watts > 1500 as likely errors.

5. **Interval workouts:** Each interval is treated as an independent single-split piece. Do NOT combine intervals — there is rest between them that is not reflected in the stored data. The contiguous-block algorithm is only used for single piece workouts.

6. **Cumulative field de-cumulation:** For single distance workouts, meters is cumulative and must be differenced. For single time workouts, time is cumulative and must be differenced. Getting this wrong will produce wildly incorrect power curve values.

7. **User filtering:** If the app supports multiple users, filter workouts by `userID` before building the curve.

8. **Workout type detection:** Use the `workoutType` string to determine distance vs time for single pieces. Distance types end with "m" (e.g., "2000m", "5000m"). Time types are formatted as durations (e.g., "30:00", "20:00"). Also use the `category` field (`.single` vs `.interval`) to determine the overall handling strategy.

---

## Worked Examples

### Example 1: Single Distance — 2000m

Raw intervals from OCR (meters is cumulative):
```
orderIndex 0: time="6:42.5"  meters="2000"  split="1:40.6"   ← AVERAGES (skip)
orderIndex 1: time="1:38.2"  meters="500"   split="1:38.2"   ← split 1
orderIndex 2: time="1:40.1"  meters="1000"  split="1:40.1"   ← split 2
orderIndex 3: time="1:41.5"  meters="1500"  split="1:41.5"   ← split 3
orderIndex 4: time="1:42.7"  meters="2000"  split="1:42.7"   ← split 4
```

After de-cumulation (meters differenced):
```
Split 1: time=98.2s,  distance=500m   (500 - 0)
Split 2: time=100.1s, distance=500m   (1000 - 500)
Split 3: time=101.5s, distance=500m   (1500 - 1000)
Split 4: time=102.7s, distance=500m   (2000 - 1500)
```

Contiguous blocks generated:
- Length 1: splits [1], [2], [3], [4] → 4 points
- Length 2: splits [1,2], [2,3], [3,4] → 3 points
- Length 3: splits [1,2,3], [2,3,4] → 2 points
- Length 4: splits [1,2,3,4] → 1 point (full piece)

For the full piece [1,2,3,4]:
- totalTime = 98.2 + 100.1 + 101.5 + 102.7 = 402.5s
- totalDistance = 500 + 500 + 500 + 500 = 2000m
- avgSplit = 402.5 / 2000 * 500 = 100.625 s/500m
- watts = 2.80 / (100.625/500)³ ≈ 343.5W
- Power curve point: (402.5, 343.5)

### Example 2: Interval Workout — 3x4:00/3:00r

Raw intervals from OCR (nothing cumulative):
```
orderIndex 0: time="12:00.0" meters="3845" split="1:33.5"    ← AVERAGES (skip)
orderIndex 1: time="4:00.2"  meters="1285" split="1:33.4"    ← interval 1
orderIndex 2: time="4:00.1"  meters="1280" split="1:33.6"    ← interval 2
orderIndex 3: time="4:00.0"  meters="1280" split="1:33.6"    ← interval 3
```

Each interval becomes ONE independent point (no combining):
- Interval 1: time=240.2s, distance=1285m → avgSplit = 240.2/1285*500 = 93.47 → watts ≈ 440.3 → point (240.2, 440.3)
- Interval 2: time=240.1s, distance=1280m → avgSplit = 240.1/1280*500 = 93.79 → watts ≈ 436.8 → point (240.1, 436.8)
- Interval 3: time=240.0s, distance=1280m → avgSplit = 240.0/1280*500 = 93.75 → watts ≈ 437.3 → point (240.0, 437.3)

### Example 3: Single Time — 30:00

Raw intervals from OCR (time is cumulative):
```
orderIndex 0: time="30:00.0" meters="7845"  split="1:54.6"   ← AVERAGES (skip)
orderIndex 1: time="5:00.0"  meters="1310"  split="1:54.2"   ← split 1
orderIndex 2: time="10:00.0" meters="1308"  split="1:54.5"   ← split 2
orderIndex 3: time="15:00.0" meters="1305"  split="1:54.7"   ← split 3
orderIndex 4: time="20:00.0" meters="1307"  split="1:54.5"   ← split 4
orderIndex 5: time="25:00.0" meters="1310"  split="1:54.2"   ← split 5
orderIndex 6: time="30:00.0" meters="1305"  split="1:54.7"   ← split 6
```

After de-cumulation (time differenced):
```
Split 1: time=300s  (5:00 - 0:00),   distance=1310m
Split 2: time=300s  (10:00 - 5:00),  distance=1308m
Split 3: time=300s  (15:00 - 10:00), distance=1305m
Split 4: time=300s  (20:00 - 15:00), distance=1307m
Split 5: time=300s  (25:00 - 20:00), distance=1310m
Split 6: time=300s  (30:00 - 25:00), distance=1305m
```

Then generate all contiguous blocks (length 1 through 6), same as single distance.

---

## Testing

To verify correctness, test with known data:

- A 2000m piece at 1:40.6 average → full piece should produce ~343W at ~402s
- A single 4:00 interval at 1:33.5 split → ~438W at 240s
- Verify monotonicity: every point at a shorter duration should have equal or higher watts than any point at a longer duration
- Verify de-cumulation: for a 2000m with 4 splits, each split should have distance ≈500m (not 500, 1000, 1500, 2000)
- Verify interval independence: a 3x4:00 workout should produce 3 separate ~240s points, NOT points at 480s or 720s

---

## Summary of Key Points

| Concept | Detail |
|---|---|
| Source data | `Interval` objects with `orderIndex >= 1` from each `Workout` |
| Skip | `orderIndex == 0` (averages row) |
| Single distance | `meters` is **cumulative** — must difference to get per-split distance. `time` is per-split. |
| Single time | `time` is **cumulative** — must difference to get per-split time. `meters` is per-split. |
| Interval | Both `time` and `meters` are per-interval. Each interval is independent. |
| Detect type | `workoutType.hasSuffix("m")` → distance; otherwise → time. Check `category` for `.interval` vs `.single`. |
| Single pieces | Combine all contiguous blocks of 1..n splits |
| Interval pieces | Each interval = 1 independent point. Never combine across intervals. |
| Compute | `avgSplit = totalTime / totalDistance * 500`, then `watts = 2.80 / (avgSplit/500)³` |
| Store | `[durationSeconds: bestWatts]` dictionary |
| Clean | Enforce monotonic decrease from short → long duration |
| Display | Log-scale X axis (duration), linear Y axis (watts), Swift Charts |
