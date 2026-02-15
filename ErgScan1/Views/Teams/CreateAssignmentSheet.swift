import SwiftUI

struct CreateAssignmentSheet: View {
    let teamID: String
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var assignmentService: AssignmentService

    @State private var workoutName = ""
    @State private var description = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default: 1 week from now
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !workoutName.trimmingCharacters(in: .whitespaces).isEmpty &&
        endDate > startDate &&
        startDate >= Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Details") {
                    TextField("Workout Name", text: $workoutName)
                        .textInputAutocapitalization(.words)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Timeline") {
                    DatePicker(
                        "Opens",
                        selection: $startDate,
                        in: Date()...,
                        displayedComponents: [.date]
                    )

                    DatePicker(
                        "Due Date",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: [.date]
                    )

                    if endDate <= startDate {
                        Text("Due date must be after start date")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        createAssignment()
                    } label: {
                        if isCreating {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Create Assignment")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(!isValid || isCreating)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    private func createAssignment() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await assignmentService.createAssignment(
                    teamID: teamID,
                    name: workoutName.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    startDate: startDate,
                    endDate: endDate
                )

                await MainActor.run {
                    isCreating = false
                    onCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
