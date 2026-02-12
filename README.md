# ErgScan

An iOS app that uses OCR to scan Concept2 rowing ergometer (PM5) monitors, automatically extracting workout data and logging it to a personal training journal with iCloud sync and social features.

## How It Works

### Core Flow

1. **Sign in** with Apple ID (required, credentials stored in Keychain)
2. **Point camera** at the Concept2 PM5 monitor screen
3. **Auto-scan** iteratively captures photos, runs OCR, and merges results until all fields are filled
4. **Review & edit** the parsed data, set intensity zone, mark erg tests
5. **Save** to local SwiftData database (syncs to iCloud automatically)
6. **Share** workouts with friends via CloudKit public database

### Scanning Pipeline

The scanner uses a multi-capture iterative approach. Each capture goes through:

```
Camera Photo
  -> Crop to center square
  -> Apple Vision OCR (VNRecognizeTextRequest, accurate mode)
  -> Guide-relative coordinate mapping
  -> Table parsing (9-phase pipeline)
  -> Merge with accumulated data from previous captures
  -> Lock when all essential fields are filled
```

**The 9-phase table parser** (`TableParserService`):
1. Group OCR detections into rows by Y-coordinate clustering
2. Find "View Detail" anchor row (PM5 landmark)
3. Extract workout descriptor, classify as single piece or intervals
4. Extract date and total time
5. Determine column order from header row (Time, Meters, /500m, s/m)
6. Detect heart rate column (if HR monitor was connected)
7. Parse summary/averages row
8. Parse data rows (intervals or splits)
9. Fallback classification and confidence calculation

## Architecture

### App Entry Point

`ErgScan1App.swift` sets up three global services:
- **AuthenticationService** - Sign in with Apple, Keychain storage
- **ThemeViewModel** - Light/dark/system theme preference
- **SocialService** - CloudKit public database for social features

The SwiftData `ModelContainer` attempts CloudKit sync first (`iCloud.com.omomalley03.ErgScan1`), falls back to local-only if CloudKit is unavailable.

### Navigation

Five-tab layout via `MainTabView` with a custom tab bar:

| Tab | View | Description |
|-----|------|-------------|
| Dashboard | `DashboardView` | Weekly meters chart (zone-stacked bars), goal progress widget |
| Log | `LogView` | Chronological list of all workouts, swipe to delete |
| + (center) | `AddWorkoutSheet` | Bottom sheet with Scan, Upload, Goals actions |
| Friends | `FriendsView` | User search, friend requests, activity feed |
| Profile | `ProfileView` | User info, workout count, link to Settings |

### Data Models (SwiftData)

| Model | Purpose |
|-------|---------|
| `User` | Apple ID, email, name, username. Has-many `Workout` |
| `Workout` | Date, type, category (single/interval), total time/distance, intensity zone, erg test flag, captured image. Has-many `Interval` |
| `Interval` | Individual split or interval row: time, meters, /500m split, stroke rate, heart rate. Each field has a confidence score from OCR |
| `Goal` | Weekly/monthly meter targets, target zone distribution percentages |
| `BenchmarkWorkout` | Ground truth dataset for OCR accuracy testing |
| `BenchmarkInterval` | Ground truth interval data for benchmarks |
| `BenchmarkImage` | Captured images with raw OCR results for benchmark comparison |

### Services

| Service | File | Role |
|---------|------|------|
| `CameraService` | `Services/CameraService.swift` | AVCaptureSession management, photo capture, continuous video frame output. Runs `startRunning()`/`stopRunning()` on background threads |
| `VisionService` | `Services/VisionService.swift` | Apple Vision framework OCR. Actor-isolated. Accurate mode for photos, fast mode for live preview |
| `TableParserService` | `Services/TableParserService.swift` | 9-phase pipeline parsing OCR text into structured `RecognizedTable` |
| `AuthenticationService` | `Services/AuthenticationService.swift` | Sign in with Apple, Keychain credential storage, session restore |
| `SocialService` | `Services/SocialService.swift` | CloudKit public database operations: user profiles, usernames, friend requests, shared workouts, activity feed |
| `HapticService` | `Services/HapticService.swift` | Centralized haptic feedback (success and light impact) |

### Utilities

| Utility | Role |
|---------|------|
| `TextPatternMatcher` | Regex patterns for PM5 data: time formats, split pace, meters, stroke rate, workout descriptors, date parsing, interval classification |
| `BoundingBoxAnalyzer` | Spatial grouping of OCR results into rows by Y-coordinate proximity |
| `GuideCoordinateMapper` | Coordinate transforms between Vision, camera, and UI coordinate spaces |

### ViewModels

| ViewModel | Role |
|-----------|------|
| `ScannerViewModel` | Manages scanning state machine (ready -> capturing -> locked -> saved), iterative capture loop, table merging, benchmark dataset collection |
| `ThemeViewModel` | App theme preference (light/dark/system), persisted to UserDefaults |

## Key Features

### OCR Scanning
- Iterative multi-capture: keeps scanning until all fields are filled
- Per-field confidence scores with visual indicators
- Data merging across captures (keeps highest-confidence value per field)
- Automatic workout type classification (single piece vs intervals)
- Heart rate column auto-detection (PM5 shows HR when monitor connected)
- Coast/cooldown tail detection and removal
- Editable locked data before saving

