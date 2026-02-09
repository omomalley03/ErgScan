# Fix: Slash-to-1 OCR Misread in Workout Descriptors

## Problem

The most common remaining descriptor parsing error is the OCR reading `/` as `1`. This causes the rest time in interval descriptors to get a spurious leading `1`:

| Actual descriptor | OCR produces | After current normalizeDescriptor | Parsed rest time |
|---|---|---|---|
| `2x20:00/1:15r` | `2x20:0011:15r` | `2x20:00/11:15r` | `11:15` ❌ (should be `1:15`) |
| `3x20:00/1:00r` | `3x20:0011:00r` | `3x20:00/11:00r` | `11:00` ❌ (should be `1:00`) |
| `5x1000m/7:00r` | `5x1000m17:00r` | `5x1000m/17:00r` | `17:00` ❌ (should be `7:00`) |
| `2x20:00/1:15r` | `2x20:00 11:15r` | fails to match | — ❌ |

### What's happening step by step

Take `2x20:00/1:15r` as an example:

1. OCR reads the `/` character as `1`, producing `2x20:0011:15r`
2. The existing fix #4 in `normalizeDescriptor()` (lines 70-88 of TextPatternMatcher.swift) detects the concatenated times: after `x`, it finds the first `\d+:\d{2}` match (`20:00`) followed by another digit (`1`), so it inserts `/` after `20:00`
3. Result: `2x20:00/11:15r`
4. This matches `intervalTypePattern` (`^\d{1,2}x[\d:]+[rm]?/[\d:]+r?$`) — so it's accepted as valid
5. `parseIntervalWorkout` extracts rest time as `11:15` instead of `1:15`
6. The workout is classified as intervals with the wrong rest time

The same thing happens with space-separated fragments. OCR might produce fragments `2x20:00` and `11:15r` as two separate pieces. The joined text `2x20:00 11:15r` gets normalizeDescriptor applied, fix #4 inserts a `/` giving `2x20:00/11:15r`, same wrong result.

### Why this is the "most common" error

The `/` character is thin and vertical, very similar to `1` on the PM5 display. The OCR misreads it as `1` more often than it reads it correctly. The other corruption modes (comma, missing entirely) were already fixed. This remaining mode produces a result that *looks* valid to the parser but has incorrect data.

## Root Cause

The existing fix #4 inserts a `/` separator but doesn't account for the fact that the first digit after the insertion point may actually BE the misread `/`. The `1` that starts `11:15r` is not a real digit — it's the ghost of the slash.

## Required Change

### In `TextPatternMatcher.swift` — Add fix #5 to `normalizeDescriptor()`

**Location:** After fix #4 (the missing separator insertion, lines 70-88), add a new step that detects when the rest time portion has a suspicious leading `1` that is likely a misread `/`.

**Insert after the closing brace of fix #4 (after line 89 `}`) and before `return result` (line 91):**

```swift
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
```

### How this interacts with existing fixes

The fix chain in `normalizeDescriptor()` now works as:

1. **Cyrillic substitutions** — `г`→`r`, `м`→`m`, etc.
2. **Leading B→3** — `Bx20:00...` → `3x20:00...`
3. **Comma→slash** — `3x20:00,1:00r` → `3x20:00/1:00r`
4. **Missing separator insertion** — `3x20:0011:00r` → `3x20:00/11:00r`
5. **NEW: Slash-as-1 correction** — `3x20:00/11:00r` → `3x20:00/1:00r`

