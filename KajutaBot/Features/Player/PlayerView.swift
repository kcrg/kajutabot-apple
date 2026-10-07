import SwiftUI

struct PlayerView: View {
    let app: AppState
    let openSearch: () -> Void
    @State private var showTargetPicker = false
    @State private var showStopConfirmation = false
    @State private var showClearQueueConfirmation = false
    @State private var draggedEntry: QueueDragItem?

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
                            .trackListRow()
                    }
                } else if let entries = app.queue?.pendingEntries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        QueueRow(app: app, entry: entry)
                            .modifier(QueueDragModifier(app: app, entry: entry, dragged: $draggedEntry))
                            .trackListRow()
                    }
                } else {
                    ContentUnavailableView {
                        Label(.queueEmptyTitle, systemImage: "music.note.list")
                    } description: {
                        Text(.queueEmptyDescription)
                    } actions: {
                        Button(.addTrackTitle, action: openSearch)
                    }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(.queueTitle)
                        if let queue = app.queue {
                            Text("\(queue.pendingEntriesCount) · \(formatDuration(queue.pendingDurationMilliseconds))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    Spacer()
                    if app.actionStatuses["queue.reorder"] != nil {
                        ActionFeedback(status: app.actionStatuses["queue.reorder"], symbol: "arrow.up.arrow.down")
                    }
                    if !(app.queue?.pendingEntries.isEmpty ?? true) {
                        Button(role: .destructive) { showClearQueueConfirmation = true } label: {
                            Label {
                                Text(.clear)
                            } icon: { ActionFeedback(status: app.actionStatuses["queue.control.clear"], symbol: "trash") }
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text(.clearQueue))
                        .actionFeedbackAccessibility(app.actionStatuses["queue.control.clear"])
                        .disabled(app.actionStatuses["queue.control.clear"] == .pending)
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
        .onChange(of: app.queue?.queueVersion) { _, _ in draggedEntry = nil }
        .onChange(of: app.selectedGuildId) { _, _ in draggedEntry = nil }
        .onDisappear { draggedEntry = nil }
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
                DiscordSelectionView(app: app) { showTargetPicker = false }
            }
        }

        .refreshable {
            await app.refreshPlayer()
        }
        .alert(.stopPlaybackQuestion, isPresented: $showStopConfirmation) {
            Button(.cancel, role: .cancel) {}
            Button(.stopBot, role: .destructive) { app.stop() }
        } message: {
            Text(.stopPlaybackMessage)
        }
        .alert(.clearQueueQuestion, isPresented: $showClearQueueConfirmation) {
            Button(.cancel, role: .cancel) {}
            Button(.clearQueue, role: .destructive) { app.clearQueue() }
        } message: {
            Text(.clearQueueMessage)
        }

    }
}

