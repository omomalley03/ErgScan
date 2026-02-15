import Foundation
import CloudKit
import SwiftData
import Combine

@MainActor
class AssignmentService: ObservableObject {
    @Published var myAssignments: [AssignedWorkoutInfo] = []
    @Published var mySubmissions: [WorkoutSubmissionInfo] = []
    @Published var assignmentDetails: [String: [WorkoutSubmissionInfo]] = [:] // keyed by assignmentID

    private let container = CKContainer.default()
    private let publicDB = CKContainer.default().publicCloudDatabase
    private var currentUserID: String?
    private var currentUsername: String?

    // MARK: - Setup

    func setCurrentUser(userID: String, username: String) {
        self.currentUserID = userID
        self.currentUsername = username
    }

    // MARK: - Create Assignment (Coach only)

    func createAssignment(
        teamID: String,
        name: String,
        description: String,
        startDate: Date,
        endDate: Date
    ) async throws {
        guard let userID = currentUserID, let username = currentUsername else {
            throw AssignmentError.notAuthorized
        }

        // Validate dates
        guard endDate > startDate else {
            throw AssignmentError.invalidDates
        }

        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "AssignedWorkout", recordID: recordID)

        record["teamID"] = teamID
        record["assignerID"] = userID
        record["assignerUsername"] = username
        record["workoutName"] = name
        record["description"] = description
        record["startDate"] = startDate
        record["endDate"] = endDate
        record["createdAt"] = Date()

