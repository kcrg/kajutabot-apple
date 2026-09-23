import Foundation

actor SessionManager {
    private let store: KeychainSessionStore
    private let authAPI: AuthAPIClient
    private var session: UserSession?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<UserSession, Error>?

    init(store: KeychainSessionStore, authAPI: AuthAPIClient) {
        self.store = store
        self.authAPI = authAPI
    }

    func restore() throws -> UserSession? {
        let stored = try store.load()
        session = stored
        accessTokenExpiry = stored.flatMap { parseISO8601($0.accessTokenExpiresAtUtc) }
        return stored
    }

    func signInAsGuest() async throws -> UserSession {
        let response = try await authAPI.guest()
        let newSession = response.userSession
        guard newSession.sessionType == .guest else { throw APIError.invalidResponse }
        try commit(newSession)
        return newSession
    }

    func exchangeDiscord(_ request: DiscordOAuthExchangeRequest) async throws -> UserSession {
        let response = try await authAPI.exchange(request)
        let newSession = response.userSession
        try commit(newSession)
        return newSession
    }

    func accessToken(forceRefreshIfMatching failedToken: String? = nil) async throws -> String {
        guard let current = session else { throw SessionError.signedOut }
        if let failedToken, current.accessToken != failedToken { return current.accessToken }
        if failedToken == nil, !isExpiringSoon { return current.accessToken }

        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { [authAPI] in
            if current.sessionType == .guest {
                return try await authAPI.guest().userSession
            }
            guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else { throw SessionError.signedOut }
            return try await authAPI.refresh(refreshToken).userSession
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            try commit(refreshed)
            return refreshed.accessToken
        } catch let error as APIError where error.statusCode == 401 {
            try? clear()
            throw SessionError.signedOut
        }
    }

    func clear() throws {
        try store.clear()
        session = nil
        accessTokenExpiry = nil
        refreshTask?.cancel()
        refreshTask = nil
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
            accessToken: accessToken,
            accessTokenExpiresAtUtc: accessTokenExpiresAtUtc,
            refreshToken: refreshToken,
            refreshTokenExpiresAtUtc: refreshTokenExpiresAtUtc,
            user: user,
            sessionType: sessionType
        )
    }
}
