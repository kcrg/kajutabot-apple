import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidResponse
    case http(status: Int, problem: ProblemDetails?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Nieprawidłowa odpowiedź serwera."
        case let .http(status, problem): problem?.detail ?? problem?.title ?? "Błąd serwera (HTTP \(status))."
        case let .decoding(error): "Nie można odczytać odpowiedzi serwera: \(error.localizedDescription)"
        }
    }

    var statusCode: Int? {
        guard case let .http(status, _) = self else { return nil }
        return status
    }

    var problem: ProblemDetails? {
        guard case let .http(_, problem) = self else { return nil }
        return problem
    }
}

struct AuthAPIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func guest() async throws -> AuthSessionResponse {
        try await send(path: "auth/guest", body: Optional<EmptyBody>.none)
    }

    func exchange(_ request: DiscordOAuthExchangeRequest) async throws -> AuthSessionResponse {
        try await send(path: "auth/discord/exchange", body: request)
    }

    func refresh(_ refreshToken: String) async throws -> AuthSessionResponse {
        try await send(path: "auth/refresh", body: RefreshUserSessionRequest(refreshToken: refreshToken))
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, body: Body?) async throws -> Response {
        var request = URLRequest(url: apiURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await decodeResponse(request)
    }

    private func apiURL(_ path: String) -> URL {
        baseURL.appending(path: "api/v1").appending(path: path)
    }

    private func decodeResponse<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, problem: try? JSONDecoder().decode(ProblemDetails.self, from: data))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}

private struct EmptyBody: Codable {}
