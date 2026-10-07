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

struct PlaybackTrackResponse: Codable, Hashable, Identifiable, Sendable {
    let contentId: String
    let contentType: String
    let title: String
    let url: String
    let durationMilliseconds: Int64
    let artworkUrl: String?
    let playCount: Int64
    let artworkAccentColor: String?

    var id: String { "\(contentType):\(contentId)" }
}

struct SearchTrackResponse: Codable, Hashable, Identifiable, Sendable {
    let contentId: String
    let contentType: String
    let title: String
    let url: String
    let durationMilliseconds: Int64
    let artworkUrl: String?

    var id: String { "\(contentType):\(contentId)" }
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
    let track: PlaybackTrackResponse

    var id: String { entryId }
}

struct QueueSnapshotResponse: Codable, Hashable, Sendable {
    let guildId: String
    let voiceChannelId: String?
    let nowPlaying: PlaybackTrackResponse?
    let nowPlayingFromRadio: Bool
    let radio: RadioStateResponse
    let pendingEntries: [QueueEntryResponse]
    let pendingEntriesCount: Int
    let pendingDurationMilliseconds: Int64
    let version: Int64
    let queueVersion: Int64
    let playbackInstanceId: String?
    let playbackPositionMilliseconds: Int64?
    let skipOutcome: SkipOutcome?
    let addedTracks: [PlaybackTrackResponse]?
    let nowPlayingStartedAt: String?
    let isRepeatEnabled: Bool

    init(
        guildId: String,
        voiceChannelId: String?,
        nowPlaying: PlaybackTrackResponse?,
        nowPlayingFromRadio: Bool,
        radio: RadioStateResponse,
        pendingEntries: [QueueEntryResponse],
        pendingDurationMilliseconds: Int64,
        version: Int64,
        nowPlayingStartedAt: String? = nil,
        isRepeatEnabled: Bool = false,
        pendingEntriesCount: Int? = nil,
        queueVersion: Int64,
        playbackInstanceId: String? = nil,
        playbackPositionMilliseconds: Int64? = nil,
        skipOutcome: SkipOutcome? = nil,
        addedTracks: [PlaybackTrackResponse]? = nil
    ) {
        self.guildId = guildId
        self.voiceChannelId = voiceChannelId
        self.nowPlaying = nowPlaying
        self.nowPlayingFromRadio = nowPlayingFromRadio
        self.radio = radio
        self.pendingEntries = pendingEntries
        self.pendingDurationMilliseconds = pendingDurationMilliseconds
        self.version = version
        self.queueVersion = queueVersion
        self.pendingEntriesCount = pendingEntriesCount ?? pendingEntries.count
        self.playbackInstanceId = playbackInstanceId
        self.playbackPositionMilliseconds = playbackPositionMilliseconds
        self.skipOutcome = skipOutcome
        self.addedTracks = addedTracks
        self.nowPlayingStartedAt = nowPlayingStartedAt
        self.isRepeatEnabled = isRepeatEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case guildId, voiceChannelId, nowPlaying, nowPlayingFromRadio, radio, pendingEntries
        case pendingEntriesCount, pendingDurationMilliseconds, version, queueVersion, nowPlayingStartedAt, isRepeatEnabled
        case playbackInstanceId, playbackPositionMilliseconds, skipOutcome, addedTracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guildId = try container.decode(String.self, forKey: .guildId)
        voiceChannelId = try container.decodeIfPresent(String.self, forKey: .voiceChannelId)
        nowPlaying = try container.decodeIfPresent(PlaybackTrackResponse.self, forKey: .nowPlaying)
        nowPlayingFromRadio = try container.decode(Bool.self, forKey: .nowPlayingFromRadio)
        radio = try container.decode(RadioStateResponse.self, forKey: .radio)
        pendingEntries = try container.decode([QueueEntryResponse].self, forKey: .pendingEntries)
        pendingDurationMilliseconds = try container.decode(Int64.self, forKey: .pendingDurationMilliseconds)
        version = try container.decode(Int64.self, forKey: .version)
        queueVersion = try container.decode(Int64.self, forKey: .queueVersion)
        pendingEntriesCount = try container.decode(Int.self, forKey: .pendingEntriesCount)
        playbackInstanceId = try container.decodeIfPresent(String.self, forKey: .playbackInstanceId)
        playbackPositionMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .playbackPositionMilliseconds)
        skipOutcome = try container.decodeIfPresent(SkipOutcome.self, forKey: .skipOutcome)
        addedTracks = try container.decodeIfPresent([PlaybackTrackResponse].self, forKey: .addedTracks)
        nowPlayingStartedAt = try container.decodeIfPresent(String.self, forKey: .nowPlayingStartedAt)
        isRepeatEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRepeatEnabled) ?? false
    }
}

enum SkipOutcome: String, Codable, Hashable, Sendable {
    case advanced = "Advanced"
    case restartedRepeatedTrack = "RestartedRepeatedTrack"
}

struct SwapQueueEntriesRequest: Codable, Sendable {
    let firstEntryId: String
    let secondEntryId: String
    let expectedQueueVersion: Int64?
}

struct EnqueueRequest: Codable, Sendable {
    let voiceChannelId: String
    let inputs: [String]
    let expectedQueueVersion: Int64?
}

struct QueueMutationRequest: Codable, Sendable {
    let expectedQueueVersion: Int64?
}

struct MoveQueueEntryRequest: Codable, Sendable {
    let newPosition: Int
    let expectedQueueVersion: Int64?
}

struct SkipQueueRequest: Codable, Sendable {
    let skipToPosition: Int?
    let expectedQueueVersion: Int64?
}

struct SetQueueRepeatRequest: Codable, Sendable {
    let isEnabled: Bool
    let expectedQueueVersion: Int64?
}

struct EnableRadioRequest: Codable, Sendable {
    let voiceChannelId: String
    let minimumDurationSeconds: Int
    let maximumDurationSeconds: Int
    let expectedQueueVersion: Int64?
}

struct SearchItemResponse: Codable, Hashable, Identifiable, Sendable {
    let input: String
    let track: SearchTrackResponse
    let metricCount: Int64
    let metricCaption: String
    let dateLabel: String?

    var id: String { "\(input)|\(track.id)" }
}

struct SearchResponse: Codable, Sendable {
    let query: String
    let items: [SearchItemResponse]
}

struct FavoriteResponse: Codable, Hashable, Identifiable, Sendable {
    let contentUrl: String
    let title: String
    let addedAt: String
    let thumbnailUrl: String?

    var id: String { contentUrl }
}

struct AddFavoriteRequest: Codable, Sendable {
    let contentType: String
    let contentId: String
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
    let currentQueueVersion: Int64?
}

