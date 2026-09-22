import Foundation
import Testing
@testable import KajutaBot

struct KajutaBotTests {
    @Test("Format czasu jest zgodny z playerem")
    func durationFormatting() {
        #expect(formatDuration(0) == "--:--")
        #expect(formatDuration(208_000) == "3:28")
        #expect(formatDuration(3_723_000) == "1:02:03")
    }

    @Test("Tożsamość YouTube jest stabilna dla różnych URL-i")
    func favoriteYouTubeIdentity() {
        #expect(favoriteIdentity("https://youtu.be/dQw4w9WgXcQ") == "youtube:dQw4w9WgXcQ")
        #expect(favoriteIdentity("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "youtube:dQw4w9WgXcQ")
        #expect(favoriteIdentity("yt:dQw4w9WgXcQ") == "youtube:dQw4w9WgXcQ")
    }

    @Test("Pozycja odtwarzania jest ograniczona do długości utworu")
    func playbackProgressClamps() throws {
        let track = TrackResponse(
            contentId: "1", contentType: "youtube", title: "Test", url: "https://example.com",
            durationMilliseconds: 10_000, thumbnailUrl: nil, playCount: 0, cachedAt: nil,
            lastPlayedAt: nil, hasCachedThumbnail: false, artworkReference: nil,
            artworkAccentColor: nil, thumbnailVersion: nil
        )
        let queue = QueueSnapshotResponse(
            guildId: "g", voiceChannelId: "c", nowPlaying: track, nowPlayingFromRadio: false,
            radio: RadioStateResponse(isEnabled: false, minimumDurationSeconds: nil, maximumDurationSeconds: nil, availableTrackCount: nil),
            pendingEntries: [], pendingDurationMilliseconds: 0, version: 1,
            nowPlayingStartedAt: "2026-09-22T10:00:00Z", isRepeatEnabled: false
        )
        let now = try #require(ISO8601DateFormatter.kajutaBotWithoutFraction.date(from: "2026-09-22T10:00:30Z"))
        #expect(playbackPosition(queue: queue, now: now) == 10)
    }

    @Test("Dekodowanie zachowuje domyślne wartości kontraktów Androida")
    func decodingDefaults() throws {
        let json = #"""
        {
          "guildId": "g",
          "voiceChannelId": null,
          "nowPlaying": {
            "contentId": "1",
            "contentType": "youtube",
            "title": "Test",
            "url": "https://example.com",
            "durationMilliseconds": 10000,
            "thumbnailUrl": null,
            "playCount": 0,
            "cachedAt": null,
            "lastPlayedAt": null
          },
          "nowPlayingFromRadio": false,
          "radio": { "isEnabled": false },
          "pendingEntries": [],
          "pendingDurationMilliseconds": 0,
          "version": 1,
          "nowPlayingStartedAt": null
        }
        """#.data(using: .utf8)!

        let queue = try JSONDecoder().decode(QueueSnapshotResponse.self, from: json)
        #expect(queue.isRepeatEnabled == false)
        #expect(queue.nowPlaying?.hasCachedThumbnail == false)
    }

}
