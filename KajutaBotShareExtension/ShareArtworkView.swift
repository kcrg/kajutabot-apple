import ImageIO
import SwiftUI
import UIKit

struct ShareArtworkView: View {
    let urlString: String?
    let hero: Bool
    let loader: ShareArtworkLoader
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(hero ? 16 / 9 : 1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: hero ? nil : 64, height: hero ? nil : 64)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: hero ? 20 : 12))
            .accessibilityHidden(true)
            .task(id: urlString) {
                image = nil
                let loaded = await loader.image(urlString: urlString, maxPixelSize: hero ? 960 : 192)
                guard !Task.isCancelled else { return }
                image = loaded
            }
            .onDisappear { image = nil }
    }
}

/// Keep image decoding off the main actor and inside the extension's smaller memory budget.
actor ShareArtworkLoader {
    private let cache: NSCache<NSString, UIImage>
    private let baseURL: URL
    private let session: URLSession

    init() {
        let imageCache = NSCache<NSString, UIImage>()
        imageCache.totalCostLimit = 8 * 1_024 * 1_024
        imageCache.countLimit = 30
        cache = imageCache
        let rawBase = Bundle.main.object(forInfoDictionaryKey: "KAJUTABOT_API_BASE_URL") as? String
        let base = URL(string: rawBase ?? "") ?? URL(string: "https://api.kajuta.tryniecki.eu")!
        baseURL = base
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration,
                             delegate: ShareArtworkRedirectDelegate(baseURL: base), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func image(urlString: String?, maxPixelSize: Int) async -> UIImage? {
        guard let url = resolve(urlString) else { return nil }
        let key = "\(maxPixelSize):\(url.absoluteString)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        var request = URLRequest(url: url)
        if ShareArtworkRedirectDelegate.isProtected(url, baseURL: baseURL) {
            guard let session = try? KeychainSessionStore().load() else { return nil }
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            // Download to disk rather than keeping the full compressed image in memory.
            let (file, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 8 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithURL(file as CFURL,
                      [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { return nil }
            let image = UIImage(cgImage: thumbnail)
            cache.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
            return image
        } catch {
            return nil
        }
    }

    private func resolve(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let url: URL?
        if value.hasPrefix("//") {
            url = URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        } else if value.hasPrefix("/") {
            url = URL(string: value, relativeTo: baseURL)?.absoluteURL
        } else {
            url = URL(string: value)
        }
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

private final class ShareArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let baseURL: URL

    init(baseURL: URL) { self.baseURL = baseURL }

    static func isProtected(_ url: URL, baseURL: URL) -> Bool {
        url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && effectivePort(url) == effectivePort(baseURL)
            && url.path.hasPrefix("/api/v1/app/artwork/")
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        var redirected = request
        if let url = request.url, !Self.isProtected(url, baseURL: baseURL) {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}
