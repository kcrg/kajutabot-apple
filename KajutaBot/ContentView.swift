import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var app = AppState()

    var body: some View {
        ZStack {
            switch app.authState {
            case .restoring:
                StartupView()
                    .transition(.opacity)
            case let .signedOut(message):
                LoginView(app: app, message: message)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            case let .recoverableError(message):
                ContentUnavailableView {
                    Label(.restoreSessionFailedTitle, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button(.retry) { app.retryRestore() }
                }
                .transition(.opacity)
            case .signedIn:
                AuthenticatedRootView(app: app)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.32), value: app.authState)
        .task { await app.initializeIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.sceneBecameActive()
            case .inactive: app.sceneWillBecomeActive()
            case .background: app.sceneEnteredBackground()
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
                .accessibilityLabel(Text(.restoringSessionAccessibility))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .ignoresSafeArea()
    }
}

private struct AuthenticatedRootView: View {
    let app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch app.guildAccessState {
            case .checking:
                if app.onboardingCompleted && !app.manualOnboardingRequested {
                    MainTabView(app: app)
                        .transition(.opacity)
                } else {
                    ProgressView { Text(app.isGuest ? String(localized: .connectingDemoServer) : String(localized: .checkingDiscordServers)) }
                        .transition(.opacity)
                }
            case .error:
                ContentUnavailableView {
                    Label(.loadGuildsFailedTitle, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(app.guildAccessError ?? String(localized: .retryDefaultMessage))
                } actions: {
                    Button(.retry) { app.refreshGuilds() }
                    Button(.logout, role: .destructive) { app.logout() }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
            case .none:
                ContentUnavailableView {
                    Label(.noAccessTitle, systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(app.isGuest ? String(localized: .guestDemoUnavailable) : String(localized: .noDiscordGuildAccess))
                } actions: {
                    Button(.refresh) { app.refreshGuilds() }
                    Button(.logout, role: .destructive) { app.logout() }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
            case .available:
                ZStack {
                    if app.shouldShowOnboarding {
                        OnboardingView(app: app)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
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
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.45), value: app.shouldShowOnboarding)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28), value: app.guildAccessState)
    }
}

#Preview {
    ContentView()
}
