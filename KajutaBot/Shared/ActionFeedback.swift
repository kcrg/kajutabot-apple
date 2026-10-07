import SwiftUI

struct ActionFeedback: View {
    let status: ActionStatus?
    let symbol: String
    var showsSuccess = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinnerReady = false

    private var showsSpinner: Bool { status == .pending && spinnerReady }

    private var displayedSymbol: String {
        switch status {
        case .success where showsSuccess: "checkmark"
        case .failure: "exclamationmark.triangle"
        default: symbol
        }
    }

    private var feedbackColor: Color? {
        switch status {
        case .success where showsSuccess: .green
        case .failure: .red
        default: nil
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: displayedSymbol)
                .foregroundStyle(feedbackColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.magic(fallback: .downUp)))
                .opacity(showsSpinner ? 0 : 1)
            if showsSpinner {
                ProgressView().controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(width: 24, height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: displayedSymbol)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsSpinner)
        .accessibilityHidden(true)
        .task(id: status) {
            spinnerReady = false
            guard status == .pending else { return }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            spinnerReady = true
        }
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
    func actionFeedbackAccessibility(_ status: ActionStatus?, showsSuccess: Bool = false) -> some View {
        let value: String
        switch status {
        case .pending: value = String(localized: .inProgress)
        case .success: value = showsSuccess ? String(localized: "actionSucceeded") : ""
        case .failure: value = String(localized: "actionFailed")
        case nil: value = ""
        }
        return accessibilityValue(value)
    }
}
