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

    @Test("Postęp używa zegara monotonicznego i pozycji backendu")
    func playbackProgressClamps() {
        let queue = queueFixture(version: 10, queueVersion: 3, playback: true, position: 5_000)
        let progress = PlaybackProgressState(snapshot: queue, uptime: 100)
        #expect(progress.position(at: 102) == 7_000)
        #expect(progress.position(at: 130) == 10_000)
        #expect(progress.position(at: 99) == 5_000)
        #expect(PlaybackProgressState(snapshot: queueFixture(playback: true), uptime: 100).position(at: 101) == nil)
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
            "artworkUrl": null,
            "playCount": 0
          },
          "nowPlayingFromRadio": false,
          "radio": { "isEnabled": false },
          "pendingEntries": [],
          "pendingDurationMilliseconds": 0,
          "version": 10,
          "queueVersion": 3,
          "pendingEntriesCount": 0,
          "nowPlayingStartedAt": null
        }
        """#.data(using: .utf8)!

        let queue = try JSONDecoder().decode(QueueSnapshotResponse.self, from: json)
        #expect(queue.version == 10)
        #expect(queue.queueVersion == 3)
        #expect(queue.isRepeatEnabled == false)
        #expect(queue.nowPlaying?.artworkUrl == nil)
    }

    @Test("Publiczne DTO nie wysyłają technicznych pól i powtórzonego ID")
    func publicDTOShape() throws {
        let move = MoveQueueEntryRequest(newPosition: 2, expectedQueueVersion: 7)
        let moveData = try JSONEncoder().encode(move)
        let moveJSON = try #require(JSONSerialization.jsonObject(with: moveData) as? [String: Any])
        #expect(moveJSON["entryId"] == nil)
        #expect(moveJSON["expectedVersion"] == nil)
        #expect(moveJSON["expectedQueueVersion"] as? Int == 7)
        #expect(moveJSON["newPosition"] as? Int == 2)

        let track = PlaybackTrackResponse(
            contentId: "id", contentType: "YouTube", title: "Title", url: "https://example.com",
            durationMilliseconds: 10_000, artworkUrl: "https://example.com/art.jpg", playCount: 4,
            artworkAccentColor: nil
        )
        let trackData = try JSONEncoder().encode(track)
        let trackJSON = try #require(JSONSerialization.jsonObject(with: trackData) as? [String: Any])
        #expect(trackJSON["artworkUrl"] as? String == "https://example.com/art.jpg")
        #expect(trackJSON["artworkReference"] == nil)
        #expect(trackJSON["cachedAt"] == nil)
        #expect(trackJSON["thumbnailVersion"] == nil)
    }

    @Test("Wynik wyszukiwania dekoduje pojedynczą datę bez Source")
    func searchDTOShape() throws {
        let json = #"{"query":"test","items":[{"input":"url","track":{"contentId":"id","contentType":"YouTube","title":"Title","url":"url","durationMilliseconds":1000,"artworkUrl":null},"metricCount":2,"metricCaption":"views","dateLabel":"2026"}]}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(SearchResponse.self, from: json)
        #expect(response.items.first?.dateLabel == "2026")
        #expect(response.items.first?.track.contentId == "id")
    }
    @Test("Artwork API URL jest rozwiązywany względem hosta API")
    func relativeArtworkURL() throws {
        let apiBaseURL = try #require(URL(string: "https://api.example.com"))
        let resolved = ArtworkURLResolver.resolve(
            "/api/v1/app/artwork/YouTube/video-id",
            apiBaseURL: apiBaseURL
        )
        #expect(resolved?.absoluteString == "https://api.example.com/api/v1/app/artwork/YouTube/video-id")
        #expect(ArtworkURLResolver.resolve("not a url", apiBaseURL: apiBaseURL) == nil)
    }

}
