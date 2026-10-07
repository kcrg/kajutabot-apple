import Foundation

struct PlaybackProgressState: Equatable {
    let identity: String
    let durationMilliseconds: Int64
    let positionMilliseconds: Int64?
    let observedUptime: TimeInterval
    let isPlaying: Bool

    init(snapshot: QueueSnapshotResponse, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        identity = snapshot.playbackInstanceId ?? snapshot.nowPlaying?.id ?? "idle"
        let duration = max(snapshot.nowPlaying?.durationMilliseconds ?? 0, 0)
        durationMilliseconds = duration
        positionMilliseconds = snapshot.playbackPositionMilliseconds.map {
            min(max($0, 0), duration)
        }
        observedUptime = uptime
        isPlaying = snapshot.nowPlaying != nil && snapshot.nowPlayingStartedAt != nil
    }

    func position(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int64? {
        guard durationMilliseconds > 0, let positionMilliseconds else { return nil }
        let elapsed = isPlaying ? max(uptime - observedUptime, 0) * 1_000 : 0
        let remaining = durationMilliseconds - positionMilliseconds
        guard elapsed.isFinite, elapsed < Double(remaining) else { return durationMilliseconds }
        return positionMilliseconds + Int64(elapsed)
    }
}

enum ActionStatus: Equatable {
    case pending
    case success
    case failure
}
