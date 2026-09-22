import SwiftUI

struct MoreView: View {
    @Bindable var app: AppState

    var body: some View {
        Form {
            Section("Konto") {
                HStack(spacing: 14) {
                    if !app.isGuest {
                        ArtworkView(urlString: app.currentUser?.avatarUrl, layout: .square(58), cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.currentUser?.displayName ?? "-")
                            .font(.headline)
                        Text(app.isGuest ? "Tryb gościa" : "@\(app.currentUser?.username ?? "-")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wyloguj", role: .destructive) { app.logout() }
                        .disabled(app.isSigningIn)
                }
                .padding(.vertical, 4)

                if app.isGuest {
                    Link("Dołącz do serwera testowego", destination: URL(string: "https://discord.gg/7jV7j5djF")!)
                    Button("Zaloguj przez Discord") { app.switchGuestToDiscord() }
                }
            }

            Section("Połączenie realtime") {
                RealtimeStatusView(realtime: app.realtime)
            }

            Section("Motyw") {
                Picker("Motyw", selection: $app.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Pomoc") {
                Button {
                    app.manualOnboardingRequested = true
                } label: {
                    SettingsLabel(icon: "signpost.right", title: "Przewodnik po aplikacji", subtitle: "Uruchom onboarding ponownie")
                }
                .buttonStyle(.plain)
            }

            Section("O aplikacji") {
                NavigationLink {
                    LibrariesView()
                } label: {
                    SettingsLabel(icon: "info.circle", title: "Użyte biblioteki", subtitle: "Komponenty i frameworki")
                }
                NavigationLink {
                    ContactView()
                } label: {
                    SettingsLabel(icon: "envelope", title: "Kontakt", subtitle: "Kacper Tryniecki")
                }
            }
        }
        .navigationTitle("Więcej")
    }
}

private struct RealtimeStatusView: View {
    @Bindable var realtime: RealtimeClient

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
                Text("Ostatnia ramka: \(ageLabel(realtime.lastFrameAt, now: context.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ostatnia aktualizacja danych: \(ageLabel(realtime.lastQueueUpdateAt, now: context.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if realtime.reconnectAttempts > 0 {
                    Text("Próby ponownego połączenia: \(realtime.reconnectAttempts)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func ageLabel(_ date: Date?, now: Date) -> String {
        guard let date else { return "brak danych" }
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 { return "\(seconds) s temu" }
        if seconds < 3_600 { return "\(seconds / 60) min temu" }
        return "\(seconds / 3_600) godz. temu"
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: String
    let subtitle: String

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
    let description: String
    let license: String
    var id: String { name }
}

private struct LibrariesView: View {
    private let libraries: [LibraryInfo] = [
        .init(name: "SwiftUI", description: "Deklaratywny interfejs i animacje", license: "Apple SDK"),
        .init(name: "Observation", description: "Obserwowalny stan aplikacji", license: "Apple SDK"),
        .init(name: "URLSession", description: "REST API i WebSocket SignalR", license: "Apple SDK"),
        .init(name: "AuthenticationServices", description: "Discord OAuth przez ASWebAuthenticationSession", license: "Apple SDK"),
        .init(name: "CryptoKit", description: "PKCE SHA-256", license: "Apple SDK"),
        .init(name: "Security / Keychain", description: "Bezpieczne przechowywanie sesji", license: "Apple SDK"),
        .init(name: "Nuke", description: "Ładowanie, cache i pipeline obrazów", license: "MIT"),
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
        .navigationTitle("Użyte biblioteki")
    }
}

private struct ContactView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kacper Tryniecki").font(.headline)
                    Text("Autor KajutaBot").font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "mailto:kacper@tryniecki.com")!) {
                    Label("kacper@tryniecki.com", systemImage: "envelope")
                }
                Link(destination: URL(string: "https://github.com/kcrg")!) {
                    Label("github.com/kcrg", systemImage: "link")
                }
            }
        }
        .navigationTitle("Kontakt")
    }
}
