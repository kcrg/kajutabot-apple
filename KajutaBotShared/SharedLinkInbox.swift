import Foundation

struct PendingSharedLink: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case ready, outcomeUnknown }
    let id: UUID
    let url: String
    let createdAt: Date
    var status: Status
}

/// Immutable UUID names avoid overwriting unrelated shares from another process.
/// No tokens are stored here. Claim BEFORE POST and never replay an unknown outcome.
struct SharedLinkInbox: Sendable {
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    static func appGroup() throws -> SharedLinkInbox {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.tryniecki.KajutaBot"
        ) else { throw CocoaError(.fileNoSuchFile) }
        return SharedLinkInbox(directory: container.appending(path: "SharedLinks", directoryHint: .isDirectory))
    }

    func insert(url: URL) throws -> PendingSharedLink {
        guard URLInput.firstURL(in: url.absoluteString) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let entry = PendingSharedLink(id: UUID(), url: url.absoluteString, createdAt: .now, status: .ready)
        try save(entry)
        return entry
    }

    func entries(now: Date = .now) throws -> [PendingSharedLink] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let entry = try? JSONDecoder().decode(PendingSharedLink.self, from: Data(contentsOf: file)) else { return nil }
            guard file.lastPathComponent == "\(entry.id.uuidString).json",
                  URLInput.firstURL(in: entry.url) != nil else { return nil }
            guard now.timeIntervalSince(entry.createdAt) < 7 * 86_400 else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            return entry
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func claim(_ entry: PendingSharedLink) throws -> PendingSharedLink {
        var coordinationError: NSError?
        var outcome: Result<PendingSharedLink, Error>?
        NSFileCoordinator().coordinate(writingItemAt: path(for: entry), options: .forReplacing,
                                       error: &coordinationError) { file in
            outcome = Result {
                var current = try JSONDecoder().decode(PendingSharedLink.self, from: Data(contentsOf: file))
                guard current.id == entry.id, current.url == entry.url, current.status == .ready else { throw CocoaError(.fileWriteFileExists) }
                current.status = .outcomeUnknown
                try save(current)
                return current
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }

    func remove(_ entry: PendingSharedLink) throws {
        let file = path(for: entry)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func save(_ entry: PendingSharedLink) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: path(for: entry), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func path(for entry: PendingSharedLink) -> URL { directory.appending(path: "\(entry.id.uuidString).json") }
}
