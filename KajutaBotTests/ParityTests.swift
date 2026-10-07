import Foundation
import Testing
@testable import KajutaBot

func queueFixture(version: Int64 = 1, queueVersion: Int64 = 1,
                  playback: Bool = false, position: Int64? = nil,
                  instance: String = "playback-1") -> QueueSnapshotResponse {
    QueueSnapshotResponse(
        guildId: "guild", voiceChannelId: "channel",
        nowPlaying: playback ? PlaybackTrackResponse(contentId: "video", contentType: "YouTube", title: "Track",
            url: "https://youtu.be/dQw4w9WgXcQ", durationMilliseconds: 10_000,
            artworkUrl: nil, playCount: 0, artworkAccentColor: nil) : nil,
        nowPlayingFromRadio: false,
        radio: RadioStateResponse(isEnabled: false, minimumDurationSeconds: nil,
            maximumDurationSeconds: nil, availableTrackCount: nil),
        pendingEntries: [], pendingDurationMilliseconds: 0, version: version,
        nowPlayingStartedAt: playback ? "2026-10-07T10:00:00Z" : nil,
        queueVersion: queueVersion, playbackInstanceId: playback ? instance : nil,
        playbackPositionMilliseconds: position
    )
}

@MainActor
private final class ControlledGate<Value> {
    private var result: Value?
    private var continuation: CheckedContinuation<Value, Never>?
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Value {
        entered = true
        observers.forEach { $0.resume() }
        observers = []
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func release(_ value: Value) {
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Suite("Kontrakty i koordynacja kolejki")
@MainActor
struct QueueParityTests {
    @Test("Druga mutacja czeka i używa queueVersion poprzedniej odpowiedzi")
    func serializesMutations() async throws {
        let coordinator = QueueMutationCoordinator()
        coordinator.observe(queueFixture(version: 20, queueVersion: 7))
        let gate = ControlledGate<QueueSnapshotResponse>()
        var tokens: [Int64] = []
        let first = Task {
            try await coordinator.run(guildId: "guild", fetch: { queueFixture() }, publish: { _ in }) { token in
                tokens.append(token)
                return await gate.wait()
            }
        }
        await gate.waitUntilEntered()
        let second = Task {
            try await coordinator.run(guildId: "guild", fetch: { queueFixture() }, publish: { _ in }) { token in
                tokens.append(token)
                return queueFixture(version: 22, queueVersion: 9)
            }
        }
        #expect(tokens == [7])
        gate.release(queueFixture(version: 21, queueVersion: 8))
        _ = try await first.value
        _ = try await second.value
        #expect(tokens == [7, 8])
    }

    @Test("Niepotwierdzony POST uzgadnia stan raz, bez powtórzenia mutacji")
    func reconcilesWithoutRetry() async throws {
        let coordinator = QueueMutationCoordinator()
        coordinator.observe(queueFixture(queueVersion: 3))
        var attempts = 0
        var reads = 0
        var observed: [Int64] = []
        do {
            _ = try await coordinator.run(guildId: "guild", fetch: {
                reads += 1
                return queueFixture(version: 10, queueVersion: 4)
            }, publish: { observed.append($0.queueVersion) }) { _ in
                attempts += 1
                throw URLError(.timedOut)
            }
            Issue.record("A failed POST must remain a failure")
        } catch { #expect(error is URLError) }
        let next = try await coordinator.run(guildId: "guild", fetch: { queueFixture() }, publish: { _ in }) { token in
            #expect(token == 4)
            return queueFixture(version: 11, queueVersion: 5)
        }
        #expect(next.queueVersion == 5)
        #expect(attempts == 1)
        #expect(reads == 1)
        #expect(observed == [4])
    }

    @Test("Starszy wynik HTTP nie cofa nowszego zdarzenia realtime")
    func rejectsOlderSnapshot() async throws {
        let coordinator = QueueMutationCoordinator()
        coordinator.observe(queueFixture(version: 20, queueVersion: 7))
        coordinator.observe(queueFixture(version: 19, queueVersion: 6))
        _ = try await coordinator.run(guildId: "guild", fetch: { queueFixture() }, publish: { _ in }) { token in
            #expect(token == 7)
            return queueFixture(version: 21, queueVersion: 8)
        }
    }

    @Test("Logout odrzuca wynik nieanulowalnej operacji poprzedniej sesji")
    func resetRejectsLateMutation() async {
        let coordinator = QueueMutationCoordinator()
        coordinator.observe(queueFixture())
        let gate = ControlledGate<QueueSnapshotResponse>()
        var publications = 0
        let task = Task {
            try await coordinator.run(guildId: "guild", fetch: { queueFixture() }, publish: { _ in publications += 1 }) { _ in
                await gate.wait()
            }
        }
        await gate.waitUntilEntered()
        coordinator.reset()
        gate.release(queueFixture(version: 2, queueVersion: 2))
        do { _ = try await task.value; Issue.record("Late result must be cancelled") }
        catch { #expect(error is CancellationError) }
        #expect(publications == 0)
    }

    @Test("Swap i favorite kodują publiczny kontrakt po ID")
    func requestShapes() throws {
        let swap = SwapQueueEntriesRequest(firstEntryId: "a", secondEntryId: "b", expectedQueueVersion: 7)
        let raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(swap)) as? [String: Any])
        #expect(raw["expectedQueueVersion"] as? Int == 7)
        #expect(raw["expectedVersion"] == nil)
        let favorite = AddFavoriteRequest(contentType: "YouTube", contentId: "video")
        let data = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(favorite)) as? [String: Any])
        #expect(Set(data.keys) == ["contentType", "contentId"])
    }

    @Test("Nowe odtworzenie tego samego utworu ma inną tożsamość i reset postępu")
    func repeatResetsProgress() {
        let first = PlaybackProgressState(snapshot: queueFixture(playback: true, position: 9_000, instance: "one"), uptime: 100)
        let second = PlaybackProgressState(snapshot: queueFixture(playback: true, position: 0, instance: "two"), uptime: 105)
        #expect(first.identity != second.identity)
        #expect(second.position(at: 106) == 1_000)
    }
}

@MainActor
private final class VolumeFake: LocalVolumeTransport {
    let read = ControlledGate<LocalVolumeState>()
    let command = ControlledGate<Void>()
    let secondCommand = ControlledGate<Void>()
    var values: [Int] = []
    func getLocalVolume() async throws -> LocalVolumeState { await read.wait() }
    func setLocalVolume(_ volume: Int) async throws {
        values.append(volume)
        if values.count == 2 { secondCommand.release(()) }
        await command.wait()
    }
}

@Suite("Lokalna głośność")
@MainActor
struct LocalVolumeTests {
    private let ready = LocalVolumeState(installed: true, online: true, available: true, volume: 100)

