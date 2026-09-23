import SwiftUI

struct LoginView: View {
    let app: AppState
    let message: String?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    BrandMark()
                    Text(verbatim: "KajutaBot")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)
                    Text(.loginSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    if !app.config.isOAuthConfigured {
                        MessageCard(text: String(localized: .discordClientIdMissing))
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
                            Text(app.isSigningIn && !app.isGuestSigningIn ? String(localized: .signingIn) : String(localized: .signInDiscord))
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
                            Text(app.isGuestSigningIn ? String(localized: .signingIn) : String(localized: .tryAsGuest))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.isSigningIn)
                    .padding(.top, 10)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
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
