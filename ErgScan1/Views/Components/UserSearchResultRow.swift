//
//  UserSearchResultRow.swift
//  ErgScan1
//
//  Created by Claude on 2/11/26.
//

import SwiftUI

struct UserSearchResultRow: View {
    let user: SocialService.UserProfileResult
    let sentRequestIDs: Set<String>
    let friendIDs: Set<String>
    let onAddFriend: () -> Void

    private var isFriend: Bool {
        friendIDs.contains(user.id)
    }

    private var alreadyRequested: Bool {
        sentRequestIDs.contains(user.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("@\(user.username)")
                    .font(.headline)

                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isFriend {
                Text("Friends")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            } else if alreadyRequested {
                Text("Requested")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Button {
                    HapticService.shared.lightImpact()
                    onAddFriend()
                } label: {
                    Text("Add Friend")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
