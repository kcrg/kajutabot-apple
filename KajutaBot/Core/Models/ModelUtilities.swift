import Foundation

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let kajutaBot: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let kajutaBotWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

func parseISO8601(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return ISO8601DateFormatter.kajutaBot.date(from: raw)
        ?? ISO8601DateFormatter.kajutaBotWithoutFraction.date(from: raw)
}

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

func playbackPosition(
    startedAt: Date?,
    durationMilliseconds: Int64,
    now: Date = .now
) -> TimeInterval? {
    guard durationMilliseconds > 0, let startedAt else { return nil }
    return min(max(now.timeIntervalSince(startedAt), 0), Double(durationMilliseconds) / 1_000)
}

func playbackPosition(queue: QueueSnapshotResponse, now: Date = .now) -> TimeInterval? {
    guard let track = queue.nowPlaying else { return nil }
    return playbackPosition(
        startedAt: parseISO8601(queue.nowPlayingStartedAt),
        durationMilliseconds: track.durationMilliseconds,
        now: now
    )
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

private let youtubeVideoIDCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))

func favoriteArtworkURL(_ favorite: FavoriteResponse) -> URL? {
    if let url = ArtworkURLResolver.resolve(favorite.thumbnailUrl) {
        return url
    }
    let identity = favoriteIdentity(favorite.contentUrl)
    guard identity.hasPrefix("youtube:") else { return nil }
    let videoId = String(identity.dropFirst("youtube:".count))
    guard videoId.count == 11, videoId.unicodeScalars.allSatisfy(youtubeVideoIDCharacters.contains) else { return nil }
    return URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
}

