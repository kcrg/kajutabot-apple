import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppState()

    var body: some View {
        Group {
            switch app.authState {
            case .restoring:
                ProgressView("Przywracanie sesji…")
            case let .signedOut(message):
                LoginView(app: app, message: message)
            case let .recoverableError(message):
                ContentUnavailableView {
                    Label("Nie można przywrócić sesji", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Spróbuj ponownie") { app.retryRestore() }
                }
            case .signedIn:
                AuthenticatedRootView(app: app)
            }
        }
        .preferredColorScheme(app.preferredColorScheme)
        .task { await app.initializeIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.sceneBecameActive()
            case .inactive, .background: app.sceneBecameInactive()
            @unknown default: break
            }
        }
    }
}

private struct AuthenticatedRootView: View {
    @Bindable var app: AppState

    var body: some View {
        Group {
            switch app.guildAccessState {
            case .checking:
                ProgressView(app.isGuest ? "Łączenie z serwerem demonstracyjnym…" : "Sprawdzanie serwerów Discord…")
            case .error:
                ContentUnavailableView {
                    Label("Nie udało się pobrać serwerów", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(app.guildAccessError ?? "Spróbuj ponownie.")
                } actions: {
                    Button("Spróbuj ponownie") { app.refreshGuilds() }
                    Button("Wyloguj", role: .destructive) { app.logout() }
                }
            case .none:
                ContentUnavailableView {
                    Label("Brak dostępu", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(app.isGuest ? "Tryb gościa nie ma teraz dostępu do serwera demonstracyjnego." : "KajutaBot nie jest dostępny na żadnym z Twoich serwerów Discord.")
                } actions: {
                    Button("Odśwież") { app.refreshGuilds() }
                    Button("Wyloguj", role: .destructive) { app.logout() }
                }
            case .available:
                if app.shouldShowOnboarding {
                    OnboardingView(app: app)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    MainTabView(app: app)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.32), value: app.shouldShowOnboarding)
    }
}

#Preview {
    ContentView()
}
