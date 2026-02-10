# Plan: Strava-Like 5-Tab Navigation with Dark Mode

## Context

**Why This Change:**
Transform ErgScan from a simple 3-tab app into a professional Strava-like fitness platform with:
- 5-tab navigation (Dashboard, Feed, Teams, Profile)
- Custom center (+) button for adding workouts (scan or upload)
- Global search for teams/individuals
- Dark mode support with toggle in settings
- Profile page with settings access

**Current State:**
- Simple 3-tab TabView (Scanner, Workouts, Settings)
- No dark mode support
- Scanner as dedicated tab (should be modal)
- Settings as main tab (should be under Profile)

**User Requirements:**
1. Bottom nav: Dashboard, Feed, (+), Teams, Profile
2. Top left: Search icon (magnifying glass) across all tabs
3. (+) button: Custom styled, shows action sheet for "Scan Workout" or "Upload from Photos"
4. Profile: User info + Settings button (top right) → Settings sheet
5. Settings: Add dark mode toggle
6. Dashboard: Current workout log (WorkoutListView content)
7. Feed & Teams: Placeholder views for now

---

## Implementation Approach

### Architecture: Custom Tab Bar with ZStack

**Why custom tab bar:**
- SwiftUI TabView doesn't support custom center buttons natively
- Need precise control over (+) button styling (black bg in light mode, off-white in dark mode)
- Allows elevated center button above tab bar

**Structure:**
```
MainTabView (root)
├── ZStack
│   ├── Content Layer (selected tab view)
│   └── CustomTabBar Overlay (bottom)
│       ├── 4 regular tab buttons
│       └── Center (+) button (elevated, themed)
├── Sheets: Scanner, ImagePicker, Search
└── Action Sheet: "Scan Workout" or "Upload from Photos"
```

---

## Files to Create

### 1. `/Views/MainTabView.swift` (~350 LOC)
Main container managing tab selection and sheet presentation:
- `@State selectedTab: TabItem`
- `@State` for sheet presentation (scanner, imagePicker, search, actionSheet)
- ZStack with content switcher and CustomTabBar overlay
- Action sheet with "Scan Workout" / "Upload from Photos" options
- Sheet presentations for scanner, image picker, search

### 2. `/Views/Components/CustomTabBar.swift` (~200 LOC)
Custom tab bar component:
- Bottom bar with 5 positions
- 4 regular tab buttons (icon + label)
- Center position: elevated (+) button
  - Light mode: black bg, white icon
  - Dark mode: off-white bg, black icon
  - Offset: `y: -20`, size: 60x60 circle
  - Shadow for elevation
- Haptic feedback on tap
- Theme-aware colors using `@Environment(\.colorScheme)`

### 3. `/Views/DashboardView.swift` (~100 LOC)
Workout log (adapted from WorkoutListView):
- Copy WorkoutListView content exactly
- Change title to "Dashboard"
- Add search button in top left toolbar
- Keep all functionality: query, filtering, swipe-to-delete, navigation

### 4. `/Views/FeedView.swift` (~50 LOC)
Placeholder view:
- NavigationStack with "Feed" title
- "Coming Soon" message with icon
- Search button in top left

### 5. `/Views/TeamsView.swift` (~50 LOC)
Placeholder view:
- NavigationStack with "Teams" title
- "Coming Soon" message with icon
- Search button in top left

### 6. `/Views/ProfileView.swift` (~150 LOC)
User profile with settings access:
- NavigationStack with "Profile" title
- User info section:
  - Large avatar circle (initials from currentUser)
  - User name (headline)
  - Email (subheadline)
  - Basic stats (workout count)
- Toolbar:
  - Left: Search button
  - Right: Settings button → opens SettingsView as sheet
- `@Environment(\.currentUser)` for user data

### 7. `/Views/SearchView.swift` (~100 LOC)
Search interface (placeholder):
- NavigationStack with "Search" title
- `.searchable(text: $searchText, prompt: "Teams or individuals")`
- Recent searches section (placeholder)
- Cancel button in toolbar

### 8. `/Views/ImagePickerView.swift` (~150 LOC)
Photo picker for workout uploads:
- Use `PhotosUI` framework (iOS 16+)
- `PhotosPicker` for image selection
- Preview selected image
- "Process Image" button (TODO: integrate with OCR pipeline)
- Cancel button to dismiss
- Crop to square helper function

### 9. `/Models/TabItem.swift` (~50 LOC)
Tab definition enum:
```swift
enum TabItem: String, CaseIterable {
    case dashboard, feed, teams, profile

    var title: String { ... }
    var icon: String { /* SF Symbol */ }
    var selectedIcon: String { /* filled variant */ }
    var tag: Int { /* 0-3 */ }
}
```

### 10. `/ViewModels/ThemeViewModel.swift` (~100 LOC)
Dark mode state management:
```swift
@MainActor
class ThemeViewModel: ObservableObject {
    @AppStorage("isDarkMode") var isDarkMode: Bool = false
    @Published var colorScheme: ColorScheme? = nil

    func toggleTheme() { isDarkMode.toggle() }
    private func updateColorScheme() {
        colorScheme = isDarkMode ? .dark : .light
    }
}
```

