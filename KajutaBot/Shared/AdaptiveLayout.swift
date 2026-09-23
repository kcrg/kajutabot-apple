import SwiftUI

enum AppLayout {
    static let primaryContentMaxWidth: CGFloat = 760
    static let settingsContentMaxWidth: CGFloat = 680
    static let onboardingContentMaxWidth: CGFloat = 760
}

extension View {
    /// Keeps phone layouts full-width while preventing content from stretching
    /// excessively in regular-width iPad windows.
    func adaptiveContentWidth(_ maxWidth: CGFloat) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
