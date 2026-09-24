import Foundation
import Nuke

/// Adds KajutaBot authorization only to the protected local artwork endpoint.
/// External provider artwork never receives the user's access token.
final class ArtworkImagePipelineDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    private let apiBaseURL: URL
    private let tokenProvider: @Sendable () async throws -> String

    init(
        apiBaseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.apiBaseURL = apiBaseURL
        self.tokenProvider = tokenProvider
    }

    @ImagePipelineActor
    func willLoadData(
        for request: ImageRequest,
        urlRequest: URLRequest,
        pipeline: ImagePipeline
    ) async throws -> URLRequest {
        guard let url = urlRequest.url,
              isProtectedArtworkURL(url) else {
            return urlRequest
        }

        let token = try await tokenProvider()
        guard !token.isEmpty else { return urlRequest }

        var authorized = urlRequest
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    private func isProtectedArtworkURL(_ url: URL) -> Bool {
        guard sameOrigin(url, apiBaseURL) else { return false }
        return url.path.hasPrefix("/api/v1/app/artwork/")
    }

    private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

enum ArtworkImagePipeline {
    static func make(
        apiBaseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String
    ) -> ImagePipeline {
        ImagePipeline(
            configuration: .withURLCache,
            delegate: ArtworkImagePipelineDelegate(
                apiBaseURL: apiBaseURL,
                tokenProvider: tokenProvider
            )
        )
    }
}
