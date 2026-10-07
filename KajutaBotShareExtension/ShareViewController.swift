import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareResultView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try await self.sharedURL() else { throw ShareFailure.invalidLink }
                try Task.checkCancellation()
                try await self.model.submit(url)
            } catch is CancellationError { return } catch {
                self.model.message = self.model.text(pl: "Nie udało się dodać linku. Sprawdź kolejkę przed ponowną próbą.",
                                                    en: "Couldn't add the link. Check the queue before trying again.")
                self.model.isLoading = false
            }
        }
    }

    deinit { task?.cancel() }

    private func sharedURL() async throws -> URL? {
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            for provider in item.attachments ?? [] {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    let value = try await provider.shareItem(type)
                    if let url = value as? URL, let valid = URLInput.firstURL(in: url.absoluteString) { return valid }
                    if let text = value as? String, let url = URLInput.firstURL(in: text) { return url }
                }
            }
            if let text = item.attributedContentText?.string, let url = URLInput.firstURL(in: text) { return url }
        }
        return nil
    }
}

private enum ShareFailure: Error { case invalidLink, invalidResponse, rejected }

@MainActor
@Observable
private final class ShareModel {
    var isLoading = true
    var succeeded = false
    var tracks: [PlaybackTrackResponse] = []
    var message = ""
    let artworkLoader = ShareArtworkLoader()

    func text(pl: String, en: String) -> String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") == true ? pl : en
    }

    func submit(_ url: URL) async throws {
        let inbox = try SharedLinkInbox.appGroup()
        var receipt = try inbox.insert(url: url)
        // The app owns refresh-token rotation across both processes. An extension
        // must never overwrite a newer account/session while the app is refreshing.
        let store = KeychainSessionStore()
        let session = try store.load()
        let defaults = UserDefaults(suiteName: "group.com.tryniecki.KajutaBot")
        guard let session, let expiry = Self.expiry(session.accessTokenExpiresAtUtc),
              expiry.timeIntervalSinceNow > 60,
              let guild = defaults?.string(forKey: "selection.guildId"),
              let channel = defaults?.string(forKey: "selection.voiceChannelId") else {
            deferred()
            return
        }
        let rawBase = Bundle.main.object(forInfoDictionaryKey: "KAJUTABOT_API_BASE_URL") as? String
        let base = URL(string: rawBase ?? "") ?? URL(string: "https://api.kajuta.tryniecki.eu")!
        let snapshot: QueueSnapshotResponse
        do {
            snapshot = try await send(base: base, path: "guilds/\(guild)/queue", token: session.accessToken)
        } catch {
            deferred()
            return
        }
        guard try store.load()?.accessToken == session.accessToken else { deferred(); return }
        receipt = try inbox.claim(receipt)
        do {
            let result: QueueSnapshotResponse = try await send(base: base, path: "guilds/\(guild)/queue/items",
                token: session.accessToken,
                body: JSONEncoder().encode(EnqueueRequest(voiceChannelId: channel, inputs: [url.absoluteString],
                                                          expectedQueueVersion: snapshot.queueVersion)))
            tracks = result.addedTracks ?? []
            succeeded = true
            message = text(pl: "Dodano do kolejki", en: "Added to queue")
            do { try inbox.remove(receipt) }
            catch {
                message = text(pl: "Dodano do kolejki. Nie udało się usunąć zapisanego linku; możesz go usunąć w KajutaBot.",
                               en: "Added to queue. The saved link could not be removed; you can discard it in KajutaBot.")
            }
        } catch {
            // A lost response may hide a committed POST. Leave an unknown receipt;
            // the app presents it for review and never automatically resubmits.
            message = text(pl: "Wynik nie został potwierdzony. Otwórz KajutaBot i sprawdź kolejkę.",
                           en: "The result wasn't confirmed. Open KajutaBot and check the queue.")
        }
        isLoading = false
    }

    private func deferred() {
        message = text(pl: "Link zapisany. Otwórz KajutaBot, zaloguj się i wybierz kanał, aby go dodać.",
                       en: "Link saved. Open KajutaBot, sign in and select a channel to add it.")
        isLoading = false
    }

    private static func expiry(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func send(base: URL, path: String, token: String, body: Data? = nil) async throws -> QueueSnapshotResponse {
        var request = URLRequest(url: base.appending(path: "api/v1/app").appending(path: path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareFailure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ShareFailure.rejected }
        return try JSONDecoder().decode(QueueSnapshotResponse.self, from: data)
    }
}

private struct ShareResultView: View {
    let model: ShareModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    SharedQueueLoadingView(message: model.text(pl: "Dodawanie do kolejki…", en: "Adding to queue…"))
                } else if model.succeeded {
                    SharedQueueResultView(tracks: model.tracks, message: model.message,
                        tracksTitle: model.text(pl: "Dodane utwory", en: "Added tracks")) { track, hero in
                        ShareArtworkView(urlString: track.artworkUrl, hero: hero, loader: model.artworkLoader)
                    }
                } else {
                    ContentUnavailableView {
                        Label("KajutaBot", systemImage: "info.circle")
                    } description: { Text(model.message) }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("KajutaBot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.text(pl: "Gotowe", en: "Done"), action: done).disabled(model.isLoading)
                }
            }
        }
    }
}

private extension NSItemProvider {
    func shareItem(_ type: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item as? NSSecureCoding) }
            }
        }
    }
}
