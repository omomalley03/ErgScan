# App Feature Specification

## 🟢 Onboarding Flow (First Login)

### Welcome Screen
- **Trigger Conditions:**
  - First login, OR
  - User does not have "onboarded" variable checked (backward compatibility for existing users)
- **Note:** This is an update to the app, so existing accounts will see this screen once, then be marked as onboarded

### Role Selection
Choose one:
- **Rower**
- **Coxswain**
- **Coach**

Continue to setup screen →

### Setup Screen

**Choose:**
- Join existing team
- Create new team

**Optional:**
- Set goal weekly mileage (or skip)

### Team Joining Logic

**If joining a team:**
1. Request is sent to team admin
2. User sees "Pending Approval" on Teams page
3. Team admin must approve membership

**Team creation can be done:**
- From onboarding
- From Teams page
- Creator automatically becomes Team Admin

---

## 🧭 App Navigation Structure

1. **Dashboard** (No change from current status)
2. **Log** (No change from current)
3. **Plus Workout** (No change from current)
4. **Teams** (New features described below)
5. **Profile** (Additional functionality described below)

---

## 👤 Profile Page

### New Teams Button
- Located under the Friends button
- Takes you to a list of your teams
- **Pending team join requests** (requests you've sent) live here

### Privacy Control

**Location:** User settings → Privacy

**Privacy Levels:**
1. **Private**
2. **Team**
3. **Friends**

**Privacy Logic:**
- Teams and Friends can be exclusive
- Example: You could be on a team with someone but not friends
  - Their results will NOT appear in your dashboard (friends only)
  - Their results WILL appear on the team feed
- A workout submitted under "Team" is only shown to people in that team
- Example: Friend not on your team won't see a team-only workout

**Workout Upload Privacy:**
- When submitting a workout, you can update privacy settings for that upload
- Auto-selected to default setting, but can be changed
- If part of multiple teams (e.g., "N150" and "CDPC"), you can select multiple teams

---

## 👥 Teams Page (Core Feature Hub)

### General
- **Replaces** the old Friends tab
- **Search bar:** Search Teams and Users to add friends or join a team
- **Create Team button** available

### Team Selector
- Toggle at the top to switch between teams (can be part of multiple teams)

### Team View Components

When selecting a team, display:

#### 1. Team Header
- Team Name
- Team profile pic

#### 2. Show Roster Button
- Opens new page listing all members
- Tags members as: Rower, Cox, or Coach
- Flags admin(s)

#### 3. Assigned Workouts Section

**Tabs:**
- **To Do workouts**
- **Completed workouts**

**Workout Details:**
- Click on an assigned workout to view:
  - Description written by workout creator
  - **"Plus" button** to scan a workout and automatically submit it
  - Option to select from your log to assign an already-scanned workout
- Once submitted, workout moves to "Completed" tab

#### 4. Team Feed
- Similar to Dashboard feed
- Shows workouts from team members only
- Limit: Most recent 10 workouts

---

## 🧑‍🏫 Coach Privileges

### Assign Erg Workouts to Team

**Extra button on team page:** "Assign a Workout"

**Workout Assignment Fields:**
- Name
- Start date for submission
- End date for submission
- Description

### View Assigned Workout Submissions

**Submission Tracker Display:**
- **Top of list:** Those who have submitted (green hue)
- **Bottom of list:** Those who have not yet submitted (red hue)
- **Click on a name:** Go to the workout results page (picture, summary, split/interval)

---

## 🎤 Coxswain Privileges

### Enter Team Scores Feature

**Location:** Teams tab special view

**Functionality:**
1. Click "Enter Team Scores" button
2. View roster list
3. Click on a person
4. Taken to erg scan screen
5. Scan workout
6. **Submission behavior:** Workout is submitted as if the selected rower scanned it themselves

**Example Flow:**
- Coxswain clicks "Enter Team Scores"
- Clicks on Athlete A
- Taken to scan screen
- Scans workout
- Workout is submitted to Athlete A's log (as if Athlete A did the scan)

---

## 📊 Workout Assignment Summary

### Complete Flow

1. **Coach** assigns workout
2. **Athlete** sees workout in Teams tab
3. **Athlete** submits via scan/upload
4. **Coach** views:
   - Submission tracker
   - Clicks a name to see their results
   - Completion status
