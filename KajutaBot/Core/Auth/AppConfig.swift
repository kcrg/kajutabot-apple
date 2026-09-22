import Foundation

struct AppConfig: Sendable {
    let apiBaseURL: URL
    let discordClientId: String

    init(bundle: Bundle = .main) {
        let rawBase = Self.stringValue(
            bundle.object(forInfoDictionaryKey: "KAJUTABOT_API_BASE_URL")
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        apiBaseURL = URL(
            string: rawBase?.isEmpty == false
                ? rawBase!
                : "https://api.kajuta.tryniecki.eu"
        )!

        discordClientId = Self.stringValue(
            bundle.object(forInfoDictionaryKey: "KAJUTABOT_DISCORD_CLIENT_ID")
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
    }

    var redirectURI: String { "discord-\(discordClientId):/authorize/callback" }
    var callbackScheme: String { "discord-\(discordClientId)" }

    var isOAuthConfigured: Bool {
        !discordClientId.isEmpty
            && discordClientId != "$(KAJUTABOT_DISCORD_CLIENT_ID)"
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        case let value as NSString:
            return value as String
        case .none:
            return nil
        default:
            return String(describing: value!)
        }
    }
}
