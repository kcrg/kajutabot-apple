import SwiftUI

struct PlayerView: View {
    let app: AppState
    @State private var showTargetPicker = false
    @State private var showStopConfirmation = false
    @State private var showClearQueueConfirmation = false

    var body: some View {
        List {
            Section {
                if !app.hasResolvedQueueState || (app.queue == nil && app.isLoadingQueue) {
                    PlayerSkeleton()
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    NowPlayingCard(app: app) {
                        showStopConfirmation = true
                    }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listSectionSeparator(.hidden)

            Section {
                if !app.hasResolvedQueueState {
                    ForEach(0..<3, id: \.self) { _ in
                        QueueRowSkeleton()
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else if let entries = app.queue?.pendingEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        QueueRow(app: app, entry: entry)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove(perform: app.moveQueueEntry)
                } else {
                    ContentUnavailableView {
                        Label(.queueEmptyTitle, systemImage: "music.note.list")
                    } description: {
                        Text(.queueEmptyDescription)
                    }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack {
                    Text(.queueTitle)
                    Spacer()
                    if !(app.queue?.pendingEntries.isEmpty ?? true) {
                        Button(role: .destructive) { showClearQueueConfirmation = true } label: {
                            Label(.clear, systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text(.clearQueue))
                    }
                }
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.playerTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTargetPicker = true
                } label: {
                    Image(systemName: "headphones")
                }
                .accessibilityLabel(Text(.changeServerChannel))
                .accessibilityValue(app.selectedVoiceChannel?.name ?? app.selectedGuild?.name ?? String(localized: .notSelected))
            }
        }
        .sheet(isPresented: $showTargetPicker) {
            NavigationStack {
                Form {
                    Section(.controlsSection) {
                        DiscordTargetPicker(app: app, showGuildPicker: !app.isGuest)
                    }
                }
                .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
                .navigationTitle(.serverChannelTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(.done) { showTargetPicker = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .refreshable {
            await app.refreshPlayer()
        }
        .confirmationDialog(
            String(localized: .stopPlaybackQuestion),
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button(.stopBot, role: .destructive) { app.stop() }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(.stopPlaybackMessage)
        }
        .confirmationDialog(
            String(localized: .clearQueueQuestion),
            isPresented: $showClearQueueConfirmation,
            titleVisibility: .visible
        ) {
            Button(.clearQueue, role: .destructive) { app.clearQueue() }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(.clearQueueMessage)
        }
        .alert(String(localized: .errorTitle), isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.dismissError() } }
        )) {
            Button(.ok) { app.dismissError() }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

private struct NowPlayingCard: View {
    let app: AppState
    let requestStop: () -> Void

    private var controlsBlocked: Bool {
        app.isMutating && app.activeControlAction == nil
    }

    private let cardShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        let track = app.nowPlaying

        VStack(alignment: .leading, spacing: 16) {
            if let track {
                let isFavorite = app.isFavorite(track)

                TrackPresentationView(
                    track: track,
                    queue: app.presentationQueue,
                    revision: app.presentationTrackRevision,
                    initiallyReady: app.initialHeroArtworkReady
                )

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 12) {
                        PlayerCircleButton(
                            systemName: "stop.fill",
                            role: .destructive,
                            active: false,
                            busy: app.activeControlAction == .stop,
                            disabled: controlsBlocked,
                            accessibilityLabel: .stopPlayback,
                            action: requestStop
                        )
                        PlayerCircleButton(
                            systemName: "forward.end.fill",
                            active: false,
                            busy: app.activeControlAction == .skip,
                            disabled: controlsBlocked,
                            size: 52,
                            symbolFont: .title2.weight(.bold),
                            accessibilityLabel: .skipTrack
                        ) { app.skip() }
                        PlayerCircleButton(
                            systemName: "repeat",
                            active: app.queue?.isRepeatEnabled == true,
                            busy: app.activeControlAction == .repeatTrack,
                            disabled: controlsBlocked,
                            accessibilityLabel: .repeatPlayback,
                            accessibilityValue: app.queue?.isRepeatEnabled == true ? .enabled : .disabled
                        ) { app.toggleRepeat() }
                        PlayerCircleButton(
                            systemName: "radio.fill",
                            active: app.queue?.radio.isEnabled == true,
                            busy: app.activeControlAction == .radio,
                            disabled: controlsBlocked,
                            accessibilityLabel: .radio,
                            accessibilityValue: app.queue?.radio.isEnabled == true ? .enabled : .disabled
                        ) { app.toggleRadio() }
                        PlayerCircleButton(
                            systemName: isFavorite ? "heart.fill" : "heart",
                            active: isFavorite,
                            busy: app.isMutatingFavorites,
                            disabled: app.isMutatingFavorites,
                            accessibilityLabel: isFavorite ? .removeFavorite : .addFavorite
                        ) { app.toggleFavorite(track) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text(.nothingPlaying)
                        .font(.title2.bold())
                    Text(app.queue == nil ? String(localized: .connectAndSelectChannel) : String(localized: .queueWaiting))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: cardShape)
        .clipShape(cardShape)
    }
}

/// Keeps the previous track rendered until the incoming hero artwork is ready.
/// This avoids the "new image appears instantly over the old animation" effect:
/// both complete track presentations coexist briefly and crossfade inside the card.
private struct TrackPresentationView: View {
    let track: PlaybackTrackResponse
    let queue: QueueSnapshotResponse?
    let revision: Int
    let initiallyReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTrack: PlaybackTrackResponse
    @State private var displayedQueue: QueueSnapshotResponse?
    @State private var incomingTrack: PlaybackTrackResponse?
    @State private var incomingQueue: QueueSnapshotResponse?
    @State private var initialArtworkReady: Bool
    @State private var transitionProgress: CGFloat = 0
    @State private var transitionTask: Task<Void, Never>?

    init(
        track: PlaybackTrackResponse,
        queue: QueueSnapshotResponse?,
        revision: Int,
        initiallyReady: Bool
    ) {
        self.track = track
        self.queue = queue
        self.revision = revision
        self.initiallyReady = initiallyReady
        _displayedTrack = State(initialValue: track)
        _displayedQueue = State(initialValue: queue)
        _initialArtworkReady = State(initialValue: initiallyReady)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !initialArtworkReady {
                PlayerCardContentSkeleton()
                    .transition(.opacity)
            }

            NowPlayingTrackContent(
                track: displayedTrack,
                queue: displayedQueue,
                onArtworkLoaded: revealInitialArtwork
            )
            .opacity(displayedOpacity)
            .offset(y: reduceMotion ? 0 : (incomingTrack == nil ? 0 : -18 * transitionProgress))
            .scaleEffect(reduceMotion ? 1 : (incomingTrack == nil ? 1 : 1 - (0.01 * transitionProgress)))
            .zIndex(0)

            if let incomingTrack {
                NowPlayingTrackContent(
                    track: incomingTrack,
                    queue: incomingQueue,
                    onArtworkLoaded: revealIncomingArtwork
                )
                // Keep the new hierarchy alive so Nuke can load it, but visually
                // hidden until the hero bitmap is ready.
                .opacity(max(0.001, transitionProgress))
                .offset(y: reduceMotion ? 0 : 18 * (1 - transitionProgress))
                .scaleEffect(reduceMotion ? 1 : 0.985 + (0.015 * transitionProgress))
                .zIndex(1)
                .allowsHitTesting(false)
                .accessibilityHidden(transitionProgress < 1)
            }
        }
        // Intentionally do not clip here. During a track change the complete
        // presentation may travel through the card padding. The enclosing
        // NowPlayingCard owns the rounded clip, so animation can use the whole
        // card surface without ever drawing outside the card itself.
        .onChange(of: revision) { _, _ in
            stageIncomingPresentation()
        }
        .onChange(of: queue?.version) { _, _ in
            if incomingTrack == nil {
                displayedQueue = queue
            } else {
                incomingQueue = queue
            }
        }
        .onChange(of: initiallyReady) { _, ready in
            guard ready, !initialArtworkReady, incomingTrack == nil else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                initialArtworkReady = true
            }
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    private var displayedOpacity: CGFloat {
        guard initialArtworkReady else { return 0.001 }
        guard incomingTrack != nil else { return 1 }
        return 1 - transitionProgress
    }

    private func revealInitialArtwork() {
        guard !initialArtworkReady, incomingTrack == nil else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            initialArtworkReady = true
        }
    }

    private func stageIncomingPresentation() {
        transitionTask?.cancel()

        // If an exceptionally fast second update arrives, commit the already staged
        // presentation before starting the next transition. This keeps the animation
        // deterministic instead of stacking multiple hidden LazyImages.
        if let stagedTrack = incomingTrack {
            displayedTrack = stagedTrack
            displayedQueue = incomingQueue
            incomingTrack = nil
            transitionProgress = 0
            initialArtworkReady = true
        }

        incomingTrack = track
        incomingQueue = queue
        transitionProgress = 0
    }

    private func revealIncomingArtwork() {
        guard let stagedTrack = incomingTrack, transitionProgress == 0 else { return }

        // If the initial artwork never became visible (for example a skip happened
        // during startup), reveal only the newest prepared presentation instead of
        // flashing the stale one underneath it.
        if !initialArtworkReady {
            displayedTrack = stagedTrack
            displayedQueue = incomingQueue
            incomingTrack = nil
            transitionProgress = 0
            withAnimation(.easeOut(duration: 0.12)) {
                initialArtworkReady = true
            }
            return
        }

        let transitionAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.14)
            : .snappy(duration: 0.20, extraBounce: 0.015)
        let transitionDuration = reduceMotion ? 150 : 215

        withAnimation(transitionAnimation) {
            transitionProgress = 1
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(transitionDuration))
            guard !Task.isCancelled, let stagedTrack = incomingTrack else { return }

            displayedTrack = stagedTrack
            displayedQueue = incomingQueue
            incomingTrack = nil
            transitionProgress = 0
        }
    }
}

private struct NowPlayingTrackContent: View {
    let track: PlaybackTrackResponse
    let queue: QueueSnapshotResponse?
    var onArtworkLoaded: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtworkHero(track: track, onLoadCompleted: onArtworkLoaded)
            Text(.nowPlaying)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(track.title)
                .font(.title2.bold())
                .lineLimit(2, reservesSpace: true)
            PlaybackProgress(queue: queue, track: track)
        }
    }
}

private struct PlayerCardContentSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 132, height: 12)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 22)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 220, height: 22)
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 8)
        }
        .redacted(reason: .placeholder)
    }
}

