import Foundation
import Observation

struct LocalVolumeState: Codable, Equatable, Sendable {
    let installed: Bool
    let online: Bool
    let available: Bool
    let volume: Int?

    var isValid: Bool {
        (!online || installed) && (!available || online)
            && (available ? volume.map { (0...200).contains($0) } == true : volume == nil)
    }
}

@MainActor
protocol LocalVolumeTransport: AnyObject {
    func getLocalVolume() async throws -> LocalVolumeState
    func setLocalVolume(_ volume: Int) async throws
}

@MainActor
@Observable
final class LocalVolumeController {
    @ObservationIgnored private let transport: any LocalVolumeTransport
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var observationRevision = 0
    @ObservationIgnored private var readRevision = 0
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var indicatorTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIntent: Int?
    private var isDiscord = false
    private var connected = false
    private(set) var observation: LocalVolumeState?
    private(set) var isFresh = false
    private(set) var isEditing = false
    private(set) var isSending = false
    private(set) var showsActivity = false
    private(set) var draft: Double?
    var errorMessage: String?

    init(transport: any LocalVolumeTransport) { self.transport = transport }

    var showVolumeButton: Bool { isDiscord && observation?.installed == true }
    var canEdit: Bool { isDiscord && connected && isFresh && observation?.available == true }

    func configure(isDiscord: Bool) {
        invalidate()
        self.isDiscord = isDiscord
        observation = nil
        draft = nil
        errorMessage = nil
    }

    func connectionChanged(_ connected: Bool) {
        invalidate()
        self.connected = connected
        if connected && isDiscord { refresh() }
    }

    func receive(_ state: LocalVolumeState) {
        guard isDiscord, connected else { return }
        guard state.isValid else {
            invalidate()
            errorMessage = String(localized: "localVolumeUnavailable")
            return
        }
        if !state.available { invalidate() }
        observationRevision &+= 1
        observation = state
        isFresh = true
        if !isEditing && !isSending { draft = state.volume.map(Double.init) }
    }

    func beginEditing() {
        guard canEdit else { return }
        isEditing = true
    }

    func updateDraft(_ value: Double) {
        guard canEdit, value.isFinite else { return }
        draft = min(max(value.rounded(), 0), 200)
    }

    func endEditing() {
        isEditing = false
        guard canEdit, let draft else { return }
        enqueue(Int(draft))
    }

    func adjust(_ increment: Int) {
        guard canEdit, let current = draft ?? observation?.volume.map(Double.init) else { return }
        updateDraft(current + Double(increment))
        endEditing()
    }

    func refresh() {
        guard connected && isDiscord else { return }
        readRevision &+= 1
        let read = readRevision
        let revision = observationRevision
        let currentEpoch = epoch
        readTask?.cancel()
        readTask = Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await self.transport.getLocalVolume()
                guard !Task.isCancelled, self.epoch == currentEpoch, self.readRevision == read,
                      self.observationRevision == revision else { return }
                guard state.isValid else { throw APIError.invalidResponse }
                self.receive(state)
            } catch is CancellationError { return } catch {
                guard self.epoch == currentEpoch, self.readRevision == read,
                      self.observationRevision == revision else { return }
                self.isFresh = false
                // Older hubs can omit this optional capability. Do not break playback.
                self.errorMessage = String(localized: "localVolumeUnavailable")
            }
        }
    }

    private func enqueue(_ value: Int) {
        pendingIntent = value
        guard commandTask == nil else { return }
        let currentEpoch = epoch
        isSending = true
        errorMessage = nil
        commandTask = Task { [weak self] in
            guard let self else { return }
            while self.epoch == currentEpoch, self.canEdit, let value = self.pendingIntent {
                self.pendingIntent = nil
                self.showsActivity = false
                self.indicatorTask?.cancel()
                self.indicatorTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, self.epoch == currentEpoch else { return }
                    self.showsActivity = true
                }
                do {
                    try await self.transport.setLocalVolume(value)
                } catch is CancellationError { break } catch {
                    guard self.epoch == currentEpoch else { return }
                    self.errorMessage = String(localized: "localVolumeSetFailed")
                    self.pendingIntent = nil
                    self.isFresh = false
                    break
                }
                guard self.epoch == currentEpoch, !Task.isCancelled else { return }
            }
            guard self.epoch == currentEpoch else { return }
            self.indicatorTask?.cancel()
            self.showsActivity = false
            self.isSending = false
            self.commandTask = nil
            if !self.isEditing { self.draft = self.observation?.volume.map(Double.init) }
            // Completion confirms the command, not the observed Windows volume.
            self.refresh()
        }
    }

    private func invalidate() {
        epoch = UUID()
        readRevision &+= 1
        readTask?.cancel()
        commandTask?.cancel()
        indicatorTask?.cancel()
        readTask = nil
        commandTask = nil
        indicatorTask = nil
        pendingIntent = nil
        isFresh = false
        isEditing = false
        isSending = false
        showsActivity = false
        draft = observation?.volume.map(Double.init)
    }
}
