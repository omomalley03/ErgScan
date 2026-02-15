import SwiftUI

struct OnboardingRoleSelectionView: View {
    @Binding var selectedRoles: Set<UserRole>
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("What's your role?")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 40)

            Text("Select all that apply")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach(UserRole.allCases) { role in
                    RoleSelectionCard(
                        role: role,
                        isSelected: selectedRoles.contains(role),
                        onSelect: {
                            if selectedRoles.contains(role) {
                                selectedRoles.remove(role)
                            } else {
                                selectedRoles.insert(role)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(!selectedRoles.isEmpty ? Color.blue : Color.gray)
                    .cornerRadius(14)
            }
            .disabled(selectedRoles.isEmpty)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

private struct RoleSelectionCard: View {
    let role: UserRole
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Group {
                    if role.icon == "figure.rowing" {
                        Image("figure.rowing")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: role.icon)
                            .font(.title2)
                    }
                }
                .foregroundColor(isSelected ? .white : .blue)
                .frame(width: 50, height: 50)
                .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(role.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