    @Test("Walidacja zależności helpera i granic 0–200")
    func validatesObservations() {
        #expect(ready.isValid)
        #expect(LocalVolumeState(installed: true, online: true, available: true, volume: 0).isValid)
        #expect(LocalVolumeState(installed: true, online: true, available: true, volume: 200).isValid)
        #expect(!LocalVolumeState(installed: false, online: true, available: true, volume: 100).isValid)
        #expect(!LocalVolumeState(installed: true, online: false, available: true, volume: 100).isValid)
        #expect(!LocalVolumeState(installed: true, online: true, available: false, volume: 100).isValid)
        #expect(!LocalVolumeState(installed: true, online: true, available: true, volume: nil).isValid)
        #expect(!LocalVolumeState(installed: true, online: true, available: true, volume: 201).isValid)
    }

    @Test("Późny odczyt nie nadpisuje nowszego zdarzenia")
    func eventWinsOverRead() async {
        let fake = VolumeFake()
        let controller = LocalVolumeController(transport: fake)
        controller.configure(isDiscord: true)
        controller.connectionChanged(true)
        await fake.read.waitUntilEntered()
        controller.receive(LocalVolumeState(installed: true, online: true, available: true, volume: 124))
        fake.read.release(ready)
        await Task.yield()
        #expect(controller.observation?.volume == 124)
    }