### Workout Management
- Full workout log with chronological list view
- Detailed view with swipeable interval cards (for interval workouts) or split list (for single pieces)
- Fastest/slowest split highlighting (green/red)
- Edit any field post-save with confidence badges
- Captured image stored and viewable in full-screen
- Intensity zone tagging (UT2, UT1, AT, Max)
- Erg test flagging

### Dashboard
- Zone-stacked bar chart (Mon-Sun, swipeable by week)
- Weekly goal progress widget
- Tap any day bar to jump to that day's workouts in the Log

### Goals
- Weekly and monthly meter targets
- Target zone distribution with sliders (UT2/UT1/AT/Max percentages)
- Live progress tracking against goals

### Social (Friends System)
- Username registration via CloudKit public database
- User search by username or display name
- Friend request system (send, accept, reject)
- "Friends" badge shown when searching for existing friends
- Activity feed showing friends' recent workouts
- Automatic workout publishing to friends when saved

### iCloud Sync
- SwiftData + CloudKit private database for personal data (workouts, goals, user profile)
- CloudKit public database for social features (user profiles, friend requests, shared workouts)
- Automatic sync across all Apple devices signed into the same iCloud account

### Other
- Sign in with Apple authentication
- Light/dark/system theme toggle
- Haptic feedback throughout the UI
- Image picker for uploading photos (future: OCR from photo library)
- Benchmark dataset collection for OCR accuracy testing

## Project Structure

```
ErgScan1/
  ErgScan1App.swift              # App entry, ModelContainer, environment setup
  Models/
    User.swift                   # User account model
    Workout.swift                # Workout + WorkoutCategory
    Interval.swift               # Split/interval row data
    Goal.swift                   # Training goals
    IntensityZone.swift          # UT2/UT1/AT/Max enum
    OCRResult.swift              # OCR result types, RecognizedTable, TableRow
    TabItem.swift                # Tab bar enum
    BenchmarkWorkout.swift       # Benchmark ground truth
    BenchmarkInterval.swift      # Benchmark interval data
    BenchmarkImage.swift         # Benchmark image storage
  Services/
    CameraService.swift          # Camera session, photo capture
    VisionService.swift          # Apple Vision OCR
    TableParserService.swift     # OCR -> structured table parser
    AuthenticationService.swift  # Sign in with Apple
    SocialService.swift          # CloudKit social features
    HapticService.swift          # Haptic feedback
  ViewModels/
    ScannerViewModel.swift       # Scanning state machine
    ThemeViewModel.swift         # Theme preference
    BenchmarkListViewModel.swift # Benchmark management
  Views/
    MainTabView.swift            # Tab navigation container
    ScannerView.swift            # Camera + scanning UI
    CameraPreviewView.swift      # AVCaptureVideoPreviewLayer wrapper
    DashboardView.swift          # Dashboard with charts
    LogView.swift                # Workout list
    FriendsView.swift            # Friends tab (search, requests, feed)
    ProfileView.swift            # User profile
    SettingsView.swift           # Settings (account, username, theme)
    GoalsView.swift              # Training goals editor
    EditWorkoutView.swift        # Post-save workout editor
    EditableWorkoutForm.swift    # Pre-save review form
    EnhancedWorkoutDetailView.swift  # Workout detail with cards/splits
    SearchView.swift             # Workout search (placeholder)
    PositioningGuideView.swift   # Camera square guide overlay
    LockedGuideOverlay.swift     # Green checkmark overlay
    AuthenticationView.swift     # Sign in screen
    ImagePickerView.swift        # Photo library picker
    DebugTabbedView.swift        # OCR debug tabs (developer mode)
    BenchmarkListView.swift      # Benchmark dataset list
    BenchmarkDetailView.swift    # Benchmark detail
    BenchmarkReportView.swift    # Benchmark accuracy report
    BenchmarkResultsView.swift   # Benchmark results comparison
    ComparisonDetailView.swift   # Side-by-side OCR comparison
    Components/
      CustomTabBar.swift         # Custom 5-tab bar with center + button
      AddWorkoutSheet.swift      # Bottom sheet (Scan/Upload/Goals)
      UserSearchResultRow.swift  # Friend search result row
      FriendRequestCard.swift    # Pending friend request card
      FriendActivityCard.swift   # Activity feed workout card
      FullScreenImageViewer.swift # Zoomable image viewer
  Utilities/
    TextPatternMatcher.swift     # Regex patterns for PM5 data
    BoundingBoxAnalyzer.swift    # OCR bounding box grouping
    GuideCoordinateMapper.swift  # Coordinate space transforms
    View+Extensions.swift        # SwiftUI view extensions
```

## Requirements

- iOS 17+
- Xcode 16+
- Apple Developer account (for Sign in with Apple and CloudKit)
- Physical device for camera features (simulator has no camera)

## CloudKit Setup

The app uses two CloudKit databases:
- **Private database** (`iCloud.com.omomalley03.ErgScan1`): SwiftData sync for personal workouts, goals, user data
- **Public database** (same container): Social features - UserProfile, FriendRequest, SharedWorkout record types

Record types are auto-created in Development when first written from an Xcode build. Deploy schema to Production via CloudKit Dashboard before TestFlight/App Store builds.
