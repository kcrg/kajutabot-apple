import Security
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let successConfirmationMinimumDuration: Duration = .seconds(1.5)

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        task = Task { [weak self] in
            await self?.enqueueSharedLink()
        }
    }

    deinit {
        task?.cancel()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        symbolView.image = UIImage(systemName: "music.note.list")
        symbolView.tintColor = .label
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        symbolView.contentMode = .scaleAspectFit

        titleLabel.text = localized(pl: "Dodawanie do kolejki…", en: "Adding to queue…")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [symbolView, titleLabel, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 42),
            symbolView.heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @MainActor
    private func enqueueSharedLink() async {
        do {
            guard let url = try await sharedURL() else {
                return showFailure(localized(pl: "Nie znaleziono linku.", en: "No link found."))
            }

            let client = ShareAPIClient()
            try await client.enqueue(url: url)
            showSuccess()
        } catch ShareError.notSignedIn {
            showFailure(localized(pl: "Zaloguj się przez Discord w KajutaBot.", en: "Sign in with Discord in KajutaBot."))
        } catch ShareError.noTarget {
            showFailure(localized(pl: "Najpierw wybierz serwer i kanał głosowy w KajutaBot.", en: "Choose a server and voice channel in KajutaBot first."))
        } catch {
            showFailure(localized(pl: "Nie udało się dodać do kolejki.", en: "Couldn’t add to queue."))
        }
    }

    private func sharedURL() async throws -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        return value
                    }
                    if let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? String,
                       let url = URL(string: value) {
                        return url
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let url = extractURL(from: text) {
                    return url
                }
            }
            if let text = item.attributedContentText?.string, let url = extractURL(from: text) {
                return url
            }
        }
        return nil
    }

    private func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    @MainActor
    private func showSuccess() {
        spinner.stopAnimating()
        symbolView.image = UIImage(systemName: "checkmark.circle.fill")
        symbolView.tintColor = .systemGreen
        titleLabel.text = localized(pl: "Dodano do kolejki", en: "Added to queue")
        finish(after: Self.successConfirmationMinimumDuration)
    }

    @MainActor
    private func showFailure(_ message: String) {
        spinner.stopAnimating()
        symbolView.image = UIImage(systemName: "exclamationmark.circle.fill")
        symbolView.tintColor = .systemRed
        titleLabel.text = message
        finish(after: .seconds(1.8))
    }

    @MainActor
    private func finish(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func localized(pl: String, en: String) -> String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") == true ? pl : en
    }
}

private enum ShareError: Error {
    case notSignedIn
    case noTarget
    case invalidResponse
    case http(Int)
}

private struct ShareUser: Codable {
    let discordUserId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
}

private enum ShareSessionType: String, Codable {
    case discord
    case guest
}

private struct ShareSession: Codable {
    let accessToken: String
    let accessTokenExpiresAtUtc: String
    let refreshToken: String?
    let refreshTokenExpiresAtUtc: String?
    let user: ShareUser
    let sessionType: ShareSessionType
}

private struct RefreshResponse: Codable {
    let accessToken: String
    let accessTokenExpiresAtUtc: String
    let refreshToken: String?
    let refreshTokenExpiresAtUtc: String?
    let user: ShareUser
    let sessionType: ShareSessionType
}

private struct RefreshRequest: Codable {
    let refreshToken: String
}

private struct ShareEnqueueRequest: Codable {
    let voiceChannelId: String
    let inputs: [String]
    let expectedVersion: Int64? = nil
}

private struct ShareSessionStore {
    private static let accessGroup = "group.com.tryniecki.KajutaBot"
    private static let service = "com.tryniecki.KajutaBot.session"
    private static let account = "user-session"

    func load() throws -> ShareSession? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessGroup as String: Self.accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw ShareError.notSignedIn }
        return try JSONDecoder().decode(ShareSession.self, from: data)
    }

    func save(_ session: ShareSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessGroup as String: Self.accessGroup,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ShareError.notSignedIn }
        } else if status != errSecSuccess {
            throw ShareError.notSignedIn
        }
    }
}

private struct ShareAPIClient {
    private static let appGroup = "group.com.tryniecki.KajutaBot"
    private static let guildKey = "selection.guildId"
    private static let channelKey = "selection.voiceChannelId"

    private let baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "KAJUTABOT_API_BASE_URL") as? String
        return URL(string: raw?.replacingOccurrences(of: "$(KAJUTABOT_API_BASE_URL)", with: "") ?? "")
            ?? URL(string: "https://api.kajuta.tryniecki.eu")!
    }()
    private let store = ShareSessionStore()

    func enqueue(url: URL) async throws {
        guard var session = try store.load(), session.sessionType == .discord else { throw ShareError.notSignedIn }
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let guildId = defaults.string(forKey: Self.guildKey),
              let channelId = defaults.string(forKey: Self.channelKey) else {
            throw ShareError.noTarget
        }

        if tokenNeedsRefresh(session) {
            session = try await refresh(session)
        }

        do {
            try await enqueue(url: url, guildId: guildId, channelId: channelId, accessToken: session.accessToken)
        } catch ShareError.http(401) {
            session = try await refresh(session)
            try await enqueue(url: url, guildId: guildId, channelId: channelId, accessToken: session.accessToken)
        }
    }

    private func enqueue(url: URL, guildId: String, channelId: String, accessToken: String) async throws {
        let endpoint = baseURL
            .appending(path: "api/v1/app")
            .appending(path: "guilds/\(guildId)/queue/items")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ShareEnqueueRequest(voiceChannelId: channelId, inputs: [url.absoluteString])
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ShareError.http(http.statusCode) }
    }

    private func refresh(_ session: ShareSession) async throws -> ShareSession {
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else { throw ShareError.notSignedIn }
        let endpoint = baseURL.appending(path: "api/v1/app/auth/refresh")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ShareError.http(http.statusCode) }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        let newSession = ShareSession(
            accessToken: refreshed.accessToken,
            accessTokenExpiresAtUtc: refreshed.accessTokenExpiresAtUtc,
            refreshToken: refreshed.refreshToken,
            refreshTokenExpiresAtUtc: refreshed.refreshTokenExpiresAtUtc,
            user: refreshed.user,
            sessionType: refreshed.sessionType
        )
        try store.save(newSession)
        return newSession
    }

    private func tokenNeedsRefresh(_ session: ShareSession) -> Bool {
        guard let expiry = ISO8601DateFormatter().date(from: session.accessTokenExpiresAtUtc) else { return true }
        return expiry.timeIntervalSinceNow < 60
    }
}

private extension NSItemProvider {
    func loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item as? NSSecureCoding)
                }
            }
        }
    }
}