Fix #5 runs after fix #4, so it handles both cases:
- Concatenated: `2x20:0011:15r` → (fix #4) `2x20:00/11:15r` → (fix #5) `2x20:00/1:15r` ✓
- Already has slash but with ghost 1: `2x20:00/11:15r` → (fix #5) `2x20:00/1:15r` ✓
- Space-separated fragments that get joined: `2x20:00 11:15r` → (fix #4 if applicable or fix in extractDescriptor) → eventually `2x20:00/11:15r` → (fix #5) `2x20:00/1:15r` ✓

### Edge cases — when NOT to strip the leading 1

The check is simple: parse the rest time minutes, and only strip if minutes ≥ 10 (impossible on PM5, max rest is 9:55).

- `2x500m/1:30r` — rest is genuinely `1:30`. Minutes = 1, which is < 10. **Not stripped. Correct.** ✓
- `3x2000m/10:00r` — impossible on PM5 anyway, but: minutes = 10, ≥ 10, would strip to `0:00r`. In practice this input can't exist because PM5 caps at 9:55.
- `2x4:00/1:00r` → OCR `2x4:0011:00r` → fix #4 `2x4:00/11:00r` → minutes = 11, ≥ 10, strip → `2x4:00/1:00r`. **Correct.** ✓
- `3x4:00/3:00r` (no OCR error) → afterSlash = `3:00r`, doesn't start with `1` → skip. **Correct.** ✓

**The critical safe case:** When the rest time genuinely starts with `1` (like `1:30r`), removing the `1` produces `:30r` which doesn't match the rest time regex pattern (no leading digit before `:`). So the fix correctly leaves it alone.

### Also handle the space-separated fragment case

When OCR produces two fragments like `2x20:00` and `11:15r`, the `extractDescriptor` method in TableParserService.swift tries joining them. The joined text `2x20:00 11:15r` needs spaces removed to become `2x20:0011:15r` before `normalizeDescriptor` can work its magic.

**In `extractDescriptor` (TableParserService.swift, line 296):** After the existing attempts to match individual fragments and joined text, add a fallback that tries combining adjacent fragments by removing the space:

```swift
// After existing fragment and joined-text attempts...
// Try combining adjacent space-separated parts that look like split descriptor
// e.g., "2x20:00" + "11:15r" → "2x20:0011:15r" → normalizeDescriptor → "2x20:00/1:15r"
if parts.count == 2 {
    let combined = parts[0] + parts[1]
    let normalizedCombined = matcher.normalizeDescriptor(combined)
    log("  Trying combined parts: '\(combined)' -> '\(normalizedCombined)'")
    if matcher.matchWorkoutType(normalizedCombined) {
        log("    ✓ Combined parts match")
        return normalizedCombined
    }
}
```

This should go after the existing space-separated parts loop (around line 336) but before the final "No descriptor pattern matched" return.

## Testing

After this fix, these OCR corruptions should all normalize correctly:

| OCR output | → normalizeDescriptor | ✓ |
|---|---|---|
| `2x20:0011:15r` | `2x20:00/1:15r` | ✓ |
| `3x20:0011:00r` | `3x20:00/1:00r` | ✓ |
| `5x1000m17:00r` | `5x1000m/7:00r` | ✓ |
| `2x20:00/11:15r` | `2x20:00/1:15r` | ✓ |
| `3x4:0013:00r` | `3x4:00/3:00r` | ✓ (fix #4 only, fix #5 leaves alone because `:00r` after stripping `1` gives `3:00r`, mins=3 <10, so it WOULD strip... wait) |

Hmm — let me trace `3x4:0013:00r` through:
1. Fix #4: `3x4:00/13:00r` (inserts `/` after first time)
2. Fix #5: afterSlash = `13:00r`, starts with `1`, minutes = 13, ≥ 10 → strip → `3x4:00/3:00r`

That's the **correct** result! The original descriptor is `3x4:00/3:00r` and the `1` in `13:00r` was the misread `/`. ✓

One more: `3x4:00/3:00r` (already correct, no OCR error):
1. Fix #5: afterSlash = `3:00r`, does NOT start with `1` → skip. **Correct — no false correction.** ✓

And: `2x500m/1:30r` (genuine 1:30 rest):
1. Fix #5: afterSlash = `1:30r`, starts with `1`, minutes = 1, < 10 → **not stripped. Correct.** ✓

## What NOT to Change

- **Existing fixes 1-4** in `normalizeDescriptor()` — leave them as-is
- **`intervalTypePattern` regex** — no changes needed, the pattern already accepts the corrected format
- **`parseIntervalWorkout`** — no changes needed, it correctly extracts work/rest from properly formatted descriptors
- **General `normalize()`** — no changes
