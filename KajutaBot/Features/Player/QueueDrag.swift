import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let kajutaQueueEntry = UTType(exportedAs: "com.tryniecki.KajutaBot.queue-entry", conformingTo: .data)
}

struct QueueDragItem: Codable, Sendable {
    let guildID: String
    let entryID: String
    let queueVersion: Int64

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.kajutaQueueEntry.identifier, visibility: .ownProcess) { completion in
            do { completion(try JSONEncoder().encode(self), nil) }
            catch { completion(nil, error) }
            return nil
        }
        return provider
    }
}

/// Commit once on drop, never on every row crossed by the pointer.
private struct QueueDropDelegate: DropDelegate {
    let app: AppState
    let targetID: String
    @Binding var dragged: QueueDragItem?
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.kajutaQueueEntry]), let dragged,
              let queue = app.queue, !app.isMutating else { return false }
        return dragged.guildID == queue.guildId && dragged.queueVersion == queue.queueVersion
            && dragged.entryID != targetID
    }

    func dropEntered(info: DropInfo) { targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let valid = validateDrop(info: info)
        if targeted != valid { targeted = valid }
        return DropProposal(operation: valid ? .move : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard validateDrop(info: info), let item = dragged else { dragged = nil; return false }
        dragged = nil
        return app.swapQueueEntries(firstEntryID: item.entryID, secondEntryID: targetID,
            expectedQueueVersion: item.queueVersion)
    }
}

struct QueueDragModifier: ViewModifier {
    let app: AppState
    let entry: QueueEntryResponse
    @Binding var dragged: QueueDragItem?
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0)
                    .allowsHitTesting(false)
            }
            .onDrag {
                guard let queue = app.queue, !app.isMutating,
                      queue.pendingEntries.contains(where: { $0.id == entry.id }) else { return NSItemProvider() }
                let item = QueueDragItem(guildID: queue.guildId, entryID: entry.id, queueVersion: queue.queueVersion)
                dragged = item
                return item.itemProvider()
            }
            .onDrop(of: [.kajutaQueueEntry], delegate: QueueDropDelegate(app: app,
                targetID: entry.id, dragged: $dragged, targeted: $targeted))
            .onChange(of: dragged?.entryID) { _, entryID in
                if entryID == nil { targeted = false }
            }
    }
}
