//
//  FriendRequestCard.swift
//  ErgScan1
//
//  Created by Claude on 2/11/26.
//

import SwiftUI

struct FriendRequestCard: View {
    let request: SocialService.FriendRequestResult
    let onAccept: () -> Void
    let onReject: () -> Void

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
                Text("@\(request.senderUsername)")
                    .font(.headline)

                Text(request.senderDisplayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    HapticService.shared.lightImpact()
                    onReject()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .clipShape(Circle())
                }

                Button {
                    HapticService.shared.lightImpact()
                    onAccept()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.green)
                        .clipShape(Circle())
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
