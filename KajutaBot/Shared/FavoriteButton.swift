import SwiftUI

struct FavoriteButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isFavorite: Bool
    let status: ActionStatus?
    var isDisabled = false
    let action: @MainActor () -> Void

    private var stateDescription: Text {
        switch status {
        case .pending: Text(.inProgress)
        case .failure: Text("actionFailed")
        default: Text(isFavorite ? .enabled : .disabled)
        }
    }

    var body: some View {
        Button(action: action) {
            ActionFeedback(status: status, symbol: isFavorite ? "heart.fill" : "heart",
                symbolColor: isFavorite ? .accentColor : .primary)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(isFavorite ? Color.accentColor.opacity(0.16) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFavorite)
        .disabled(isDisabled || status == .pending)
        .accessibilityLabel(Text(isFavorite ? .removeFavorite : .addFavorite))
        .accessibilityValue(stateDescription)
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}
