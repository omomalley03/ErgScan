import SwiftUI

struct FullScreenImageViewer: View {
    let image: UIImage
    let workoutType: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    // Clamp scale between 1x and 4x
                                    if scale < 1.0 {
                                        withAnimation { scale = 1.0; lastScale = 1.0 }
                                    } else if scale > 4.0 {
                                        withAnimation { scale = 4.0; lastScale = 4.0 }
                                    }
                                }
                        )
                }
            }
            .background(Color.black)
            .navigationTitle(workoutType)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