private struct ArtworkHero: View {
    let track: PlaybackTrackResponse
    var onLoadCompleted: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if let color = Color(hex: track.artworkAccentColor) {
                // The gradient is soft enough on its own. Avoiding a large live blur
                // prevents an extra offscreen-rendering pass while the player scrolls
                // and while two hero presentations overlap during a track transition.
                RadialGradient(
                    colors: [color.opacity(0.38), color.opacity(0.10), .clear],
                    center: .bottom,
                    startRadius: 8,
                    endRadius: 300
                )
            }

            ArtworkView(
                urlString: track.artworkUrl,
                layout: .aspectRatio(16 / 9),
                cornerRadius: 20,
                onLoadCompleted: onLoadCompleted
            )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PlaybackProgress: View {
    let queue: QueueSnapshotResponse?
    let track: PlaybackTrackResponse

    var body: some View {
        let startedAt = parseISO8601(queue?.nowPlayingStartedAt)
        let durationMilliseconds = track.durationMilliseconds
        let duration = max(Double(durationMilliseconds) / 1_000, 1)
        let durationLabel = formatDuration(durationMilliseconds)

        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let position = playbackPosition(
                startedAt: startedAt,
                durationMilliseconds: durationMilliseconds,
                now: context.date
            ) ?? 0
            VStack(spacing: 6) {
                ProgressView(value: position, total: duration)
                HStack {
                    Text(verbatim: formatDuration(Int64(position * 1_000)))
                    Spacer()
                    Text(verbatim: durationLabel)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlayerCircleButton: View {
    let systemName: String
    var role: ButtonRole? = nil
    let active: Bool
    let busy: Bool
    var disabled = false
    var size: CGFloat = 44
    var symbolFont: Font = .body.weight(.semibold)
    let accessibilityLabel: LocalizedStringResource
    var accessibilityValue: LocalizedStringResource? = nil
    let action: () -> Void

    private var accessibilityValueText: Text {
        if busy { return Text(.inProgress) }
        if let accessibilityValue { return Text(accessibilityValue) }
        return Text(verbatim: "")
    }

    var body: some View {
        Button(role: role, action: action) {
            Group {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(symbolFont)
                        .foregroundStyle(active ? Color.accentColor : Color.primary)
                }
            }
            .frame(width: max(size, 44), height: max(size, 44))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(busy || disabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct QueueRow: View {
    let app: AppState
    let entry: QueueEntryResponse

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(entry.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            ArtworkView(urlString: entry.track.artworkUrl, layout: .square(54), cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.track.title)
                    .lineLimit(2)
                Text(verbatim: formatDuration(entry.track.durationMilliseconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { app.toggleFavorite(entry.track) } label: {
                Image(systemName: app.isFavorite(entry.track) ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(app.isFavorite(entry.track) ? String(localized: .removeFavorite) : String(localized: .addFavorite)))

            Button(role: .destructive) { app.removeQueueEntry(entry.entryId) } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(.removeFromQueue))
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct QueueRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 15)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 72, height: 11)
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct PlayerSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlayerCardContentSkeleton()

            HStack(spacing: 12) {
                ForEach(Array([44, 52, 44, 44, 44].enumerated()), id: \.offset) { _, size in
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: CGFloat(size), height: CGFloat(size))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .redacted(reason: .placeholder)
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
