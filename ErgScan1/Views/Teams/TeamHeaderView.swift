import SwiftUI

struct TeamHeaderView: View {
    let team: TeamInfo
    let memberCount: Int

    var body: some View {
        VStack(spacing: 12) {
            // Team avatar
            if let imageData = team.profilePicData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    )
            }

            Text(team.name)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
