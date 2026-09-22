import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct PKCEData: Sendable {
    let verifier: String
    let challenge: String
    let state: String
}

enum OAuthError: LocalizedError {
    case notConfigured
    case invalidCallback
    case cancelled
    case stateMismatch
    case missingCode
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Brak konfiguracji Discord Client ID."
        case .invalidCallback: "Nieprawidłowa odpowiedź logowania Discord."
        case .cancelled: "Logowanie przez Discord zostało anulowane."
        case .stateMismatch: "Stan logowania nie zgadza się z rozpoczętą próbą."
        case .missingCode: "Discord nie zwrócił kodu autoryzacji."
        case .randomGenerationFailed: "Nie udało się wygenerować bezpiecznych danych logowania."
        }
    }
}

@MainActor
final class DiscordOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(config: AppConfig) async throws -> DiscordOAuthExchangeRequest {
        guard config.isOAuthConfigured else { throw OAuthError.notConfigured }
        let pkce = try makePKCE()
        var components = URLComponents(string: "https://discord.com/oauth2/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: config.discordClientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: "identify"),
            .init(name: "state", value: pkce.state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let authorizationURL = components.url else { throw OAuthError.invalidCallback }

        defer { session = nil }
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: config.callbackScheme) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            session = authSession
            guard authSession.start() else {
                continuation.resume(throwing: OAuthError.invalidCallback)
                return
            }
        }

        let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let items = callback?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" { throw OAuthError.cancelled }
            throw OAuthError.invalidCallback
        }
        guard items.first(where: { $0.name == "state" })?.value == pkce.state else { throw OAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw OAuthError.missingCode }
        return DiscordOAuthExchangeRequest(code: code, codeVerifier: pkce.verifier, redirectUri: config.redirectURI)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return keyWindow }
        if let windowScene = scenes.first, let window = windowScene.windows.first {
            return window
        }
        if let windowScene = scenes.first {
            return ASPresentationAnchor(windowScene: windowScene)
        }
        return ASPresentationAnchor()
    }

    private func makePKCE() throws -> PKCEData {
        let verifier = try randomURLSafeString(byteCount: 64)
        let state = try randomURLSafeString(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCEData(verifier: verifier, challenge: challenge, state: state)
    }

    private func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw OAuthError.randomGenerationFailed }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
