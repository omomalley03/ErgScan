import SwiftUI

struct BigChupOverlay: View {
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            VStack(spacing: 8) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                    .shadow(color: .orange, radius: 10)
                Text("BIG Chup!")
                    .font(.title.bold())
                    .foregroundColor(.yellow)
            }
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { isShowing = false }
                }
            }
        }
    }
}
