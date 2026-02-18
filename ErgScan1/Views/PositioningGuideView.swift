import SwiftUI

/// Decorative square guide showing where the crop region is.
/// Spans the full width of the frame, centered vertically.
struct PositioningGuideView: View {

    var hint: String = "Zoom in so erg LCD fills the square"

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let yOffset = (geometry.size.height - side) / 2

            ZStack {
                // Dimmed background outside the guide
                Color.black.opacity(0.5)

                // Square cutout
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: side, height: side)
                    .offset(y: yOffset > 0 ? 0 : 0)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .blendMode(.destinationOut)

                // Square border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: side, height: side)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Instruction text above the guide
                VStack {
                    Text(hint)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                        )
                        .padding(.top, max(yOffset - 30, 4))

                    Spacer()
                }
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.gray
        PositioningGuideView()
    }
}
