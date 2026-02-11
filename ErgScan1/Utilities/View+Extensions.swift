import SwiftUI
import UIKit

extension View {
    /// Adds a tap gesture to dismiss the keyboard when tapping anywhere on the view
    /// Uses simultaneousGesture to avoid interfering with buttons and other interactive elements
    func dismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
    }
}
