import SwiftUI

struct ActionFeedback: View {
    let status: ActionStatus?
    let symbol: String

    var body: some View {
        Group {
            switch status {
            case .pending: ProgressView().controlSize(.small)
            case .success: Image(systemName: "checkmark").foregroundStyle(.green)
            case .failure: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            case nil: Image(systemName: symbol)
            }
        }
        .frame(minWidth: 24, minHeight: 24)
        .accessibilityHidden(true)
    }
}

struct OperationError: ViewModifier {
    @Bindable var app: AppState

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let message = app.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    Button(.ok) { app.dismissError() }
                }
                .padding()
                .background(.regularMaterial)
                .accessibilityElement(children: .contain)
            }
        }
    }
}

extension View {
    func operationError(_ app: AppState) -> some View { modifier(OperationError(app: app)) }
}

extension View {
    func actionFeedbackAccessibility(_ status: ActionStatus?) -> some View {
        let value: String
        switch status {
        case .pending: value = String(localized: .inProgress)
        case .success: value = String(localized: "actionSucceeded")
        case .failure: value = String(localized: "actionFailed")
        case nil: value = ""
        }
        return accessibilityValue(value)
    }
}
