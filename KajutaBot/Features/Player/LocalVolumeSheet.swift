import SwiftUI

struct LocalVolumeSheet: View {
    @Bindable var controller: LocalVolumeController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("localVolumeObserved")
                        Spacer()
                        Text(controller.observation?.volume.map { "\($0)%" } ?? "—")
                            .monospacedDigit()
                    }
                    .foregroundStyle(controller.isFresh ? .primary : .secondary)
                    HStack {
                        Text("localVolumeDraft")
                        Spacer()
                        Text(controller.draft.map { "\(Int($0))%" } ?? "—")
                            .monospacedDigit()
                    }
                    Slider(value: Binding(get: { controller.draft ?? 0 }, set: controller.updateDraft),
                           in: 0...200, step: 1, onEditingChanged: { editing in
                        if editing { controller.beginEditing() } else { controller.endEditing() }
                    })
                    .disabled(!controller.canEdit)
                    .accessibilityLabel(Text("localVolumeTitle"))
                    .accessibilityValue(controller.draft.map { "\(Int($0))%" } ?? String(localized: .noData))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: controller.adjust(5)
                        case .decrement: controller.adjust(-5)
                        @unknown default: break
                        }
                    }
                    HStack {
                        if controller.showsActivity { ProgressView() }
                        Text(controller.canEdit ? String(localized: "localVolumeHelp") : String(localized: "localVolumeUnavailable"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
                if let message = controller.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                Button(.refresh) { controller.refresh() }
            }
            .navigationTitle("localVolumeTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(.done) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { controller.refresh() }
    }
}
