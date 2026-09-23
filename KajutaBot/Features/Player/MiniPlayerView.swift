import SwiftUI

struct MiniPlayerView: View {
    let app: AppState
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

    private func inlinePlayer(track: PlaybackTrackResponse) -> some View {
        HStack(spacing: 4) {
            Button(action: openPlayer) {
                HStack(spacing: 7) {
                    ArtworkView(
                        urlString: track.artworkUrl,
                        layout: .square(24),
                        cornerRadius: 6
                    )
                    .fixedSize()

                    Text(track.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.openPlayer))
            .accessibilityValue(track.title)

            Button {
                app.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.isMutating)
            .accessibilityLabel(Text(.skipTrack))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .center)
    }

    private func expandedPlayer(track: PlaybackTrackResponse, queue: QueueSnapshotResponse) -> some View {
        let startedAt = parseISO8601(queue.nowPlayingStartedAt)
        let durationMilliseconds = track.durationMilliseconds
        let duration = max(Double(durationMilliseconds) / 1_000, 1)
        let durationLabel = formatDuration(durationMilliseconds)
        let isFavorite = app.isFavorite(track)

        return ZStack(alignment: .bottom) {
            HStack(spacing: 4) {
                Button(action: openPlayer) {
                    HStack(spacing: 10) {
                        ArtworkView(
                            urlString: track.artworkUrl,
                            layout: .square(42),
                            cornerRadius: 9
                        )
                        .fixedSize()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let position = playbackPosition(
                                    startedAt: startedAt,
                                    durationMilliseconds: durationMilliseconds,
                                    now: context.date
                                ) ?? 0
                                Text(verbatim: "\(formatDuration(Int64(position * 1_000))) / \(durationLabel)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel(Text(.openPlayer))
                .accessibilityValue(track.title)

                Button {
                    app.toggleFavorite(track)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.isMutatingFavorites)
                .accessibilityLabel(Text(isFavorite ? String(localized: .removeFavorite) : String(localized: .addFavorite)))

                Button {
                    app.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app.isMutating)
                .accessibilityLabel(Text(.skipTrack))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .center)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let position = playbackPosition(
                    startedAt: startedAt,
                    durationMilliseconds: durationMilliseconds,
                    now: context.date
                ) ?? 0
                ProgressView(value: position, total: duration)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
    }
}
