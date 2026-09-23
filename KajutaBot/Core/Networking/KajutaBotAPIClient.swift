import Foundation

struct KajutaBotAPIClient: Sendable {
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

    func removeQueueEntry(guildId: String, entryId: String, expectedVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/queue/items/\(entryId)",
            query: expectedVersion.map { [URLQueryItem(name: "expectedVersion", value: String($0))] } ?? []
        )
    }

    func moveQueueEntry(guildId: String, entryId: String, request body: MoveQueueEntryRequest) async throws -> QueueSnapshotResponse {
        try await send(method: "PUT", path: "guilds/\(guildId)/queue/items/\(entryId)/position", body: body)
    }

    func clearPendingQueue(guildId: String, expectedVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/queue/items",
            query: expectedVersion.map { [URLQueryItem(name: "expectedVersion", value: String($0))] } ?? []
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

    func disableRadio(guildId: String, expectedVersion: Int64?) async throws -> QueueSnapshotResponse {
        try await send(
            method: "DELETE",
            path: "guilds/\(guildId)/radio",
            query: expectedVersion.map { [URLQueryItem(name: "expectedVersion", value: String($0))] } ?? []
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
        let token = try await sessionManager.accessToken()
        do {
            return try await execute(method: method, path: path, query: query, body: body, accessToken: token)
        } catch let error as APIError where error.statusCode == 401 {
            let refreshed = try await sessionManager.accessToken(forceRefreshIfMatching: token)
            return try await execute(method: method, path: path, query: query, body: body, accessToken: refreshed)
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
