import Nuke
import NukeUI
import SwiftUI

enum ArtworkLayout: Equatable {
    case square(CGFloat)
    case aspectRatio(CGFloat)
}

enum ArtworkRequestFactory {
    static func make(urlString: String?, layout: ArtworkLayout) -> ImageRequest? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }

        var request = ImageRequest(url: url)
        request.priority = priority(for: layout)
        var thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: decodedPixelLimit(for: layout))
        thumbnail.createThumbnailWithTransform = true
        request.thumbnail = thumbnail
        return request
    }

    private static func priority(for layout: ArtworkLayout) -> ImageRequest.Priority {
        switch layout {
        case .square: .normal
        case .aspectRatio: .high
        }
    }

    private static func decodedPixelLimit(for layout: ArtworkLayout) -> Float {
        switch layout {
        case let .square(side):
            return Float(max(CGFloat(96), ceil(side * 3)))
        case .aspectRatio:
            return 1_536
        }
    }
}

enum ArtworkPreloader {
    @discardableResult
    static func preloadHero(urlString: String?) async -> Bool {
        guard let request = ArtworkRequestFactory.make(
            urlString: urlString,
            layout: .aspectRatio(16 / 9)
        ) else { return true }

        do {
            _ = try await ImagePipeline.shared.imageTask(with: request).image
            return true
        } catch {
            // A failed image request should not hold the app on the launch screen.
            // ArtworkView will render its normal fallback once the player appears.
            return true
        }
    }
}

struct ArtworkView: View {
    let urlString: String?
    let layout: ArtworkLayout
    var cornerRadius: CGFloat = 14
    var onLoadCompleted: (() -> Void)? = nil

    var body: some View {
        let request = ArtworkRequestFactory.make(urlString: urlString, layout: layout)

        switch layout {
        case let .square(side):
            artworkContent(request: request)
                .frame(width: side, height: side)
                .clipped()
                .clipShape(shape)

        case let .aspectRatio(ratio):
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    artworkContent(request: request)
                }
                .clipped()
                .clipShape(shape)
        }
    }

    private func artworkContent(request: ImageRequest?) -> some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)

            if let request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                            .onAppear { onLoadCompleted?() }
                    } else if state.error != nil {
                        missing
                            .onAppear { onLoadCompleted?() }
                    } else {
                        // Keep scrolling cheap: dozens of animated ProgressViews in image
                        // cells cost more than a neutral placeholder and add no information.
                        Color(uiColor: .tertiarySystemFill)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: urlString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                missing
                    .onAppear { onLoadCompleted?() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }


    private var missing: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BrandMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "music.note.list")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}