        do {
            _ = try await publicDB.save(record)
        } catch {
            throw AssignmentError.cloudKitError(error.localizedDescription)
        }
    }

    // MARK: - Load Assignments for Team

    func loadAssignments(teamID: String) async {
        guard currentUserID != nil else { return }

        let predicate = NSPredicate(format: "teamID == %@", teamID)
        let query = CKQuery(recordType: "AssignedWorkout", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: true)]

        do {
            let results = try await publicDB.records(matching: query)
            let assignments = results.matchResults.compactMap { _, result -> AssignedWorkoutInfo? in
                guard case .success(let record) = result else { return nil }
                return parseAssignedWorkout(record)
            }
            self.myAssignments = assignments
        } catch {
            print("Failed to load assignments: \(error)")
        }
    }

    // MARK: - Load Submissions for Assignment (Coach view)

    func loadSubmissions(assignmentID: String, teamID: String) async {
        let predicate = NSPredicate(
            format: "assignmentID == %@ AND teamID == %@",
            assignmentID, teamID
        )
        let query = CKQuery(recordType: "WorkoutSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "submittedAt", ascending: false)]

        do {
            let results = try await publicDB.records(matching: query)
            let submissions = results.matchResults.compactMap { _, result -> WorkoutSubmissionInfo? in
                guard case .success(let record) = result else { return nil }
                return parseWorkoutSubmission(record)
            }
            self.assignmentDetails[assignmentID] = submissions
        } catch {
            print("Failed to load submissions: \(error)")
        }
    }

    // MARK: - Load My Submissions

    func loadMySubmissions(teamID: String) async {
        guard let userID = currentUserID else { return }

        let predicate = NSPredicate(
            format: "submitterID == %@ AND teamID == %@",
            userID, teamID
        )
        let query = CKQuery(recordType: "WorkoutSubmission", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "submittedAt", ascending: false)]

        do {
            let results = try await publicDB.records(matching: query)
            let submissions = results.matchResults.compactMap { _, result -> WorkoutSubmissionInfo? in
                guard case .success(let record) = result else { return nil }
                return parseWorkoutSubmission(record)
            }
            self.mySubmissions = submissions
        } catch {
            print("Failed to load my submissions: \(error)")
        }
    }

    // MARK: - Submit Workout

    func submitWorkout(
        assignmentID: String,
        teamID: String,
        workoutRecordID: String,
        sharedWorkoutRecordID: String?,
        totalDistance: Int,
        totalTime: String,
        averageSplit: String
    ) async throws {
        guard let userID = currentUserID, let username = currentUsername else {
            throw AssignmentError.notAuthorized
        }

        // Check if already submitted
        if hasSubmitted(assignmentID: assignmentID) {
            throw AssignmentError.alreadySubmitted
        }

        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "WorkoutSubmission", recordID: recordID)

        record["assignmentID"] = assignmentID
        record["teamID"] = teamID
        record["submitterID"] = userID
        record["submitterUsername"] = username
        record["workoutRecordID"] = workoutRecordID
        record["sharedWorkoutRecordID"] = sharedWorkoutRecordID
        record["submittedAt"] = Date()
        record["totalDistance"] = totalDistance
        record["totalTime"] = totalTime
        record["averageSplit"] = averageSplit

        do {
            let savedRecord = try await publicDB.save(record)
            if let submission = parseWorkoutSubmission(savedRecord) {
                self.mySubmissions.append(submission)
            }
        } catch {
            throw AssignmentError.cloudKitError(error.localizedDescription)
        }
    }

    // MARK: - Check if User Has Submitted

    func hasSubmitted(assignmentID: String) -> Bool {
        return mySubmissions.contains { $0.assignmentID == assignmentID }
    }

    // MARK: - Get Assignment Status

    func getAssignmentStatus(assignmentID: String) -> AssignmentStatus? {
        guard let assignment = myAssignments.first(where: { $0.id == assignmentID }) else {
            return nil
        }
        let hasSubmitted = hasSubmitted(assignmentID: assignmentID)
        let submission = mySubmissions.first { $0.assignmentID == assignmentID }
        return AssignmentStatus(
            assignment: assignment,
            hasSubmitted: hasSubmitted,
            submission: submission
        )
    }

    // MARK: - Parsing Helpers

    private func parseAssignedWorkout(_ record: CKRecord) -> AssignedWorkoutInfo? {
        guard
            let teamID = record["teamID"] as? String,
            let assignerID = record["assignerID"] as? String,
            let assignerUsername = record["assignerUsername"] as? String,
            let workoutName = record["workoutName"] as? String,
            let description = record["description"] as? String,
            let startDate = record["startDate"] as? Date,
            let endDate = record["endDate"] as? Date,
            let createdAt = record["createdAt"] as? Date
        else {
            return nil
        }

        return AssignedWorkoutInfo(
            id: record.recordID.recordName,
            teamID: teamID,
            assignerID: assignerID,
            assignerUsername: assignerUsername,
            workoutName: workoutName,
            description: description,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt
        )
    }

    private func parseWorkoutSubmission(_ record: CKRecord) -> WorkoutSubmissionInfo? {
        guard
            let assignmentID = record["assignmentID"] as? String,
            let teamID = record["teamID"] as? String,
            let submitterID = record["submitterID"] as? String,
            let submitterUsername = record["submitterUsername"] as? String,
            let workoutRecordID = record["workoutRecordID"] as? String,
            let submittedAt = record["submittedAt"] as? Date,
            let totalDistance = record["totalDistance"] as? Int,
            let totalTime = record["totalTime"] as? String,
            let averageSplit = record["averageSplit"] as? String
        else {
            return nil
        }

        let sharedWorkoutRecordID = record["sharedWorkoutRecordID"] as? String

        return WorkoutSubmissionInfo(
            id: record.recordID.recordName,
            assignmentID: assignmentID,
            teamID: teamID,
            submitterID: submitterID,
            submitterUsername: submitterUsername,
            workoutRecordID: workoutRecordID,
            sharedWorkoutRecordID: sharedWorkoutRecordID,
            submittedAt: submittedAt,
            totalDistance: totalDistance,
            totalTime: totalTime,
            averageSplit: averageSplit
        )
    }

    // MARK: - Build Submission Tracker

    /// For coach view: cross-reference roster with submissions
    func buildSubmissionTracker(
        assignmentID: String,
        roster: [TeamMembershipInfo]
    ) -> [SubmissionTrackerEntry] {
        let submissions = assignmentDetails[assignmentID] ?? []
        let submitterIDs = Set(submissions.map { $0.submitterID })

        return roster.map { member in
            let hasSubmitted = submitterIDs.contains(member.userID)
            let submission = submissions.first { $0.submitterID == member.userID }
            return SubmissionTrackerEntry(
                id: member.id,
                username: member.username,
                displayName: member.displayName,
                hasSubmitted: hasSubmitted,
                submission: submission
            )
        }
    }
}
