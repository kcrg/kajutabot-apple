import Foundation
import Pulse
import PulseProxy

/// Always-on, on-device diagnostics used by the hidden diagnostics console.
///
/// Pulse persists network traffic and application logs locally. Secrets are
/// redacted before they reach the store because diagnostics are enabled in
/// Release builds as well.
enum Diagnostics {
    static func bootstrap() {
        LoggerStore.shared.configuration.sizeLimit = 20 * 1_000_000
        LoggerStore.shared.configuration.maxAge = 3 * 86_400

        NetworkLogger.shared = NetworkLogger {
            $0.label = "KajutaBot"
            $0.sensitiveHeaders = [
                "Authorization",
                "Cookie",
                "Set-Cookie",
                "X-Api-Key",
                "X-API-Key",
                "X-Auth-Token",
            ]
            $0.sensitiveQueryItems = [
                "access_token",
                "refresh_token",
                "token",
                "code",
            ]
            $0.sensitiveDataFields = [
                "accessToken",
                "access_token",
                "refreshToken",
                "refresh_token",
                "token",
                "authorization",
                "code",
            ]
        }

        // Intentionally enabled in Release too. Access to the UI is hidden
        // behind the Discord-account gesture in MoreView.
        NetworkLogger.enableProxy()
        info("app", "Diagnostics initialized")
    }

    static func trace(_ label: String, _ message: String) {
        LoggerStore.shared.storeMessage(label: label, level: .trace, message: message)
    }

    static func debug(_ label: String, _ message: String) {
        LoggerStore.shared.storeMessage(label: label, level: .debug, message: message)
    }

    static func info(_ label: String, _ message: String) {
        LoggerStore.shared.storeMessage(label: label, level: .info, message: message)
    }

    static func warning(_ label: String, _ message: String) {
        LoggerStore.shared.storeMessage(label: label, level: .warning, message: message)
    }

    static func error(_ label: String, _ message: String) {
        LoggerStore.shared.storeMessage(label: label, level: .error, message: message)
    }
}
