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
}
