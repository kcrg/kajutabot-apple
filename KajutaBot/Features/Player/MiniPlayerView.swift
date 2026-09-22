import SwiftUI

struct MiniPlayerView: View {
    @Bindable var app: AppState
    let openPlayer: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let track = app.nowPlaying, let queue = app.queue {
            let progressQueue = app.presentationQueue ?? queue

            switch placement {
            case .inline:
                inlinePlayer(track: track)
            case .expanded, .none:
                expandedPlayer(track: track, queue: progressQueue)
            @unknown default:
                expandedPlayer(track: track, queue: progressQueue)
            }
        }
    }

    private func inlinePlayer(track: TrackResponse) -> some View {
        HStack(spacing: 7) {
            ArtworkView(
                urlString: track.thumbnailUrl,
                layout: .square(24),
                cornerRadius: 6
            )
            .fixedSize()
            .accessibilityHidden(true)

            Text(track.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 2)

            Button {
                app.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(app.isMutating)
            .accessibilityLabel("Pomiń utwór")
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: openPlayer)
    }

    private func expandedPlayer(track: TrackResponse, queue: QueueSnapshotResponse) -> some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 10) {
                ArtworkView(
                    urlString: track.thumbnailUrl,
                    layout: .square(42),
                    cornerRadius: 9
                )
                .fixedSize()
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let position = playbackPosition(queue: queue, now: context.date) ?? 0
                        Text("\(formatDuration(Int64(position * 1_000))) / \(formatDuration(track.durationMilliseconds))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Button {
                    app.toggleFavorite(track)
                } label: {
                    Image(systemName: app.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(app.isMutatingFavorites)
                .accessibilityLabel(app.isFavorite(track) ? "Usuń z ulubionych" : "Dodaj do ulubionych")

                Button {
                    app.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(app.isMutating)
                .accessibilityLabel("Pomiń utwór")
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .center)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let position = playbackPosition(queue: queue, now: context.date) ?? 0
                let duration = max(Double(track.durationMilliseconds) / 1_000, 1)
                ProgressView(value: position, total: duration)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
        .contentShape(Rectangle())
        .onTapGesture(perform: openPlayer)
    }
}
