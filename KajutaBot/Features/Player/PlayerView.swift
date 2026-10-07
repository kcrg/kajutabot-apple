import SwiftUI

struct PlayerView: View {
    let app: AppState
    let openSearch: () -> Void
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
                    .moveDisabled(app.isMutating)
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
                            Label(.clear, systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text(.clearQueue))
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(app.isMutating || (app.queue?.pendingEntries.isEmpty ?? true)) }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openSearch) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(Text(.addTrackTitle))
            }
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
        VStack(alignment: .leading, spacing: 16) {
            if let track = app.nowPlaying {
                ArtworkView(urlString: track.artworkUrl, layout: .aspectRatio(16 / 9), cornerRadius: 20)
                Text(.nowPlaying).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(track.title).font(.title2.bold()).lineLimit(2, reservesSpace: true)
                    .contentTransition(.interpolate)
                PlaybackProgressView(progress: app.progress)
                Button { app.requeueNowPlaying() } label: {
                    Label {
                        Text("requeueTrack")
                    } icon: { ActionFeedback(status: app.actionStatuses["queue.control.requeue"], symbol: "text.badge.plus") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(app.actionStatuses["queue.control.requeue"] == .pending)
            } else {
                ContentUnavailableView {
                    Label(.nothingPlaying, systemImage: "music.note")
                } description: {
                    Text(app.queue == nil ? String(localized: .connectAndSelectChannel) : String(localized: .queueWaiting))
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { primaryControls; secondaryControls }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 12) {
                    HStack(spacing: 12) { primaryControls }
                    HStack(spacing: 12) { secondaryControls }
                }
            }
            .frame(maxWidth: .infinity)
            if app.actionStatuses["queue.control.skip"] == .success,
               app.lastSkipOutcome == .restartedRepeatedTrack {
                Text("repeatRestarted").font(.caption).foregroundStyle(.secondary)
            }
            if app.localVolume.showVolumeButton {
                Button { showVolume = true } label: { Label("localVolumeTitle", systemImage: "speaker.wave.2") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
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
            size: 52, symbolFont: .title2.weight(.bold), accessibilityLabel: .skipTrack) { app.skip() }
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
            PlayerCircleButton(systemName: favorite ? "heart.fill" : "heart", active: favorite,
                busy: app.actionStatuses[app.favoriteActionKey(for: track)] == .pending, feedback: app.actionStatuses[app.favoriteActionKey(for: track)],
                disabled: app.isLoadingFavorites, accessibilityLabel: favorite ? .removeFavorite : .addFavorite) { app.toggleFavorite(track) }
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
    let systemName: String
    var role: ButtonRole? = nil
    let active: Bool
    let busy: Bool
    var feedback: ActionStatus? = nil
    var disabled = false
    var size: CGFloat = 44
    var symbolFont: Font = .body.weight(.semibold)
    let accessibilityLabel: LocalizedStringResource
    var accessibilityValue: LocalizedStringResource? = nil
    let action: () -> Void

    private var accessibilityValueText: Text {
        if busy { return Text(.inProgress) }
        if feedback == .success { return Text("actionSucceeded") }
        if feedback == .failure { return Text("actionFailed") }
        if let accessibilityValue { return Text(accessibilityValue) }
        return Text(verbatim: "")
    }

    var body: some View {
        Button(role: role, action: action) {
            Group {
                if let feedback {
                    ActionFeedback(status: feedback, symbol: systemName)
                } else if busy {
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
    @State private var showSwap = false

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
                ActionFeedback(status: app.actionStatuses[app.favoriteActionKey(for: entry.track)], symbol: app.isFavorite(entry.track) ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingFavorites || app.actionStatuses[app.favoriteActionKey(for: entry.track)] == .pending)
            .accessibilityLabel(Text(app.isFavorite(entry.track) ? String(localized: .removeFavorite) : String(localized: .addFavorite)))

            Button { app.requeueEntry(entry) } label: {
                ActionFeedback(status: app.actionStatuses["queue.requeue." + entry.id], symbol: "text.badge.plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(.addToQueue))
            .actionFeedbackAccessibility(app.actionStatuses["queue.requeue." + entry.id])
            .disabled(app.actionStatuses["queue.requeue." + entry.id] == .pending)
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .swipeActions(edge: .leading) {
            Button { app.requeueEntry(entry) } label: { Label(.addToQueue, systemImage: "text.badge.plus") }
                .tint(.accentColor).disabled(app.actionStatuses["queue.requeue." + entry.id] == .pending)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { app.removeQueueEntry(entry.id) } label: { Label(.removeFromQueue, systemImage: "trash") }
                .tint(.red).disabled(app.actionStatuses["queue.remove." + entry.id] == .pending)
        }
        .contextMenu {
            Button("swapWith") { showSwap = true }
                .disabled(app.isMutating || (app.queue?.pendingEntries.count ?? 0) < 2)
            Button { app.requeueEntry(entry) } label: { Label(.addToQueue, systemImage: "text.badge.plus") }
            Button { app.swapQueueEntry(entry, offset: -1) } label: { Label("swapPrevious", systemImage: "arrow.up") }
                .disabled(entry.position <= 1 || app.isMutating)
            Button { app.swapQueueEntry(entry, offset: 1) } label: { Label("swapNext", systemImage: "arrow.down") }
                .disabled(entry.position >= (app.queue?.pendingEntries.count ?? 0) || app.isMutating)
            Button(role: .destructive) { app.removeQueueEntry(entry.id) } label: { Label(.removeFromQueue, systemImage: "trash") }
        }
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
                ForEach(Array([44, 52, 44].enumerated()), id: \.offset) { _, size in
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
