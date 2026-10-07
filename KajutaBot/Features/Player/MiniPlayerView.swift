import SwiftUI

struct MiniPlayerView: View {
    let app: AppState
    let openPlayer: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let track = app.nowPlaying {
            let favorite = app.isFavorite(track)
            let favoriteStatus = app.actionStatuses[app.favoriteActionKey(for: track)]
            HStack(spacing: 4) {
                Button(action: openPlayer) {
                    HStack(spacing: 10) {
                        ArtworkView(urlString: track.artworkUrl, layout: .square(placement == .inline ? 24 : 42), cornerRadius: 8)
                            .playerTransitionElement(track: track, revision: app.presentationTrackRevision,
                                location: .miniPlayer, part: .artwork, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                .playerTransitionElement(track: track, revision: app.presentationTrackRevision,
                                    location: .miniPlayer, part: .title)
                            if placement != .inline {
                                TimelineView(.periodic(from: .now, by: 1)) { _ in
                                    Text(verbatim: "\(app.progress?.position().map(formatPlaybackElapsed) ?? "—") / \(formatDuration(track.durationMilliseconds))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer(minLength: 2)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain).layoutPriority(1)
                .accessibilityLabel(Text(.openPlayer)).accessibilityValue(track.title)
                if placement != .inline {
                    FavoriteButton(isFavorite: favorite, status: favoriteStatus, isDisabled: app.isLoadingFavorites) {
                        app.toggleFavorite(track)
                    }
                }
                Button { app.skip() } label: {
                    ActionFeedback(status: app.actionStatuses["queue.control.skip"], symbol: "forward.end.fill").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).disabled(app.actionStatuses["queue.control.skip"] == .pending)
                .accessibilityLabel(Text(.skipTrack))
                .actionFeedbackAccessibility(app.actionStatuses["queue.control.skip"])
            }
            .padding(.horizontal, 8)
            .accessibilityAction(named: Text(favorite ? String(localized: .removeFavorite) : String(localized: .addFavorite))) {
                app.toggleFavorite(track)
            }
        }
    }
}