---

## Files to Modify

### 1. `/Views/ContentView.swift`
**Current:** 3-tab TabView with Scanner, Workouts, Settings
**Change:** Replace with `MainTabView()`
```swift
struct ContentView: View {
    var body: some View {
        MainTabView()  // Replace entire TabView
    }
}
```

### 2. `/Views/SettingsView.swift`
**Current:** Account, iCloud Sync, About, Sign Out sections
**Change:** Add "Appearance" section with dark mode toggle
```swift
Section("Appearance") {
    Toggle("Dark Mode", isOn: $themeViewModel.isDarkMode)
}
```
**Access:** `@EnvironmentObject var themeViewModel: ThemeViewModel`

### 3. `/Views/ScannerView.swift`
**Current:** Full-screen tab view
**Change:** Add dismiss button for modal presentation
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("Cancel") { dismiss() }
    }
}
```
**Presentation:** Via sheet from (+) button action sheet

### 4. `/ErgScan1App.swift`
**Current:** AuthenticationService StateObject
**Change:** Add ThemeViewModel and apply colorScheme
```swift
@StateObject private var themeViewModel = ThemeViewModel()

var body: some Scene {
    WindowGroup {
        ContentViewWrapper(authService: authService)
            .environmentObject(themeViewModel)
            .preferredColorScheme(themeViewModel.colorScheme)
    }
}
```

---

## Implementation Sequence

### Phase 1: Foundation (30 mins)
1. Create `TabItem.swift` enum
2. Create `ThemeViewModel.swift`
3. Update `ErgScan1App.swift`:
   - Add `@StateObject private var themeViewModel = ThemeViewModel()`
   - Inject `.environmentObject(themeViewModel)`
   - Apply `.preferredColorScheme(themeViewModel.colorScheme)`
4. **Verify:** Build succeeds

### Phase 2: Custom Tab Bar (1 hour)
1. Create `CustomTabBar.swift`:
   - Bottom HStack with 5 positions
   - Tab button component (icon + label, selected state)
   - Center button: ZStack with circle, plus icon
     - `colorScheme == .dark ? Color(.systemGray6) : .black` (bg)
     - `colorScheme == .dark ? .black : .white` (icon)
     - `.offset(y: -20)`, `.shadow()`
   - Callbacks: `@Binding selectedTab`, `onCenterButtonTap: () -> Void`
   - Haptic feedback on tap
2. **Verify:** Preview in light/dark modes, test tap gestures

### Phase 3: Main Tab Container (1 hour)
1. Create `MainTabView.swift`:
   - `@State selectedTab: TabItem = .dashboard`
   - `@State` for sheet presentation bools
   - ZStack: content view + CustomTabBar
   - Content switcher: `switch selectedTab { case .dashboard: ... }`
   - `.sheet(isPresented: $showScanner) { ScannerView() }`
   - `.sheet(isPresented: $showImagePicker) { ImagePickerView() }`
   - `.sheet(isPresented: $showSearch) { SearchView() }`
   - `.confirmationDialog` for (+) button actions
2. **Verify:** Tab switching works, action sheet appears

### Phase 4: Individual Tab Views (1.5 hours)
1. Create `DashboardView.swift`:
   - Copy WorkoutListView content
   - Change `.navigationTitle("Dashboard")`
   - Add search button in toolbar
2. Create `FeedView.swift` (placeholder)
3. Create `TeamsView.swift` (placeholder)
4. Create `ProfileView.swift`:
   - User avatar (large circle with initials)
   - Name, email from `@Environment(\.currentUser)`
   - Toolbar: search (left), settings button (right)
   - `.sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }`
5. Create `SearchView.swift` (placeholder with .searchable)
6. **Verify:** Each tab renders, Profile → Settings works

### Phase 5: Dark Mode Integration (45 mins)
1. Update `SettingsView.swift`:
   - Add `@EnvironmentObject var themeViewModel: ThemeViewModel`
   - Add "Appearance" section before "About"
   - Add `Toggle("Dark Mode", isOn: $themeViewModel.isDarkMode)`
2. Test: Toggle in settings → entire app switches theme
3. **Verify:** Center (+) button styling inverts correctly

### Phase 6: Image Picker (1 hour)
1. Create `ImagePickerView.swift`:
   - Import `PhotosUI`
   - `@State selectedItem: PhotosPickerItem?`
   - `@State selectedImage: UIImage?`
   - `PhotosPicker` for selection
   - Preview image if selected
   - "Process Image" button (placeholder handler)
   - `.onChange(of: selectedItem)` to load image
   - Crop to square helper function
2. Wire up in MainTabView action sheet
3. **Verify:** Select photo, preview, dismiss

### Phase 7: Scanner Integration (30 mins)
1. Update `ScannerView.swift`: Add cancel button if missing
2. Wire up in MainTabView action sheet
3. **Verify:** Full scan flow works, dismiss returns to previous tab

### Phase 8: Search Integration (30 mins)
1. Add search button to all tab toolbars
2. Wire up in MainTabView
3. **Verify:** Search sheet presents and dismisses

### Phase 9: Final Integration (1 hour)
1. Update `ContentView.swift`: Replace TabView with `MainTabView()`
2. Test complete user flows:
   - Dashboard → Detail → Edit → Save
   - Profile → Settings → Dark Mode → Sign Out
   - (+) → Scan → Complete flow
   - (+) → Upload → Select image
   - Search from each tab
3. Polish: Safe area handling, animations
4. **Verify:** All original functionality preserved

---

## Key Code Patterns

### Dark Mode Toggle
```swift
// In SettingsView
@EnvironmentObject var themeViewModel: ThemeViewModel

