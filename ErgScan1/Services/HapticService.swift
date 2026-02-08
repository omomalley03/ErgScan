import UIKit

/// Centralized haptic feedback management
@MainActor
final class HapticService {

    private let successGenerator = UINotificationFeedbackGenerator()

    /// Prepare the haptic generator for immediate response
    func prepare() {
        successGenerator.prepare()
    }

    /// Trigger success haptic feedback
    func triggerSuccess() {
        successGenerator.notificationOccurred(.success)
    }
}
