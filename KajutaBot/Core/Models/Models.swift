import Foundation

enum SessionType: String, Codable, Sendable {
    case discord
    case guest
}

struct DiscordOAuthExchangeRequest: Codable, Sendable {
    let code: String
    let codeVerifier: String
    let redirectUri: String
}

struct RefreshUserSessionRequest: Codable, Sendable {
    let refreshToken: String
}

struct AuthUserResponse: Codable, Hashable, Sendable {
    let discordUserId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
}

struct AuthSessionResponse: Codable, Sendable {
    let accessToken: String
    let accessTokenExpiresAtUtc: String
    let refreshToken: String?
    let refreshTokenExpiresAtUtc: String?
    let user: AuthUserResponse
    let sessionType: SessionType

    enum CodingKeys: String, CodingKey {
        case accessToken, accessTokenExpiresAtUtc, refreshToken, refreshTokenExpiresAtUtc, user, sessionType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        accessTokenExpiresAtUtc = try container.decode(String.self, forKey: .accessTokenExpiresAtUtc)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        refreshTokenExpiresAtUtc = try container.decodeIfPresent(String.self, forKey: .refreshTokenExpiresAtUtc)
        user = try container.decode(AuthUserResponse.self, forKey: .user)
        sessionType = try container.decodeIfPresent(SessionType.self, forKey: .sessionType) ?? .discord
    }
}

struct UserSession: Codable, Sendable {
    let accessToken: String
    let accessTokenExpiresAtUtc: String
    let refreshToken: String?
    let refreshTokenExpiresAtUtc: String?
    let user: AuthUserResponse
    let sessionType: SessionType
}

struct DiscordGuildResponse: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let iconUrl: String?
    let isAvailable: Bool
}

struct DiscordVoiceChannelResponse: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let position: Int
    let userCount: Int
    let isConnected: Bool
}

struct TrackResponse: Codable, Hashable, Identifiable, Sendable {
    let contentId: String
    let contentType: String
    let title: String
    let url: String
    let durationMilliseconds: Int64
    let thumbnailUrl: String?
    let playCount: Int64
    let cachedAt: String?
    let lastPlayedAt: String?
    let hasCachedThumbnail: Bool
    let artworkReference: String?
    let artworkAccentColor: String?
    let thumbnailVersion: String?

    var id: String { "\(contentType):\(contentId)" }

    init(
        contentId: String,
        contentType: String,
        title: String,
        url: String,
        durationMilliseconds: Int64,
        thumbnailUrl: String?,
        playCount: Int64,
        cachedAt: String?,
        lastPlayedAt: String?,
        hasCachedThumbnail: Bool = false,
        artworkReference: String? = nil,
        artworkAccentColor: String? = nil,
        thumbnailVersion: String? = nil
    ) {
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.url = url
        self.durationMilliseconds = durationMilliseconds
        self.thumbnailUrl = thumbnailUrl
        self.playCount = playCount
        self.cachedAt = cachedAt
        self.lastPlayedAt = lastPlayedAt
        self.hasCachedThumbnail = hasCachedThumbnail
        self.artworkReference = artworkReference
        self.artworkAccentColor = artworkAccentColor
        self.thumbnailVersion = thumbnailVersion
    }

    private enum CodingKeys: String, CodingKey {
        case contentId, contentType, title, url, durationMilliseconds, thumbnailUrl, playCount
        case cachedAt, lastPlayedAt, hasCachedThumbnail, artworkReference, artworkAccentColor, thumbnailVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentId = try container.decode(String.self, forKey: .contentId)
        contentType = try container.decode(String.self, forKey: .contentType)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        durationMilliseconds = try container.decode(Int64.self, forKey: .durationMilliseconds)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        playCount = try container.decode(Int64.self, forKey: .playCount)
        cachedAt = try container.decodeIfPresent(String.self, forKey: .cachedAt)
        lastPlayedAt = try container.decodeIfPresent(String.self, forKey: .lastPlayedAt)
        hasCachedThumbnail = try container.decodeIfPresent(Bool.self, forKey: .hasCachedThumbnail) ?? false
        artworkReference = try container.decodeIfPresent(String.self, forKey: .artworkReference)
        artworkAccentColor = try container.decodeIfPresent(String.self, forKey: .artworkAccentColor)
        thumbnailVersion = try container.decodeIfPresent(String.self, forKey: .thumbnailVersion)
    }
}

struct ApiOperationResponse: Codable, Sendable {
    let succeeded: Bool
    let errorCode: String?
    let message: String?
    let version: Int64?
}

struct RadioStateResponse: Codable, Hashable, Sendable {
    let isEnabled: Bool
    let minimumDurationSeconds: Int?
    let maximumDurationSeconds: Int?
    let availableTrackCount: Int?
}

struct QueueEntryResponse: Codable, Hashable, Identifiable, Sendable {
    let entryId: String
    let position: Int
    let track: TrackResponse

    var id: String { entryId }
}