private struct NowPlayingCard: View {
    let app: AppState
    let requestStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = app.nowPlaying {
                ArtworkView(urlString: track.artworkUrl, layout: .aspectRatio(16 / 9), cornerRadius: 20)
                    .playerTransitionElement(track: track, revision: app.presentationTrackRevision,
                        location: .player, part: .artwork, cornerRadius: 20)
                Text(.nowPlaying).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(track.title).font(.title2.bold()).lineLimit(2, reservesSpace: true)
                    .contentTransition(.interpolate)
                    .playerTransitionElement(track: track, revision: app.presentationTrackRevision,
                        location: .player, part: .title)
                PlaybackProgressView(progress: app.progress)
            } else {
                ContentUnavailableView {
                    Label(.nothingPlaying, systemImage: "music.note")
                } description: {
                    Text(app.queue == nil ? String(localized: .connectAndSelectChannel) : String(localized: .queueWaiting))
                }
            }
            GlassEffectContainer(spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { primaryControls; secondaryControls }.fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 8) {
                        HStack(spacing: 4) { primaryControls }
                        HStack(spacing: 4) { secondaryControls }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if app.actionStatuses["queue.control.skip"] == .success,
               app.lastSkipOutcome == .restartedRepeatedTrack {
                Text("repeatRestarted").font(.caption).foregroundStyle(.secondary)
            }
            if app.nowPlaying != nil || app.localVolume.showVolumeButton {
                HStack(spacing: 8) {
                    if app.nowPlaying != nil {
                        Button { app.requeueNowPlaying() } label: {
                            Label {
                                Text("requeueTrack").font(.subheadline)
                            } icon: {
                                ActionFeedback(status: app.actionStatuses["queue.control.requeue"],
                                    symbol: "text.badge.plus", showsSuccess: true)
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(app.actionStatuses["queue.control.requeue"] == .pending)
                        .actionFeedbackAccessibility(app.actionStatuses["queue.control.requeue"], showsSuccess: true)
                    }
                    Spacer(minLength: 0)
                    if app.localVolume.showVolumeButton {
                        Button { showVolume = true } label: {
                            Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("localVolumeTitle"))
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: app.presentationTrackRevision)
        .sheet(isPresented: $showVolume) { LocalVolumeSheet(controller: app.localVolume) }
    }

    @ViewBuilder private var primaryControls: some View {
        PlayerCircleButton(systemName: "stop.fill", role: .destructive, active: false,
            busy: app.actionStatuses["queue.control.stop"] == .pending, feedback: app.actionStatuses["queue.control.stop"], disabled: app.nowPlaying == nil,
            accessibilityLabel: .stopPlayback, action: requestStop)
        PlayerCircleButton(systemName: "forward.end.fill", active: false,
            busy: app.actionStatuses["queue.control.skip"] == .pending, feedback: app.actionStatuses["queue.control.skip"], disabled: app.nowPlaying == nil,
            size: 50, symbolFont: .system(size: 22, weight: .bold), accessibilityLabel: .skipTrack) { app.skip() }
        PlayerCircleButton(systemName: "repeat", active: app.queue?.isRepeatEnabled == true,
            busy: app.actionStatuses["queue.control.repeatTrack"] == .pending, feedback: app.actionStatuses["queue.control.repeatTrack"], disabled: app.nowPlaying == nil,
            accessibilityLabel: .repeatPlayback, accessibilityValue: app.queue?.isRepeatEnabled == true ? .enabled : .disabled) { app.toggleRepeat() }
    }

    @ViewBuilder private var secondaryControls: some View {
        PlayerCircleButton(systemName: "radio.fill", active: app.queue?.radio.isEnabled == true,
            busy: app.actionStatuses["queue.control.radio"] == .pending, feedback: app.actionStatuses["queue.control.radio"],
            disabled: app.queue == nil || (app.queue?.radio.isEnabled != true && !app.hasDiscordTarget),
            accessibilityLabel: .radio, accessibilityValue: app.queue?.radio.isEnabled == true ? .enabled : .disabled) { app.toggleRadio() }
        if let track = app.nowPlaying {
            let favorite = app.isFavorite(track)
            let favoriteStatus = app.actionStatuses[app.favoriteActionKey(for: track)]
            PlayerCircleButton(systemName: favorite ? "heart.fill" : "heart", active: favorite,
                busy: favoriteStatus == .pending, feedback: favoriteStatus,
                disabled: app.isLoadingFavorites, showsActiveOutline: false,
                accessibilityLabel: favorite ? .removeFavorite : .addFavorite,
                accessibilityValue: favorite ? .enabled : .disabled) { app.toggleFavorite(track) }
        }
    }
}

private struct PlayerCardContentSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 20).fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 132, height: 12)
            RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(height: 48)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 8)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct PlayerCircleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let systemName: String
    var role: ButtonRole? = nil
    let active: Bool
    let busy: Bool
    var feedback: ActionStatus? = nil
    var disabled = false
    var showsActiveOutline = true
    var size: CGFloat = 44
    var symbolFont: Font = .system(size: 18, weight: .semibold)
    let accessibilityLabel: LocalizedStringResource
    var accessibilityValue: LocalizedStringResource? = nil
    let action: () -> Void