    @Test("Podczas wysyłania zachowana jest tylko ostatnia zatwierdzona wartość")
    func coalescesLatestIntent() async {
        let fake = VolumeFake()
        let controller = LocalVolumeController(transport: fake)
        controller.configure(isDiscord: true)
        controller.connectionChanged(true)
        controller.receive(ready)
        controller.beginEditing(); controller.updateDraft(110); controller.endEditing()
        await fake.command.waitUntilEntered()
        controller.beginEditing(); controller.updateDraft(130); controller.endEditing()
        controller.beginEditing(); controller.updateDraft(170); controller.endEditing()
        fake.command.release(())
        await fake.secondCommand.wait()
        #expect(fake.values == [110, 170])
        controller.connectionChanged(false)
        fake.read.release(ready)
    }

    @Test("Zdarzenie podczas edycji zachowuje draft, logout odrzuca komendę")
    func editingAndLogout() async {
        let fake = VolumeFake()
        let controller = LocalVolumeController(transport: fake)
        controller.configure(isDiscord: true)
        controller.connectionChanged(true)
        controller.receive(ready)
        controller.beginEditing()
        controller.updateDraft(150)
        controller.receive(LocalVolumeState(installed: true, online: true, available: true, volume: 90))
        #expect(controller.draft == 150)
        controller.endEditing()
        await fake.command.waitUntilEntered()
        controller.configure(isDiscord: false)
        fake.command.release(())
        fake.read.release(ready)
        await Task.yield()
        #expect(fake.values == [150])
        #expect(!controller.showVolumeButton)
        #expect(controller.observation == nil)
        #expect(!controller.isSending)
    }
}

struct SharedInputTests {
    @Test("Link z API jest pełnym URL HTTP(S), a tekst udostępnienia nadal wymaga ekstrakcji")
    func validatesStructuredURLs() {
        #expect(URLInput.httpURL(" https://example.com/track%20name?list=one&v=two ")?.absoluteString == "https://example.com/track%20name?list=one&v=two")
        #expect(URLInput.httpURL("http://example.com/track")?.host == "example.com")
        #expect(URLInput.httpURL("file:///private/token") == nil)
        #expect(URLInput.httpURL("/track") == nil)
        #expect(URLInput.httpURL("Polecam https://example.com/track") == nil)
        #expect(URLInput.firstURL(in: "Polecam https://example.com/track dziś")?.absoluteString == "https://example.com/track")
    }

    @Test("Parser przyjmuje URL z tekstem, odrzuca inne schematy i obcy host")
    func parsesURLs() {
        #expect(URLInput.firstURL(in: "Polecam https://youtu.be/dQw4w9WgXcQ dziś")?.host == "youtu.be")
        #expect(URLInput.firstURL(in: "file:///private/token") == nil)
        #expect(URLInput.favoriteRequest(for: "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ") == nil)
        #expect(URLInput.favoriteRequest(for: "https://youtube.com/shorts/dQw4w9WgXcQ")?.contentId == "dQw4w9WgXcQ")
        #expect(URLInput.favoriteRequest(for: "https://youtube.com/watch?v=bad") == nil)
    }

    @Test("Inbox zachowuje dwie intencje i nie pozwala drugi raz claimować tej samej")
    func inboxClaim() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = SharedLinkInbox(directory: directory)
        let first = try inbox.insert(url: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let second = try inbox.insert(url: #require(URL(string: "https://soundcloud.com/artist/track")))
        #expect(try inbox.entries().count == 2)
        #expect(try inbox.claim(first).status == .outcomeUnknown)
        #expect(throws: (any Error).self) { try inbox.claim(first) }
        try inbox.remove(first)
        #expect(try inbox.entries().map(\.id) == [second.id])
    }
}
