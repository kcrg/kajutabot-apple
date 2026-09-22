import NukeUI
import SwiftUI

enum ArtworkLayout: Equatable {
    case square(CGFloat)
    case aspectRatio(CGFloat)
}

struct ArtworkView: View {
    let urlString: String?
    let layout: ArtworkLayout
    var cornerRadius: CGFloat = 14

    var body: some View {
        switch layout {
        case let .square(side):
            artworkContent
                .frame(width: side, height: side)
                .clipped()
                .clipShape(shape)

        case let .aspectRatio(ratio):
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    artworkContent
                }
                .clipped()
                .clipShape(shape)
        }
    }

    private var artworkContent: some View {
        ZStack {
            Color.secondary.opacity(0.08)

            if let url = validURL {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if state.error != nil {
                        missing
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                missing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var validURL: URL? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    private var missing: some View {
        ZStack {
            Color.secondary.opacity(0.08)
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
