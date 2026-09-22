import SwiftUI

struct MiniPlayerView: View {
    @Bindable var app: AppState
    let openPlayer: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let track = app.nowPlaying, let queue = app.queue {
            let progressQueue = app.presentationQueue ?? queue

            if placement == .inline {
                inlinePlayer(track: track)
            } else {
                expandedPlayer(track: track, queue: progressQueue)
            }
        }
    }

    private func inlinePlayer(track: TrackResponse) -> some View {
        HStack(spacing: 8) {
            ArtworkView(urlString: track.thumbnailUrl, layout: .square(30), cornerRadius: 6)

            Text(track.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                app.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(app.isMutating)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openPlayer)
    }

    private func expandedPlayer(track: TrackResponse, queue: QueueSnapshotResponse) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ArtworkView(urlString: track.thumbnailUrl, layout: .square(48), cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let position = playbackPosition(queue: queue, now: context.date) ?? 0
                        Text("\(formatDuration(Int64(position * 1_000))) / \(formatDuration(track.durationMilliseconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    app.toggleFavorite(track)
                } label: {
                    Image(systemName: app.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button {
                    app.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(app.isMutating)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openPlayer)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let position = playbackPosition(queue: queue, now: context.date) ?? 0
                let duration = max(Double(track.durationMilliseconds) / 1_000, 1)
                ProgressView(value: position, total: duration)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
