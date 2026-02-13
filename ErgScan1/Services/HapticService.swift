import UIKit

/// Centralized haptic feedback management
@MainActor
final class HapticService {

    static let shared = HapticService()

    private let successGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    private init() {}

    /// Prepare the haptic generator for immediate response
    func prepare() {
        successGenerator.prepare()
        impactGenerator.prepare()
    }

    /// Trigger success haptic feedback
    func triggerSuccess() {
        successGenerator.notificationOccurred(.success)
    }

    /// Trigger light impact haptic feedback
    func lightImpact() {
        impactGenerator.impactOccurred()
    }

    /// Medium impact for chup/like actions
    func chupFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Heavy double-tap impact for Big Chup
    func bigChupFeedback() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            heavy.impactOccurred(intensity: 1.0)
        }
    }

    /// Light impact for hearting a comment
    func commentHeartFeedback() {
        impactGenerator.impactOccurred()
    }
}
