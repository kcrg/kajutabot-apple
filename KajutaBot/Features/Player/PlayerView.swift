import SwiftUI

struct PlayerView: View {
    @Bindable var app: AppState
    @State private var showTargetPicker = false

    var body: some View {
        List {
            Section {
                if app.isLoadingQueue && app.queue == nil {
                    PlayerSkeleton()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    NowPlayingCard(app: app)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if let entries = app.queue?.pendingEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        QueueRow(app: app, entry: entry)
                    }
                    .onMove(perform: app.moveQueueEntry)
                } else if !app.isLoadingQueue {
                    ContentUnavailableView("Kolejka jest pusta", systemImage: "music.note.list", description: Text("Dodaj utwór, aby rozpocząć odtwarzanie."))
                        .listRowBackground(Color.clear)
                }
            } header: {
                HStack {
                    Text("Kolejka")
                    Spacer()
                    if !(app.queue?.pendingEntries.isEmpty ?? true) {
                        Button(role: .destructive) { app.clearQueue() } label: {
                            Label("Wyczyść", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Odtwarzacz")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showTargetPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "headphones")
                        Text(app.selectedVoiceChannel?.name ?? app.selectedGuild?.name ?? "Wybierz")
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
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
            app.refreshGuilds()
            app.refreshQueue()
        }
        .alert("KajutaBot", isPresented: Binding(
            get: { app.errorMessage != nil || app.noticeMessage != nil },
            set: { if !$0 { app.dismissMessages() } }
        )) {
            Button("OK") { app.dismissMessages() }
        } message: {
            Text(app.errorMessage ?? app.noticeMessage ?? "")
        }
    }
}

private struct NowPlayingCard: View {
    @Bindable var app: AppState

    private var controlsBlocked: Bool {
        app.isMutating && app.activeControlAction == nil
    }

    var body: some View {
        let track = app.nowPlaying
        VStack(alignment: .leading, spacing: 16) {
            if let track {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkHero(track: track)
                    Text("TERAZ ODTWARZANE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(track.title)
                        .font(.title2.bold())
                        .lineLimit(2, reservesSpace: true)
                    PlaybackProgress(queue: app.presentationQueue, track: track)
                }
                .id("\(track.id)|\(app.presentationQueue?.nowPlayingStartedAt ?? "")")
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 12) {
                        PlayerCircleButton(systemName: "stop.fill", role: .destructive, active: false, busy: app.activeControlAction == .stop, disabled: controlsBlocked) { app.stop() }
                        PlayerCircleButton(systemName: "forward.end.fill", active: false, busy: app.activeControlAction == .skip, disabled: controlsBlocked) { app.skip() }
                        PlayerCircleButton(systemName: "repeat", active: app.queue?.isRepeatEnabled == true, busy: app.activeControlAction == .repeatTrack, disabled: controlsBlocked) { app.toggleRepeat() }
                        PlayerCircleButton(systemName: "radio.fill", active: app.queue?.radio.isEnabled == true, busy: app.activeControlAction == .radio, disabled: controlsBlocked) { app.toggleRadio() }
                        PlayerCircleButton(systemName: app.isFavorite(track) ? "heart.fill" : "heart", active: app.isFavorite(track), busy: app.isMutatingFavorites, disabled: app.isMutatingFavorites) { app.toggleFavorite(track) }
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
        .animation(.snappy(duration: 0.36), value: app.presentationQueue?.nowPlayingStartedAt)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct ArtworkHero: View {
    let track: TrackResponse

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

            ArtworkView(urlString: track.thumbnailUrl, layout: .aspectRatio(16 / 9), cornerRadius: 20)
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
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let position = queue.flatMap { playbackPosition(queue: $0, now: context.date) } ?? 0
            let duration = max(Double(track.durationMilliseconds) / 1_000, 1)
            VStack(spacing: 6) {
                ProgressView(value: position, total: duration)
                HStack {
                    Text(formatDuration(Int64(position * 1_000)))
                    Spacer()
                    Text(formatDuration(track.durationMilliseconds))
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
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Group {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(active ? Color.accentColor : Color.primary)
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(busy || disabled)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct QueueRow: View {
    @Bindable var app: AppState
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
        .padding(.vertical, 5)
    }
}

private struct PlayerSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 20).fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(height: 24)
            RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(height: 8)
        }
        .redacted(reason: .placeholder)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
