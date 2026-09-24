import SwiftUI

struct MoreView: View {
    let app: AppState

    var body: some View {
        Form {
            Section(.accountSection) {
                HStack(spacing: 14) {
                    if !app.isGuest {
                        ArtworkView(urlString: app.currentUser?.avatarUrl, layout: .square(58), cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.currentUser?.displayName ?? "-")
                            .font(.headline)
                        Text(app.isGuest ? String(localized: .guestMode) : "@\(app.currentUser?.username ?? "-")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(.logout, role: .destructive) { app.logout() }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .disabled(app.isSigningIn)
                }
                .padding(.vertical, 4)

                if app.isGuest {
                    Link(String(localized: .joinTestServer), destination: URL(string: "https://discord.gg/7jV7j5djF")!)
                    Button(.signInDiscord) { app.switchGuestToDiscord() }
                }
            }

            Section(.realtimeSection) {
                RealtimeStatusView(realtime: app.realtime)
            }

            Section(.helpSection) {
                Button {
                    app.manualOnboardingRequested = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsLabel(icon: "signpost.right", title: .appGuideTitle, subtitle: .appGuideSubtitle)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section(.aboutSection) {
                NavigationLink {
                    LibrariesView()
                } label: {
                    SettingsLabel(icon: "info.circle", title: .librariesTitle, subtitle: .librariesSubtitle)
                }
                NavigationLink {
                    ContactView()
                } label: {
                    SettingsLabel(icon: "envelope", title: .contactTitle, subtitle: .contactSubtitle)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.moreTitle)
    }
}

private struct RealtimeStatusView: View {
    let realtime: RealtimeClient

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(realtime.state == .connected ? Color.accentColor : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(realtime.state.label)
                        .font(.headline)
                }
                Text(.lastFrame(value: ageLabel(realtime.lastFrameAt, now: context.date)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(.lastDataUpdate(value: ageLabel(realtime.lastQueueUpdateAt, now: context.date)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if realtime.reconnectAttempts > 0 {
                    Text(.reconnectAttempts(count: realtime.reconnectAttempts))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func ageLabel(_ date: Date?, now: Date) -> String {
        guard let date else { return String(localized: .noData) }
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return String(localized: .secondsAgo(count: seconds)) }
        if seconds < 3_600 { return String(localized: .minutesAgo(count: seconds / 60)) }
        return String(localized: .hoursAgo(count: seconds / 3_600))
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct LibraryInfo: Identifiable {
    let name: String
    let description: LocalizedStringResource
    let license: String
    var id: String { name }
}

private struct LibrariesView: View {
    private let libraries: [LibraryInfo] = [
        .init(name: "SwiftUI", description: .librarySwiftUIDescription, license: "Apple SDK"),
        .init(name: "Observation", description: .libraryObservationDescription, license: "Apple SDK"),
        .init(name: "URLSession", description: .libraryURLSessionDescription, license: "Apple SDK"),
        .init(name: "AuthenticationServices", description: .libraryAuthenticationServicesDescription, license: "Apple SDK"),
        .init(name: "CryptoKit", description: .libraryCryptoKitDescription, license: "Apple SDK"),
        .init(name: "Security / Keychain", description: .libraryKeychainDescription, license: "Apple SDK"),
        .init(name: "Nuke", description: .libraryNukeDescription, license: "MIT"),
        .init(name: "SignalRClient", description: .librarySignalRDescription, license: "MIT"),
        .init(name: "Swift Async Algorithms", description: .libraryAsyncAlgorithmsDescription, license: "Apache 2.0"),
    ]

    var body: some View {
        List(libraries) { library in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(library.name)
                    Spacer()
                    Text(library.license).font(.caption).foregroundStyle(.secondary)
                }
                Text(library.description).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.librariesTitle)
    }
}

private struct ContactView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Kacper Tryniecki").font(.headline)
                    Text(.authorKajutaBot).font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "mailto:kacper@tryniecki.com")!) {
                    Label { Text(verbatim: "kacper@tryniecki.com") } icon: { Image(systemName: "envelope") }
                }
                Link(destination: URL(string: "https://github.com/kcrg")!) {
                    Label { Text(verbatim: "github.com/kcrg") } icon: { Image(systemName: "link") }
                }
            }
        }
        .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.contactTitle)
    }
}
