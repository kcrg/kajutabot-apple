import SwiftUI

/// The app and Share Extension use the same result layout, with their own image loaders.
struct SharedQueueResultView<Artwork: View>: View {
    let tracks: [PlaybackTrackResponse]
    let message: String
    let tracksTitle: String
    @ViewBuilder let artwork: (PlaybackTrackResponse, Bool) -> Artwork

    var body: some View {
        if tracks.count > 1 {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "checkmark.circle.fill").font(.headline)
                    Text(verbatim: "\(tracksTitle) · \(tracks.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    // A playlist may contain the same content more than once.
                    ForEach(tracks.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            artwork(tracks[index], false)
                            Text(tracks[index].title).frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: "\(index + 1)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        } else {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        if let track = tracks.first {
                            artwork(track, true).frame(maxWidth: 320)
                            Text(track.title).font(.title2.bold()).multilineTextAlignment(.center)
                        }
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
    }
}

struct SharedQueueLoadingView: View {
    let message: String
    @State private var showsSpinner = false

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
                .frame(width: 48, height: 48)
                .opacity(showsSpinner ? 1 : 0)
                .accessibilityHidden(true)
            Text(message).font(.headline).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(100))
                showsSpinner = true
            } catch { /* The result arrived before the spinner was needed. */ }
        }
    }
}