Section("Appearance") {
    Toggle("Dark Mode", isOn: $themeViewModel.isDarkMode)
}
```

### Center Button Styling
```swift
// In CustomTabBar
@Environment(\.colorScheme) var colorScheme

Circle()
    .fill(colorScheme == .dark ? Color(.systemGray6) : .black)
    .frame(width: 60, height: 60)
    .overlay(
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(colorScheme == .dark ? .black : .white)
    )
    .offset(y: -20)
    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
```

### Action Sheet
```swift
.confirmationDialog("Add Workout", isPresented: $showActionSheet) {
    Button("Scan Workout") { showScanner = true }
    Button("Upload from Photos") { showImagePicker = true }
    Button("Cancel", role: .cancel) {}
}
```

### Image Picker
```swift
PhotosPicker(
    selection: $selectedItem,
    matching: .images
) {
    Label("Select Photo", systemImage: "photo")
}
.onChange(of: selectedItem) { _, newItem in
    Task {
        if let data = try? await newItem?.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage = image
        }
    }
}
```

---

## Verification Checklist

### Functionality Preservation
- [ ] Dashboard shows all workouts correctly
- [ ] Swipe-to-delete works
- [ ] Workout detail navigation works
- [ ] Scanner flow unchanged (ready → capturing → locked → saved)
- [ ] Authentication flow unchanged
- [ ] Settings functionality unchanged (sign out, iCloud sync info)
- [ ] SwiftData persistence unchanged

### New Features
- [ ] 5 tabs render correctly (Dashboard, Feed, Teams, Profile)
- [ ] Tab switching works smoothly
- [ ] Center (+) button shows action sheet
- [ ] "Scan Workout" opens scanner
- [ ] "Upload from Photos" opens image picker
- [ ] Search icon appears in all tabs
- [ ] Search view presents and dismisses
- [ ] Profile shows user info
- [ ] Profile → Settings button works
- [ ] Dark mode toggle in settings works
- [ ] Entire app switches theme
- [ ] Center (+) button styling inverts in dark mode

### Edge Cases
- [ ] Safe area handling (iPhone X+ notch, home indicator)
- [ ] iPad layout (tab bar width, sheet presentation)
- [ ] VoiceOver accessibility
- [ ] Dynamic Type support
- [ ] Offline mode (no crashes)
- [ ] State preservation on tab switching

---

## Critical Files

1. **ContentView.swift** - `/Users/omomalley03/Desktop/ErgScan1/ErgScan1/Views/ContentView.swift`
   Main integration point, replace TabView with MainTabView

2. **WorkoutListView.swift** - `/Users/omomalley03/Desktop/ErgScan1/ErgScan1/Views/WorkoutListView.swift`
   Reference for DashboardView content

3. **ScannerView.swift** - `/Users/omomalley03/Desktop/ErgScan1/ErgScan1/Views/ScannerView.swift`
   Add cancel button for modal presentation

4. **SettingsView.swift** - `/Users/omomalley03/Desktop/ErgScan1/ErgScan1/Views/SettingsView.swift`
   Add dark mode toggle

5. **ErgScan1App.swift** - `/Users/omomalley03/Desktop/ErgScan1/ErgScan1/ErgScan1App.swift`
   Add ThemeViewModel and preferredColorScheme

---

## Estimated Time: 8 hours

| Phase | Time |
|-------|------|
| Foundation | 30 mins |
| Custom Tab Bar | 1 hour |
| Main Tab Container | 1 hour |
| Individual Tabs | 1.5 hours |
| Dark Mode | 45 mins |
| Image Picker | 1 hour |
| Scanner Integration | 30 mins |
| Search Integration | 30 mins |
| Final Integration | 1 hour |

---

## Future Enhancements

1. **Feed Implementation**: Activity feed, likes, comments
2. **Teams Implementation**: Create/join teams, leaderboards
3. **Search Backend**: Real search with history and suggestions
4. **Profile Enhancements**: Avatar upload, bio, statistics charts
5. **Image Upload Processing**: Full OCR pipeline for uploaded photos
