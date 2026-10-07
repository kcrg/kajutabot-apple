import SwiftUI

struct QueueSwapView: View {
    let app: AppState
    let source: QueueEntryResponse
    let done: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(source.track.title).font(.headline)
                    Text("swapWithDescription").foregroundStyle(.secondary)
                }
                Section("swapWith") {
                    ForEach(app.queue?.pendingEntries.filter { $0.id != source.id } ?? []) { entry in
                        Button {
                            app.swapQueueEntry(source, with: entry)
                            done()
                        } label: {
                            TrackListCard(artworkURL: entry.track.artworkUrl, position: entry.position) {
                                Text(entry.track.title).foregroundStyle(.primary)
                            } details: {
                                Text(verbatim: formatDuration(entry.track.durationMilliseconds))
                            } trailing: { EmptyView() }
                        }
                        .buttonStyle(.plain)
                        .trackListRow()
                        .disabled(app.isMutating || app.queue?.pendingEntries.contains(where: { $0.id == source.id }) != true)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("swapWith")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(.cancel, action: done) } }
        }
    }
}
