//
//  FriendActivityCard.swift
//  ErgScan1
//
//  Created by Claude on 2/11/26.
//

import SwiftUI

struct FriendActivityCard: View {
    let workout: SocialService.SharedWorkoutResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: username and date
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(workout.ownerUsername)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(workout.ownerDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(workout.workoutDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Workout details
            VStack(alignment: .leading, spacing: 8) {
                // Workout type
                Text(workout.workoutType)
                    .font(.headline)

                HStack(spacing: 16) {
                    // Distance
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(workout.totalDistance)m")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    // Average split
                    if !workout.averageSplit.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avg Split")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(workout.averageSplit)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }

                    Spacer()

                    // Zone badge
                    if !workout.intensityZone.isEmpty {
                        if let zone = IntensityZone(rawValue: workout.intensityZone) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(zone.color)
                                    .frame(width: 8, height: 8)
                                Text(zone.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(zone.color.opacity(0.2))
                            .cornerRadius(6)
                        }
                    }

                    // Erg test flag
                    if workout.isErgTest {
                        Image(systemName: "flag.checkered")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
