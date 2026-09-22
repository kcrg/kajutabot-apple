import Foundation

struct AppConfig: Sendable {
    let apiBaseURL: URL
    let discordClientId: String

    init(bundle: Bundle = .main) {
        let rawBase = (bundle.object(forInfoDictionaryKey: "KAJUTABOT_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        apiBaseURL = URL(string: rawBase?.isEmpty == false ? rawBase! : "https://api.kajuta.tryniecki.eu")!
        discordClientId = ((bundle.object(forInfoDictionaryKey: "KAJUTABOT_DISCORD_CLIENT_ID") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var redirectURI: String { "discord-\(discordClientId):/authorize/callback" }
    var callbackScheme: String { "discord-\(discordClientId)" }
    var isOAuthConfigured: Bool { !discordClientId.isEmpty }
}
