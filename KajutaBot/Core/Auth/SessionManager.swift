import Foundation

actor SessionManager {
    private let store: any SessionStoring
    private let authAPI: any AuthSessionAPI
    private var session: UserSession?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<UserSession, Error>?
    private var refreshID: UUID?
    private(set) var identity = UUID()

    init(store: any SessionStoring, authAPI: any AuthSessionAPI) {
        self.store = store
        self.authAPI = authAPI
    }

    func validate(identity expected: UUID) throws {
        guard identity == expected, session != nil else { throw CancellationError() }
    }

    func restore() throws -> UserSession? {
        let stored = try store.load()
        invalidatePendingWork()
        session = stored
        accessTokenExpiry = stored.flatMap { parseISO8601($0.accessTokenExpiresAtUtc) }
        return stored
    }

    func signInAsGuest() async throws -> UserSession {
        let epoch = identity
        let response = try await authAPI.guest()
        guard identity == epoch else { throw CancellationError() }
        guard response.sessionType == .guest else { throw APIError.invalidResponse }
        try commit(response.userSession)
        invalidatePendingWork()
        return response.userSession
    }

    func exchangeDiscord(_ request: DiscordOAuthExchangeRequest) async throws -> UserSession {
        let epoch = identity
        let response = try await authAPI.exchange(request)
        guard identity == epoch else { throw CancellationError() }
        guard response.sessionType == .discord else { throw APIError.invalidResponse }
        try commit(response.userSession)
        invalidatePendingWork()
        return response.userSession
    }

    func accessToken(forceRefreshIfMatching failedToken: String? = nil) async throws -> String {
        guard let current = session else { throw SessionError.signedOut }
        if let failedToken, current.accessToken != failedToken { return current.accessToken }
        if failedToken == nil, !isExpiringSoon { return current.accessToken }
        let epoch = identity
        let id: UUID
        let task: Task<UserSession, Error>
        if let existing = refreshTask, let existingID = refreshID {
            task = existing
            id = existingID
        } else {
            id = UUID()
            task = Task { [authAPI] in
                if current.sessionType == .guest { return try await authAPI.guest().userSession }
                guard let token = current.refreshToken, !token.isEmpty else { throw SessionError.signedOut }
                return try await authAPI.refresh(token).userSession
            }
            refreshTask = task
            refreshID = id
        }
        defer {
            if refreshID == id { refreshTask = nil; refreshID = nil }
        }
        do {
            let refreshed = try await task.value
            try validate(identity: epoch)
            guard refreshed.sessionType == current.sessionType,
                  current.sessionType == .guest || refreshed.user.discordUserId == current.user.discordUserId else {
                throw APIError.invalidResponse
            }
            if session?.accessToken == current.accessToken { try commit(refreshed) }
            return refreshed.accessToken
        } catch let error as APIError where error.statusCode == 401 {
            guard identity == epoch else { throw CancellationError() }
            try clear()
            throw SessionError.signedOut
        } catch {
            guard identity == epoch else { throw CancellationError() }
            throw error
        }
    }

    func clear() throws {
        try store.clear()
        invalidatePendingWork()
        session = nil
        accessTokenExpiry = nil
    }

    private func invalidatePendingWork() {
        identity = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
    }

    private func commit(_ value: UserSession) throws {
        try store.save(value)
        session = value
        accessTokenExpiry = parseISO8601(value.accessTokenExpiresAtUtc)
    }

    private var isExpiringSoon: Bool {
        guard let accessTokenExpiry else { return true }
        return accessTokenExpiry.timeIntervalSinceNow < 60
    }
}

enum SessionError: LocalizedError {
    case signedOut
    var errorDescription: String? { String(localized: .sessionExpired) }
}

private extension AuthSessionResponse {
    var userSession: UserSession {
        UserSession(
            accessToken: accessToken, accessTokenExpiresAtUtc: accessTokenExpiresAtUtc,
            refreshToken: refreshToken, refreshTokenExpiresAtUtc: refreshTokenExpiresAtUtc,
            user: user, sessionType: sessionType
        )
    }
}
