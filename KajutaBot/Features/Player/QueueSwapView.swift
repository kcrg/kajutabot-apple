import SwiftUI

struct QueueSwapView: View {
    let app: AppState
    let source: QueueEntryResponse
    let done: () -> Void

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
                            HStack {
                                Text(verbatim: "\(entry.position)").monospacedDigit()
                                Text(entry.track.title).foregroundStyle(.primary)
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(app.isMutating || app.queue?.pendingEntries.contains(where: { $0.id == source.id }) != true)
                    }
                }
            }
            .navigationTitle("swapWith")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(.cancel, action: done) } }
        }
    }
}
