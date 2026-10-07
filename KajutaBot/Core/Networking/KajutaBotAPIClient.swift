import Foundation

struct KajutaBotAPIClient: KajutaBotAPI {
    let baseURL: URL
    let sessionManager: SessionManager
    private let urlSession: URLSession

    init(baseURL: URL, sessionManager: SessionManager, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.sessionManager = sessionManager
        self.urlSession = urlSession
    }

    func logout() async throws { try await sendVoid(method: "POST", path: "auth/logout") }
    func getMyGuilds() async throws -> [DiscordGuildResponse] { try await send(method: "GET", path: "users/me/guilds") }

    func getVoiceChannels(guildId: String) async throws -> [DiscordVoiceChannelResponse] {
        try await send(method: "GET", path: "discord/guilds/\(guildId)/voice-channels")
    }

    func getQueue(guildId: String) async throws -> QueueSnapshotResponse {
        try await send(method: "GET", path: "guilds/\(guildId)/queue")
    }

    func enqueue(guildId: String, request body: EnqueueRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "POST", path: "guilds/\(guildId)/queue/items", body: body)
    }

    func removeQueueEntry(guildId: String, entryId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/queue/items/\(entryId)",
            query: expectedQueueVersion.map { [URLQueryItem(name: "expectedQueueVersion", value: String($0))] } ?? []
        )
    }

    func moveQueueEntry(guildId: String, entryId: String, request body: MoveQueueEntryRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "PUT", path: "guilds/\(guildId)/queue/items/\(entryId)/position", body: body)
    }

    func swapQueueEntries(guildId: String, request body: SwapQueueEntriesRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "POST", path: "guilds/\(guildId)/queue/items/swap", body: body)
    }

    func clearPendingQueue(guildId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/queue/items",
            query: expectedQueueVersion.map { [URLQueryItem(name: "expectedQueueVersion", value: String($0))] } ?? []
        )
    }

    func skip(guildId: String, request body: SkipQueueRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "POST", path: "guilds/\(guildId)/queue/skip", body: body)
    }

    func setRepeat(guildId: String, request body: SetQueueRepeatRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "PUT", path: "guilds/\(guildId)/queue/repeat", body: body)
    }

    func stop(guildId: String, request body: QueueMutationRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "POST", path: "guilds/\(guildId)/queue/stop", body: body)
    }

    func enableRadio(guildId: String, request body: EnableRadioRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "PUT", path: "guilds/\(guildId)/radio", body: body)
    }

    func disableRadio(guildId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/radio",
            query: expectedQueueVersion.map { [URLQueryItem(name: "expectedQueueVersion", value: String($0))] } ?? []
        )
    }

    func search(query: String, source: SearchSourceOption, maxResults: Int = 20) async throws -> SearchResponse {
        try await send(
            method: "GET",
            path: "search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "source", value: source.rawValue),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
            ]
        )
    }

    func getFavorites() async throws -> [FavoriteResponse] {
        try await send(method: "GET", path: "users/me/favorites")
    }

    func addFavorite(_ body: AddFavoriteRequest) async throws -> FavoriteResponse {
        try await send(method: "POST", path: "users/me/favorites", body: body)
    }

    func deleteFavorite(contentURL: String) async throws {
        try await sendVoid(method: "DELETE", path: "users/me/favorites", query: [URLQueryItem(name: "contentUrl", value: contentURL)])
    }

    func queueFavorites(_ body: QueueFavoritesRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "POST", path: "users/me/favorites/queue", body: body)
    }

    private func send<T: Decodable>(method: String, path: String, query: [URLQueryItem] = []) async throws -> T {
        try await perform(method: method, path: path, query: query, body: nil)
    }

    private func send<T: Decodable, Body: Encodable>(method: String, path: String, query: [URLQueryItem] = [], body: Body) async throws -> T {
        try await perform(method: method, path: path, query: query, body: try JSONEncoder().encode(body))
    }

    private func sendVoid(method: String, path: String, query: [URLQueryItem] = []) async throws {
        _ = try await performRaw(method: method, path: path, query: query, body: nil)
    }

    private func perform<T: Decodable>(method: String, path: String, query: [URLQueryItem], body: Data?) async throws -> T {
        let (data, _) = try await performRaw(method: method, path: path, query: query, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func performRaw(method: String, path: String, query: [URLQueryItem], body: Data?) async throws -> (Data, HTTPURLResponse) {
        let identity = await sessionManager.identity
        let token = try await sessionManager.accessToken()
        try await sessionManager.validate(identity: identity)
        do {
            let result = try await execute(method: method, path: path, query: query, body: body, accessToken: token)
            try await sessionManager.validate(identity: identity)
            return result
        } catch let error as APIError where error.statusCode == 401 {
            try await sessionManager.validate(identity: identity)
            let refreshed = try await sessionManager.accessToken(forceRefreshIfMatching: token)
            try await sessionManager.validate(identity: identity)
            let result = try await execute(method: method, path: path, query: query, body: body, accessToken: refreshed)
            try await sessionManager.validate(identity: identity)
            return result
        }
    }

    private func execute(method: String, path: String, query: [URLQueryItem], body: Data?, accessToken: String) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/app").appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let problem = try? JSONDecoder().decode(ProblemDetails.self, from: data)
            throw APIError.http(status: http.statusCode, problem: problem)
        }
        return (data, http)
    }
}
