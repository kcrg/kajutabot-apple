import SwiftUI

struct SharedImportView: View {
    @Bindable var app: AppState
    let entry: PendingSharedLink
    @State private var task: Task<Void, Never>?
    @State private var showTarget = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text(entry.url).textSelection(.enabled) }
                if submitted {
                    Section("sharedAddedTracks") {
                        Label("sharedLinkAdded", systemImage: "checkmark.circle.fill")
                        ForEach(Array(app.lastAddedTracks.enumerated()), id: \.offset) { _, track in Text(track.title) }
                    }
                } else if app.pendingSharedLink?.status == .outcomeUnknown {
                    Section { Text("sharedResultUnknown") }
                } else {
                    Section {
                        Button(.changeServerChannel) { showTarget = true }
                        Button(.addToQueue) {
                            task = Task { submitted = await app.importSharedLink(entry) }
                        }
                        .disabled(!app.hasDiscordTarget || app.isMutating)
                    }
                }
            }
            .navigationTitle("sharedLinkTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done) { app.dismissSharedLink(entry, discard: submitted || entry.status == .outcomeUnknown) }
                        .disabled(app.isMutating)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharedLinkDiscard", role: .destructive) { app.dismissSharedLink(entry, discard: true) }
                        .disabled(app.isMutating)
                }
            }
            .sheet(isPresented: $showTarget) {
                NavigationStack { DiscordSelectionView(app: app) { showTarget = false } }
            }
            .operationError(app)
        }
        .interactiveDismissDisabled(app.isMutating)
        .onDisappear { task?.cancel() }
    }
}
