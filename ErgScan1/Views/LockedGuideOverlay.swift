import SwiftUI

/// Visual overlay shown when workout data is locked for review
struct LockedGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.3)

                // Green checkmark in center
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                        .shadow(color: .black.opacity(0.3), radius: 10)

                    // "Review Workout" text
                    Text("Review Workout")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.7))
                        )
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.gray
        LockedGuideOverlay()
    }
}