struct QueueSnapshotResponse: Codable, Hashable, Sendable {
    let guildId: String
    let voiceChannelId: String?
    let nowPlaying: TrackResponse?
    let nowPlayingFromRadio: Bool
    let radio: RadioStateResponse
    let pendingEntries: [QueueEntryResponse]
    let pendingDurationMilliseconds: Int64
    let version: Int64
    let nowPlayingStartedAt: String?
    let isRepeatEnabled: Bool

    init(
        guildId: String,
        voiceChannelId: String?,
        nowPlaying: TrackResponse?,
        nowPlayingFromRadio: Bool,
        radio: RadioStateResponse,
        pendingEntries: [QueueEntryResponse],
        pendingDurationMilliseconds: Int64,
        version: Int64,
        nowPlayingStartedAt: String? = nil,
        isRepeatEnabled: Bool = false
    ) {
        self.guildId = guildId
        self.voiceChannelId = voiceChannelId
        self.nowPlaying = nowPlaying
        self.nowPlayingFromRadio = nowPlayingFromRadio
        self.radio = radio
        self.pendingEntries = pendingEntries
        self.pendingDurationMilliseconds = pendingDurationMilliseconds
        self.version = version
        self.nowPlayingStartedAt = nowPlayingStartedAt
        self.isRepeatEnabled = isRepeatEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case guildId, voiceChannelId, nowPlaying, nowPlayingFromRadio, radio, pendingEntries
        case pendingDurationMilliseconds, version, nowPlayingStartedAt, isRepeatEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guildId = try container.decode(String.self, forKey: .guildId)
        voiceChannelId = try container.decodeIfPresent(String.self, forKey: .voiceChannelId)
        nowPlaying = try container.decodeIfPresent(TrackResponse.self, forKey: .nowPlaying)
        nowPlayingFromRadio = try container.decode(Bool.self, forKey: .nowPlayingFromRadio)
        radio = try container.decode(RadioStateResponse.self, forKey: .radio)
        pendingEntries = try container.decode([QueueEntryResponse].self, forKey: .pendingEntries)
        pendingDurationMilliseconds = try container.decode(Int64.self, forKey: .pendingDurationMilliseconds)
        version = try container.decode(Int64.self, forKey: .version)
        nowPlayingStartedAt = try container.decodeIfPresent(String.self, forKey: .nowPlayingStartedAt)
        isRepeatEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRepeatEnabled) ?? false
    }
}

struct EnqueueRequest: Codable, Sendable {
    let voiceChannelId: String
    let inputs: [String]
    let expectedVersion: Int64?
}

struct EnqueueResponse: Codable, Sendable {
    let operation: ApiOperationResponse
    let snapshot: QueueSnapshotResponse
}

struct QueueMutationRequest: Codable, Sendable {
    let expectedVersion: Int64?
}

struct MoveQueueEntryRequest: Codable, Sendable {
    let entryId: String
    let newPosition: Int
    let expectedVersion: Int64?
}

struct SkipQueueRequest: Codable, Sendable {
    let skipToPosition: Int?
    let expectedVersion: Int64?
}

struct SetQueueRepeatRequest: Codable, Sendable {
    let isEnabled: Bool
    let expectedVersion: Int64?
}

struct QueueMutationResponse: Codable, Sendable {
    let operation: ApiOperationResponse
    let snapshot: QueueSnapshotResponse
}

struct EnableRadioRequest: Codable, Sendable {
    let voiceChannelId: String
    let minimumDurationSeconds: Int
    let maximumDurationSeconds: Int
    let expectedQueueVersion: Int64?
}

struct SearchItemResponse: Codable, Hashable, Identifiable, Sendable {
    let input: String
    let track: TrackResponse
    let metricCount: Int64
    let metricLabel: String?
    let metricCaption: String
    let dateLabel: String?

    var id: String { "\(input)|\(track.id)" }
}

struct SearchResponse: Codable, Sendable {
    let query: String
    let source: String
    let items: [SearchItemResponse]
}

struct FavoriteResponse: Codable, Hashable, Identifiable, Sendable {
    let discordUserId: String
    let contentUrl: String
    let title: String
    let addedAt: String
    let thumbnailUrl: String?

    var id: String { contentUrl }
}

struct AddFavoriteRequest: Codable, Sendable {
    let contentUrl: String
    let title: String?
    let thumbnailUrl: String?
}

struct QueueFavoritesRequest: Codable, Sendable {
    let guildId: String
    let voiceChannelId: String
    let expectedQueueVersion: Int64?
    let shuffle: Bool
}

struct ProblemDetails: Codable, Sendable {
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
    let instance: String?
    let errorCode: String?
}

enum SearchSourceOption: String, CaseIterable, Identifiable, Sendable {
    case youtube = "YouTube"
    case soundCloud = "SoundCloud"
    case database = "Database"

    var id: String { rawValue }
    var displayName: LocalizedStringResource {
        switch self {
        case .youtube: .searchSourceYouTube
        case .soundCloud: .searchSourceSoundCloud
        case .database: .searchSourceDatabase
        }
    }
}

