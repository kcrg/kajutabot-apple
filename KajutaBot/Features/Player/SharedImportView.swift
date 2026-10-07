import SwiftUI

struct SharedImportView: View {
    @Bindable var app: AppState
    let entry: PendingSharedLink
    @State private var task: Task<Void, Never>?
    @State private var showTarget = false
    @State private var submitted = false
    @State private var isSubmitting = false
    @State private var addedTracks: [PlaybackTrackResponse] = []

    var body: some View {
        NavigationStack {
            Group {
                if isSubmitting {
                    SharedQueueLoadingView(message: String(localized: "sharedLinkAdding"))
                } else if submitted {
                    SharedQueueResultView(tracks: addedTracks,
                        message: String(localized: "sharedLinkAdded"),
                        tracksTitle: String(localized: "sharedAddedTracks")) { track, hero in
                        ArtworkView(urlString: track.artworkUrl,
                            layout: hero ? .aspectRatio(16 / 9) : .square(64),
                            cornerRadius: hero ? 20 : 12)
                    }
                } else if app.pendingSharedLink?.status == .outcomeUnknown {
                    ContentUnavailableView {
                        Label("sharedLinkTitle", systemImage: "info.circle")
                    } description: { Text("sharedResultUnknown") }
                } else {
                    Form {
                        Section { Text(entry.url).textSelection(.enabled) }
                        Section {
                            Button(.changeServerChannel) { showTarget = true }
                            Button(.addToQueue, action: submit)
                                .disabled(!app.hasDiscordTarget || app.isMutating)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("sharedLinkTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done) {
                        app.dismissSharedLink(entry, discard: submitted || app.pendingSharedLink?.status == .outcomeUnknown)
                    }
                    .disabled(isSubmitting || app.isMutating)
                }
                if !submitted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("sharedLinkDiscard", role: .destructive) { app.dismissSharedLink(entry, discard: true) }
                            .disabled(isSubmitting || app.isMutating)
                    }
                }
            }
            .sheet(isPresented: $showTarget) {
                NavigationStack { DiscordSelectionView(app: app) { showTarget = false } }
            }
            .operationError(app)
        }
        .interactiveDismissDisabled(isSubmitting || app.isMutating)
        .onDisappear { task?.cancel() }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        task = Task {
            defer { isSubmitting = false }
            let tracks = await app.importSharedLink(entry)
            guard !Task.isCancelled else { return }
            if let tracks {
                // Keep this receipt's result even if another queue mutation follows.
                addedTracks = tracks
                submitted = true
            }
        }
    }
}
