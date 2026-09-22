import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppState()

    var body: some View {
        ZStack {
            switch app.authState {
            case .restoring:
                StartupView()
                    .transition(.opacity)
            case let .signedOut(message):
                LoginView(app: app, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case let .recoverableError(message):
                ContentUnavailableView {
                    Label("Nie można przywrócić sesji", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Spróbuj ponownie") { app.retryRestore() }
                }
                .transition(.opacity)
            case .signedIn:
                AuthenticatedRootView(app: app)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.32), value: app.authState)
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

private struct StartupView: View {
    private let logoSize: CGFloat = 112
    private let logoVerticalOffset: CGFloat = -18

    var body: some View {
        ZStack {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .offset(y: logoVerticalOffset)
                .accessibilityHidden(true)

            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
                .offset(y: 55)
                .accessibilityLabel("Przywracanie sesji")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .ignoresSafeArea()
    }
}

private struct AuthenticatedRootView: View {
    let app: AppState

    var body: some View {
        Group {
            switch app.guildAccessState {
            case .checking:
                if app.onboardingCompleted && !app.manualOnboardingRequested {
                    MainTabView(app: app)
                } else {
                    ProgressView(app.isGuest ? "Łączenie z serwerem demonstracyjnym…" : "Sprawdzanie serwerów Discord…")
                }
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
                ZStack {
                    if app.shouldShowOnboarding {
                        OnboardingView(app: app)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                            .zIndex(1)
                    } else {
                        MainTabView(app: app)
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.45), value: app.shouldShowOnboarding)
            }
        }
    }
}

#Preview {
    ContentView()
}
