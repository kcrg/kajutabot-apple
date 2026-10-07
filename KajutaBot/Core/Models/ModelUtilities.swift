import Foundation

func formatDuration(_ milliseconds: Int64) -> String {
    guard milliseconds > 0 else { return "--:--" }
    let seconds = milliseconds / 1_000
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remaining = seconds % 60
    return hours > 0
        ? String(format: "%lld:%02lld:%02lld", hours, minutes, remaining)
        : String(format: "%lld:%02lld", minutes, remaining)
}

func favoriteIdentity(_ raw: String?) -> String {
    guard let input = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else { return "" }
    let lower = input.lowercased()
    if lower.hasPrefix("yt:") { return "youtube:" + input.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines) }
    if lower.hasPrefix("sc:") { return "soundcloud-id:" + input.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard let components = URLComponents(string: input), let host = components.host?.lowercased() else { return input }
    let normalizedHost = host.replacingOccurrences(of: "www.", with: "").replacingOccurrences(of: "m.", with: "")
    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if ["youtube.com", "music.youtube.com", "youtu.be"].contains(normalizedHost) {
        let videoId: String?
        if normalizedHost == "youtu.be" {
            videoId = path.split(separator: "/").first.map(String.init)
        } else if path.hasPrefix("shorts/") || path.hasPrefix("embed/") || path.hasPrefix("live/") {
            videoId = path.split(separator: "/").dropFirst().first.map(String.init)
        } else {
            videoId = components.queryItems?.first(where: { $0.name.lowercased() == "v" })?.value
        }
        if let videoId, !videoId.isEmpty { return "youtube:\(videoId)" }
    }
    if normalizedHost == "soundcloud.com" { return "soundcloud-url:\(path.lowercased())" }
    return input
}
