import Foundation

enum APIUserMessage {
    static func message(for error: APIError) -> String {
        switch error {
        case .invalidResponse, .decoding:
            return String(localized: "errorInvalidServerResponse")
        case let .http(status, problem):
            switch problem?.errorCode {
            case "queue_version_conflict": return String(localized: .queueChangedRefreshed)
            case "queue_persistence_conflict": return String(localized: "errorQueuePersistence")
            case "queue_full": return String(localized: "errorQueueFull")
            case "content_unavailable": return String(localized: "errorContentUnavailable")
            case "queue_bound_to_other_channel": return String(localized: "errorQueueOtherChannel")
            case "guild_access_denied", "discord_guild_access_denied": return String(localized: "errorAccessDenied")
            case "search_failed": return String(localized: "errorSearchFailed")
            default:
                switch status {
                case 401: return String(localized: .sessionExpired)
                case 403: return String(localized: "errorAccessDenied")
                case 409: return String(localized: .queueChangedRefreshed)
                case 429: return String(localized: "errorRateLimit")
                default: return String(localized: "errorServerUnavailable")
                }
            }
        }
    }
}
