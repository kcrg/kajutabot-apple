import SwiftUI

struct LoginView: View {
    @Bindable var app: AppState
    let message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                BrandMark()
                Text("KajutaBot")
                    .font(.largeTitle.bold())
                    .padding(.top, 20)
                Text("Steruj muzyką na Discordzie z telefonu. Zaloguj się przez Discord albo wypróbuj aplikację od razu w trybie gościa.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                if !app.config.isOAuthConfigured {
                    MessageCard(text: "Brak konfiguracji Discord Client ID. Uzupełnij KAJUTABOT_DISCORD_CLIENT_ID w Build Settings.")
                        .padding(.top, 24)
                }
                if let message {
                    MessageCard(text: message)
                        .padding(.top, 12)
                }

                Button {
                    app.signInWithDiscord()
                } label: {
                    HStack {
                        if app.isSigningIn && !app.isGuestSigningIn { ProgressView().controlSize(.small) }
                        Text(app.isSigningIn && !app.isGuestSigningIn ? "Logowanie…" : "Zaloguj przez Discord")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.isSigningIn || !app.config.isOAuthConfigured)
                .padding(.top, 28)

                Button {
                    app.signInAsGuest()
                } label: {
                    HStack {
                        if app.isGuestSigningIn { ProgressView().controlSize(.small) }
                        Text(app.isGuestSigningIn ? "Logowanie…" : "Wypróbuj jako gość")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .disabled(app.isSigningIn)
                .padding(.top, 10)
                Spacer(minLength: 80)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MessageCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.red)
    }
}
