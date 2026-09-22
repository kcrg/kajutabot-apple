import SwiftUI

struct PlayerView: View {
    let app: AppState
    @State private var showTargetPicker = false
    @State private var showStopConfirmation = false
    @State private var showClearQueueConfirmation = false

    var body: some View {
        List {
            Section {
                if !app.hasResolvedQueueState || (app.isLoadingQueue && app.queue == nil) {
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
                    ContentUnavailableView("Kolejka jest pusta", systemImage: "music.note.list", description: Text("Dodaj utwór, aby rozpocząć odtwarzanie."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack {
                    Text("Kolejka")
                    Spacer()
                    if !(app.queue?.pendingEntries.isEmpty ?? true) {
                        Button(role: .destructive) { showClearQueueConfirmation = true } label: {
                            Label("Wyczyść", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Odtwarzacz")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTargetPicker = true
                } label: {
                    Image(systemName: "headphones")
                }
                .accessibilityLabel("Zmień serwer i kanał głosowy")
                .accessibilityValue(app.selectedVoiceChannel?.name ?? app.selectedGuild?.name ?? "Nie wybrano")
            }
        }
        .sheet(isPresented: $showTargetPicker) {
            NavigationStack {
                Form {
                    Section("Sterowanie") {
                        DiscordTargetPicker(app: app, showGuildPicker: !app.isGuest)
                    }
                }
                .navigationTitle("Serwer i kanał")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { showTargetPicker = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .refreshable {
            await app.refreshPlayer()
        }
        .confirmationDialog(
            "Zatrzymać odtwarzanie?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zatrzymaj bota", role: .destructive) { app.stop() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Odtwarzanie zostanie zatrzymane, a aktualny utwór przerwany.")
        }
        .confirmationDialog(
            "Wyczyścić kolejkę?",
            isPresented: $showClearQueueConfirmation,
            titleVisibility: .visible
        ) {
            Button("Wyczyść kolejkę", role: .destructive) { app.clearQueue() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Wszystkie oczekujące utwory zostaną usunięte. Aktualnie odtwarzany utwór nie zostanie zatrzymany.")
        }
        .alert("Błąd", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.dismissError() } }
        )) {
            Button("OK") { app.dismissError() }
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
                        PlayerCircleButton(systemName: "stop.fill", role: .destructive, active: false, busy: app.activeControlAction == .stop, disabled: controlsBlocked, action: requestStop)
                        PlayerCircleButton(systemName: "forward.end.fill", active: false, busy: app.activeControlAction == .skip, disabled: controlsBlocked, size: 52, symbolFont: .title2.weight(.bold)) { app.skip() }
                        PlayerCircleButton(systemName: "repeat", active: app.queue?.isRepeatEnabled == true, busy: app.activeControlAction == .repeatTrack, disabled: controlsBlocked) { app.toggleRepeat() }
                        PlayerCircleButton(systemName: "radio.fill", active: app.queue?.radio.isEnabled == true, busy: app.activeControlAction == .radio, disabled: controlsBlocked) { app.toggleRadio() }
                        PlayerCircleButton(systemName: isFavorite ? "heart.fill" : "heart", active: isFavorite, busy: app.isMutatingFavorites, disabled: app.isMutatingFavorites) { app.toggleFavorite(track) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Nic nie gra")
                        .font(.title2.bold())
                    Text(app.queue == nil ? "Połącz aplikację z serwerem i wybierz kanał głosowy." : "Kolejka oczekuje na utwory.")
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
    let track: TrackResponse
    let queue: QueueSnapshotResponse?
    let revision: Int
    let initiallyReady: Bool

    @State private var displayedTrack: TrackResponse
    @State private var displayedQueue: QueueSnapshotResponse?
    @State private var incomingTrack: TrackResponse?
    @State private var incomingQueue: QueueSnapshotResponse?
    @State private var initialArtworkReady: Bool
    @State private var transitionProgress: CGFloat = 0
    @State private var transitionTask: Task<Void, Never>?

    init(
        track: TrackResponse,
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
            .offset(y: incomingTrack == nil ? 0 : -18 * transitionProgress)
            .scaleEffect(incomingTrack == nil ? 1 : 1 - (0.01 * transitionProgress))
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
                .offset(y: 18 * (1 - transitionProgress))
                .scaleEffect(0.985 + (0.015 * transitionProgress))
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

        withAnimation(.snappy(duration: 0.20, extraBounce: 0.015)) {
            transitionProgress = 1
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(215))
            guard !Task.isCancelled, let stagedTrack = incomingTrack else { return }

            displayedTrack = stagedTrack
            displayedQueue = incomingQueue
            incomingTrack = nil
            transitionProgress = 0
        }
    }
}

private struct NowPlayingTrackContent: View {
    let track: TrackResponse
    let queue: QueueSnapshotResponse?
    var onArtworkLoaded: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtworkHero(track: track, onLoadCompleted: onArtworkLoaded)
            Text("TERAZ ODTWARZANE")
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
    let track: TrackResponse
    var onLoadCompleted: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if let color = Color(hex: track.artworkAccentColor) {
                RadialGradient(
                    colors: [color.opacity(0.45), color.opacity(0.05), .clear],
                    center: .bottom,
                    startRadius: 10,
                    endRadius: 260
                )
                .blur(radius: 26)
            }

            ArtworkView(
                urlString: track.thumbnailUrl,
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
    let track: TrackResponse

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
                    Text(formatDuration(Int64(position * 1_000)))
                    Spacer()
                    Text(durationLabel)
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
    var size: CGFloat = 42
    var symbolFont: Font = .body.weight(.semibold)
    let action: () -> Void

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
            .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(busy || disabled)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct QueueRow: View {
    let app: AppState
    let entry: QueueEntryResponse

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            ArtworkView(urlString: entry.track.thumbnailUrl, layout: .square(54), cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.track.title)
                    .lineLimit(2)
                Text(formatDuration(entry.track.durationMilliseconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { app.toggleFavorite(entry.track) } label: {
                Image(systemName: app.isFavorite(entry.track) ? "heart.fill" : "heart")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) { app.removeQueueEntry(entry.entryId) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
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
                ForEach(Array([42, 52, 42, 42, 42].enumerated()), id: \.offset) { _, size in
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
