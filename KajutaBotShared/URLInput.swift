import Foundation

enum URLInput {
    static func firstURL(in input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              let url = match.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    static func favoriteRequest(for input: String) -> AddFavoriteRequest? {
        guard let url = firstURL(in: input), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = components.host?.lowercased() ?? ""
        let parts = components.path.split(separator: "/").map(String.init)
        let id: String?
        switch host {
        case "youtu.be": id = parts.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            if let first = parts.first, ["shorts", "embed", "live"].contains(first), parts.count > 1 {
                id = parts[1]
            } else {
                id = components.queryItems?.first { $0.name == "v" }?.value
            }
        default: return nil // SoundCloud URLs need server-side resolution, not a guessed ID.
        }
        guard let id, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return AddFavoriteRequest(contentType: "YouTube", contentId: id)
    }
}