    private var accessibilityValueText: Text {
        if busy { return Text(.inProgress) }
        if feedback == .failure { return Text("actionFailed") }
        if let accessibilityValue { return Text(accessibilityValue) }
        return Text(verbatim: "")
    }

    var body: some View {
        Button(role: role, action: action) {
            ActionFeedback(status: feedback ?? (busy ? .pending : nil), symbol: systemName,
                symbolColor: active ? .accentColor : .primary)
                .font(symbolFont)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .frame(width: max(size, 44), height: max(size, 44))
                .glassEffect(.regular.tint(active ? Color.accentColor.opacity(0.25) : nil).interactive(), in: .circle)
                .overlay {
                    Circle().strokeBorder(active && showsActiveOutline ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: active)
        .disabled(busy || disabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct QueueRow: View {
    let app: AppState
    let entry: QueueEntryResponse
    @State private var showSwap = false

    var body: some View {
        let favorite = app.isFavorite(entry.track)
        let favoriteStatus = app.actionStatuses[app.favoriteActionKey(for: entry.track)]
        let removeStatus = app.actionStatuses["queue.remove." + entry.id]
        let removing = removeStatus == .pending || removeStatus == .failure
        let rowStatus = removing ? removeStatus : app.actionStatuses["queue.requeue." + entry.id]
        TrackListCard(artworkURL: entry.track.artworkUrl, position: entry.position,
            actionStatus: rowStatus, actionSymbol: removing ? "trash" : "text.badge.plus", confirmsAction: !removing) {
            Text(entry.track.title)
        } details: {
            Text(verbatim: formatDuration(entry.track.durationMilliseconds))
        } trailing: {
            FavoriteButton(isFavorite: favorite, status: favoriteStatus, isDisabled: app.isLoadingFavorites) {
                app.toggleFavorite(entry.track)
            }
        }
        .swipeActions(edge: .leading) {
            Button { app.requeueEntry(entry) } label: {
                Label {
                    Text(.addToQueue)
                } icon: {
                    ActionFeedback(status: app.actionStatuses["queue.requeue." + entry.id],
                        symbol: "text.badge.plus", showsSuccess: true)
                }
            }
                .tint(.accentColor).disabled(app.actionStatuses["queue.requeue." + entry.id] == .pending)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { app.removeQueueEntry(entry.id) } label: {
                Label {
                    Text(.removeFromQueue)
                } icon: { ActionFeedback(status: app.actionStatuses["queue.remove." + entry.id], symbol: "trash") }
            }
                .tint(.red).disabled(app.actionStatuses["queue.remove." + entry.id] == .pending)
        }
        .contextMenu {
            Button("swapWith") { showSwap = true }
                .disabled(app.isMutating || (app.queue?.pendingEntries.count ?? 0) < 2)
        }
        .actionFeedbackAccessibility(rowStatus, showsSuccess: !removing)
        .accessibilityAction(named: Text(.addToQueue)) { app.requeueEntry(entry) }
        .accessibilityAction(named: Text(.removeFromQueue)) { app.removeQueueEntry(entry.id) }
        .accessibilityAction(named: Text("swapPrevious")) { app.swapQueueEntry(entry, offset: -1) }
        .accessibilityAction(named: Text("swapNext")) { app.swapQueueEntry(entry, offset: 1) }
        .accessibilityAction(named: Text("swapWith")) { showSwap = true }
        .sheet(isPresented: $showSwap) {
            QueueSwapView(app: app, source: entry) { showSwap = false }
        }

    }
}

private struct QueueRowSkeleton: View {
    var body: some View {
        TrackListCard(artworkURL: nil) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 15)
        } details: {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 72, height: 11)
        } trailing: {
            EmptyView()
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct PlayerSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayerCardContentSkeleton()

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: index == 1 ? 50 : 44, height: index == 1 ? 50 : 44)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .redacted(reason: .placeholder)
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }
}
