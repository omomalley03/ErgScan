import Foundation

// MARK: - Assigned Workout Info

struct AssignedWorkoutInfo: Identifiable, Hashable {
    let id: String              // assignmentID (CloudKit recordName)
    let teamID: String
    let assignerID: String
    let assignerUsername: String
    let workoutName: String
    let description: String
    let startDate: Date
    let endDate: Date
    let createdAt: Date

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var isPast: Bool {
        Date() > endDate
    }

    var isFuture: Bool {
        Date() < startDate
    }

    var daysUntilDue: Int {
        let calendar = Calendar.current
        let now = Date()
        if let days = calendar.dateComponents([.day], from: now, to: endDate).day {
            return days
        }
        return 0
    }
}

// MARK: - Workout Submission Info

struct WorkoutSubmissionInfo: Identifiable, Hashable {
    let id: String              // submissionID (CloudKit recordName)
    let assignmentID: String
    let teamID: String
    let submitterID: String
    let submitterUsername: String
    let workoutRecordID: String          // UUID linking to local Workout
    let sharedWorkoutRecordID: String?   // Optional CloudKit SharedWorkout ID
    let submittedAt: Date
    let totalDistance: Int
    let totalTime: String
    let averageSplit: String
}

// MARK: - Assignment Errors

enum AssignmentError: LocalizedError {
    case notCoach
    case invalidDates
    case missingTeam
    case alreadySubmitted
    case submissionNotFound
    case cloudKitError(String)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notCoach:
            return "Only coaches can create assignments"
        case .invalidDates:
            return "End date must be after start date"
        case .missingTeam:
            return "Team information is missing"
        case .alreadySubmitted:
            return "You have already submitted this assignment"
        case .submissionNotFound:
            return "Submission could not be found"
        case .cloudKitError(let message):
            return "CloudKit error: \(message)"
        case .notAuthorized:
            return "You are not authorized to perform this action"
        }
    }
}

// MARK: - Assignment Status Helper

struct AssignmentStatus {
    let assignment: AssignedWorkoutInfo
    let hasSubmitted: Bool
    let submission: WorkoutSubmissionInfo?

    var statusText: String {
        if hasSubmitted {
            return "Completed"
        } else if assignment.isPast {
            return "Overdue"
        } else if assignment.daysUntilDue == 0 {
            return "Due today"
        } else if assignment.daysUntilDue == 1 {
            return "Due tomorrow"
        } else {
            return "Due in \(assignment.daysUntilDue) days"
        }
    }

    var statusColor: String {
        if hasSubmitted {
            return "green"
        } else if assignment.isPast {
            return "red"
        } else if assignment.daysUntilDue <= 1 {
            return "orange"
        } else {
            return "blue"
        }
    }
}

// MARK: - Submission Tracker Entry

/// Represents a team member's submission status for coach tracking view
struct SubmissionTrackerEntry: Identifiable {
    let id: String              // membershipID
    let username: String
    let displayName: String
    let hasSubmitted: Bool
    let submission: WorkoutSubmissionInfo?

    var submittedAtText: String? {
        guard let submission = submission else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: submission.submittedAt)
    }
}
