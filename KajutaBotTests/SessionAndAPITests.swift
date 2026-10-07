import Foundation
import Testing
@testable import KajutaBot

private enum StubFailure: Error { case unexpectedCall }

private final class MemorySessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UserSession?
    init(_ value: UserSession?) { self.value = value }
    func load() throws -> UserSession? { lock.withLock { value } }
    func save(_ value: UserSession) throws { lock.withLock { self.value = value } }
    func clear() throws { lock.withLock { value = nil } }
}

private func sessionFixture(expired: Bool = true) -> UserSession {
    UserSession(accessToken: "old", accessTokenExpiresAtUtc: expired ? "2000-01-01T00:00:00Z" : "2100-01-01T00:00:00Z",
        refreshToken: "refresh", refreshTokenExpiresAtUtc: "2100-01-01T00:00:00Z",
        user: AuthUserResponse(discordUserId: "user", username: "name", displayName: "Name", avatarUrl: nil),
        sessionType: .discord)
}

private actor ControlledAuth: AuthSessionAPI {
    private var continuation: CheckedContinuation<AuthSessionResponse, Never>?
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var refreshCount = 0
    func guest() async throws -> AuthSessionResponse { throw StubFailure.unexpectedCall }
    func exchange(_ request: DiscordOAuthExchangeRequest) async throws -> AuthSessionResponse { throw StubFailure.unexpectedCall }
    func refresh(_ refreshToken: String) async throws -> AuthSessionResponse {
        refreshCount += 1
        entered = true
        observers.forEach { $0.resume() }
        observers = []
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func finish() throws {
        let data = Data(#"{"accessToken":"new","accessTokenExpiresAtUtc":"2100-01-01T00:00:00Z","refreshToken":"next","refreshTokenExpiresAtUtc":"2100-01-01T00:00:00Z","user":{"discordUserId":"user","username":"name","displayName":"Name","avatarUrl":null},"sessionType":"discord"}"#.utf8)
        continuation?.resume(returning: try JSONDecoder().decode(AuthSessionResponse.self, from: data))
        continuation = nil
    }
}

struct SessionIsolationTests {
    @Test("Współbieżne żądania współdzielą jedno odświeżenie tokena")
    func oneRefresh() async throws {
        let api = ControlledAuth()
        let store = MemorySessionStore(sessionFixture())
        let manager = SessionManager(store: store, authAPI: api)
        _ = try await manager.restore()
        let first = Task { try await manager.accessToken() }
        await api.waitUntilEntered()
        let second = Task { try await manager.accessToken() }
        try await api.finish()
        #expect(try await first.value == "new")
        #expect(try await second.value == "new")
        #expect(await api.refreshCount == 1)
        #expect(try store.load()?.refreshToken == "next")
    }

    @Test("Wynik refresh po logout nie odtwarza wpisu w Keychain")
    func logoutDuringRefresh() async throws {
        let api = ControlledAuth()
        let store = MemorySessionStore(sessionFixture())
        let manager = SessionManager(store: store, authAPI: api)
        _ = try await manager.restore()
        let task = Task { try await manager.accessToken() }
        await api.waitUntilEntered()
        try await manager.clear()
        try await api.finish()
        do { _ = try await task.value; Issue.record("Refresh must not restore the signed-out session") }
        catch { #expect(error is CancellationError) }
        #expect(try store.load() == nil)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    func snapshot() -> [URLRequest] { lock.withLock { requests } }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixture: (@Sendable (URLRequest) -> Data)?
    static func configure(_ handler: (@Sendable (URLRequest) -> Data)?) { lock.withLock { fixture = handler } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.lock.withLock { Self.fixture }
        guard let data = handler?(request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: StubFailure.unexpectedCall)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct HTTPContractTests {
    @Test("Wszystkie mutacje i query DELETE wysyłają expectedQueueVersion")
    func queueRequests() async throws {
        let auth = ControlledAuth()
        let manager = SessionManager(store: MemorySessionStore(sessionFixture(expired: false)), authAPI: auth)
        _ = try await manager.restore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); FixtureURLProtocol.configure(nil) }
        let recorder = RequestRecorder()
        let data = try JSONEncoder().encode(queueFixture(version: 20, queueVersion: 7))
        FixtureURLProtocol.configure { request in recorder.append(request); return data }
        let api = KajutaBotAPIClient(baseURL: try #require(URL(string: "https://fixture.invalid")), sessionManager: manager, urlSession: session)
        _ = try await api.enqueue(guildId: "guild", request: EnqueueRequest(voiceChannelId: "channel", inputs: ["url"], expectedQueueVersion: 7))
        _ = try await api.moveQueueEntry(guildId: "guild", entryId: "entry", request: MoveQueueEntryRequest(newPosition: 2, expectedQueueVersion: 7))
        _ = try await api.swapQueueEntries(guildId: "guild", request: SwapQueueEntriesRequest(firstEntryId: "a", secondEntryId: "b", expectedQueueVersion: 7))
        _ = try await api.skip(guildId: "guild", request: SkipQueueRequest(skipToPosition: nil, expectedQueueVersion: 7))
        _ = try await api.stop(guildId: "guild", request: QueueMutationRequest(expectedQueueVersion: 7))
        _ = try await api.setRepeat(guildId: "guild", request: SetQueueRepeatRequest(isEnabled: true, expectedQueueVersion: 7))
        _ = try await api.enableRadio(guildId: "guild", request: EnableRadioRequest(voiceChannelId: "channel", minimumDurationSeconds: 60, maximumDurationSeconds: 600, expectedQueueVersion: 7))
        _ = try await api.queueFavorites(QueueFavoritesRequest(guildId: "guild", voiceChannelId: "channel", expectedQueueVersion: 7, shuffle: true))
        _ = try await api.removeQueueEntry(guildId: "guild", entryId: "entry", expectedQueueVersion: 7)
        _ = try await api.clearPendingQueue(guildId: "guild", expectedQueueVersion: 7)
        _ = try await api.disableRadio(guildId: "guild", expectedQueueVersion: 7)
        let requests = recorder.snapshot()
        #expect(requests.count == 11)
        #expect(requests.contains { $0.url?.path == "/api/v1/app/guilds/guild/queue/items/swap" })
        for request in requests {
            if request.httpMethod == "DELETE" {
                let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
                #expect(items?.contains { $0.name == "expectedQueueVersion" && $0.value == "7" } == true)
                #expect(items?.contains { $0.name == "expectedVersion" } == false)
            } else {
                let body = try #require(request.httpBody)
                let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(payload["expectedQueueVersion"] as? Int == 7)
                #expect(payload["expectedVersion"] == nil)
            }
        }
    }
}
