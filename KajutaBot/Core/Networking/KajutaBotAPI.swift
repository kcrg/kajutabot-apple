import Foundation

protocol KajutaBotAPI: Sendable {
    func logout() async throws
    func getMyGuilds() async throws -> [DiscordGuildResponse]
    func getVoiceChannels(guildId: String) async throws -> [DiscordVoiceChannelResponse]
    func getQueue(guildId: String) async throws -> QueueSnapshotResponse
    func enqueue(guildId: String, request: EnqueueRequest) async throws -> QueueSnapshotResponse
    func removeQueueEntry(guildId: String, entryId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse
    func moveQueueEntry(guildId: String, entryId: String, request: MoveQueueEntryRequest) async throws -> QueueSnapshotResponse
    func swapQueueEntries(guildId: String, request: SwapQueueEntriesRequest) async throws -> QueueSnapshotResponse
    func clearPendingQueue(guildId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse
    func skip(guildId: String, request: SkipQueueRequest) async throws -> QueueSnapshotResponse
    func setRepeat(guildId: String, request: SetQueueRepeatRequest) async throws -> QueueSnapshotResponse
    func stop(guildId: String, request: QueueMutationRequest) async throws -> QueueSnapshotResponse
    func enableRadio(guildId: String, request: EnableRadioRequest) async throws -> QueueSnapshotResponse
    func disableRadio(guildId: String, expectedQueueVersion: Int64?) async throws -> QueueSnapshotResponse
    func search(query: String, source: SearchSourceOption, maxResults: Int) async throws -> SearchResponse
    func getFavorites() async throws -> [FavoriteResponse]
    func addFavorite(_ request: AddFavoriteRequest) async throws -> FavoriteResponse
    func deleteFavorite(contentURL: String) async throws
    func queueFavorites(_ request: QueueFavoritesRequest) async throws -> QueueSnapshotResponse
}

protocol AuthSessionAPI: Sendable {
    func guest() async throws -> AuthSessionResponse
    func exchange(_ request: DiscordOAuthExchangeRequest) async throws -> AuthSessionResponse
    func refresh(_ refreshToken: String) async throws -> AuthSessionResponse
}
