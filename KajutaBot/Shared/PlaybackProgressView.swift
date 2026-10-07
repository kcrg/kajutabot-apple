import SwiftUI

struct PlaybackProgressView: View {
    let progress: PlaybackProgressState?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let position = progress?.position()
            let duration = progress?.durationMilliseconds ?? 0
            VStack(spacing: 6) {
                ProgressView(value: Double(position ?? 0), total: Double(max(duration, 1)))
                    .accessibilityHidden(true)
                HStack {
                    Text(verbatim: position.map(formatPlaybackElapsed) ?? "—")
                    Spacer()
                    Text(verbatim: formatDuration(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("playbackProgressLabel"))
            .accessibilityValue(position.map(formatPlaybackElapsed) ?? "—")
        }
    }
}

func formatPlaybackElapsed(_ milliseconds: Int64) -> String {
    milliseconds == 0 ? "0:00" : formatDuration(milliseconds)
}
