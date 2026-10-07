import Foundation

private enum ISO8601Parsing {
    // Value types with Sendable conformance, shared by UI, session actors and the extension.
    static let fractional = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true)
    static let wholeSeconds = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: false)
}

func parseISO8601(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return (try? ISO8601Parsing.fractional.parse(raw))
        ?? (try? ISO8601Parsing.wholeSeconds.parse(raw))
}
