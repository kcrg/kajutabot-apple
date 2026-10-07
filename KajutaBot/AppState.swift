import AuthenticationServices
import DequeModule
import Foundation
import Nuke
import Observation

enum AppAuthState: Equatable {
    case restoring
    case signedOut(String? = nil)
    case signedIn(AuthUserResponse)
    case recoverableError(String)
}

enum GuildAccessState: Equatable {
    case checking
    case available
    case none
    case error
}

enum PlayerControlAction {
    case stop
    case skip
    case repeatTrack
    case radio
    case requeue
}

@MainActor
@Observable
final class AppState {
    let config: AppConfig
    let realtime: RealtimeClient
    let localVolume: LocalVolumeController

    private let sessionManager: SessionManager
    private let api: any KajutaBotAPI
    private let oauth = DiscordOAuthService()
    private let defaults: UserDefaults
    private let targetDefaults: UserDefaults
    @ObservationIgnored private let mutations = QueueMutationCoordinator()
    @ObservationIgnored private var sessionEpoch = UUID()
    @ObservationIgnored private var selectionEpoch = UUID()
    @ObservationIgnored private var favoriteRevision = 0
    @ObservationIgnored private var favoriteRefreshNeeded = false
    @ObservationIgnored private var channelGeneration = 0
    @ObservationIgnored private var feedbackTokens: [String: UUID] = [:]
    @ObservationIgnored private var operationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var initialized = false
    private var session: UserSession?
    @ObservationIgnored private var presentationRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var presentationIdleTask: Task<Void, Never>?
    @ObservationIgnored private var startupPresentationTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var queueRefreshTask: Task<QueueSnapshotResponse, Error>?
    @ObservationIgnored private var queueRefreshGuildId: String?
    @ObservationIgnored private var queueRefreshGeneration = 0
    @ObservationIgnored private var wasBackgrounded = false
    @ObservationIgnored private var foregroundRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let artworkPrefetcher: ImagePrefetcher
    @ObservationIgnored private var prefetchedArtworkRequests: [ImageRequest] = []
    @ObservationIgnored private var prefetchedArtworkKeys: [String] = []

    var authState: AppAuthState = .restoring
    var isSigningIn = false
    var isGuestSigningIn = false

    var guilds: [DiscordGuildResponse] = []
    var voiceChannels: [DiscordVoiceChannelResponse] = []
    var selectedGuildId: String?
    var selectedVoiceChannelId: String?
    var guildAccessState: GuildAccessState = .checking
    var guildAccessError: String?
    var isLoadingGuilds = false
    var isLoadingVoiceChannels = false

    var queue: QueueSnapshotResponse?
    var presentationQueue: QueueSnapshotResponse?
    var isLoadingQueue = false
    var hasResolvedQueueState = false
    var initialHeroArtworkReady = false
    var presentationTrackRevision = 0
    var actionStatuses: [String: ActionStatus] = [:]
    var progress: PlaybackProgressState?
    var isMutating: Bool { actionStatuses.contains { $0.key.hasPrefix("queue.") && $0.value == .pending } }
    var lastSkipOutcome: SkipOutcome?
    var activeControlAction: PlayerControlAction?
    var pendingSharedLink: PendingSharedLink?
    var lastAddedTracks: [PlaybackTrackResponse] = []
    @ObservationIgnored private var dismissedSharedLinks: Set<UUID> = []
    var errorMessage: String?

    var searchQuery = ""
    var searchSource: SearchSourceOption = .youtube
    var searchResults: [SearchItemResponse] = []
    var searchHistory: Deque<String> = []
    var isSearching = false
    var lastCompletedSearchQuery: String?

    var favorites: [FavoriteResponse] = []
    private var favoriteByIdentity: [String: FavoriteResponse] = [:]
    private var favoriteSavedDates: [String: Date] = [:]
    var isLoadingFavorites = false
    var isMutatingFavorites = false
    var favoritesShuffle = false

    var manualOnboardingRequested = false
    var onboardingCompleted = false

    init(defaults: UserDefaults = .standard, api injectedAPI: (any KajutaBotAPI)? = nil, sessionManager injectedManager: SessionManager? = nil) {
        self.defaults = defaults
        targetDefaults = UserDefaults(suiteName: Keys.appGroup) ?? defaults
        let appConfig = AppConfig()
        config = appConfig
        let authAPI = AuthAPIClient(baseURL: appConfig.apiBaseURL)
        let manager = injectedManager ?? SessionManager(store: KeychainSessionStore(), authAPI: authAPI)
        sessionManager = manager
        api = injectedAPI ?? KajutaBotAPIClient(baseURL: appConfig.apiBaseURL, sessionManager: manager)
        realtime = RealtimeClient(baseURL: appConfig.apiBaseURL) {
            try await manager.accessToken()
        }
        localVolume = LocalVolumeController(transport: realtime)
        let artworkPipeline = ArtworkImagePipeline.make(apiBaseURL: appConfig.apiBaseURL) {
            try await manager.accessToken()
        }
        ImagePipeline.shared = artworkPipeline
        artworkPrefetcher = ImagePrefetcher(
            pipeline: artworkPipeline,
            destination: .memoryCache,
            maxConcurrentRequestCount: 2
        )
        selectedGuildId = targetDefaults.string(forKey: Keys.guildId) ?? defaults.string(forKey: Keys.guildId)
        selectedVoiceChannelId = targetDefaults.string(forKey: Keys.channelId) ?? defaults.string(forKey: Keys.channelId)
        if let selectedGuildId { targetDefaults.set(selectedGuildId, forKey: Keys.guildId) }
        if let selectedVoiceChannelId { targetDefaults.set(selectedVoiceChannelId, forKey: Keys.channelId) }
        searchHistory = Deque((defaults.stringArray(forKey: Keys.searchHistory) ?? []).prefix(5))
        realtime.onLocalVolume = { [weak self] in self?.localVolume.receive($0) }
        realtime.onConnectionChanged = { [weak self] in self?.localVolume.connectionChanged($0) }
        realtime.onSnapshot = { [weak self] snapshot in
            self?.applyQueueSnapshot(snapshot)
        }
        realtime.onRecoveryNeeded = { [weak self] guildId in
            Task { await self?.refreshQueueAsync(guildId: guildId) }
        }
    }

    var currentUser: AuthUserResponse? {
        if case let .signedIn(user) = authState { return user }
        return nil
    }

    var isGuest: Bool { session?.sessionType == .guest }
    var selectedGuild: DiscordGuildResponse? { guilds.first { $0.id == selectedGuildId } }
    var selectedVoiceChannel: DiscordVoiceChannelResponse? { voiceChannels.first { $0.id == selectedVoiceChannelId } }
    var hasDiscordTarget: Bool { selectedGuildId != nil && selectedVoiceChannelId != nil }
    var nowPlaying: PlaybackTrackResponse? { presentationQueue?.nowPlaying }

    var shouldShowOnboarding: Bool {
        guard session != nil, guildAccessState == .available else { return false }
        return manualOnboardingRequested || !onboardingCompleted
    }

    var favoritesOwnerKey: String {
        guard let session else { return "unknown" }
        return session.sessionType == .guest ? "guest" : session.user.discordUserId
    }

    func initializeIfNeeded() async {
        guard !initialized else { return }
        initialized = true
        authState = .restoring
        do {
            guard let restored = try await sessionManager.restore() else {
                authState = .signedOut()
                return
            }
            session = restored
            Diagnostics.info("auth", "Session restored")
            onboardingCompleted = defaults.bool(forKey: onboardingKey(for: restored))
            favoritesShuffle = defaults.bool(forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
            await bootstrapAndPresentAuthenticatedState(user: restored.user)
        } catch {
            authState = .recoverableError(String(localized: .secureSessionReadFailed))
        }
    }

    func retryRestore() {
        initialized = false
        Task { await initializeIfNeeded() }
    }

    func signInWithDiscord() {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            defer { isSigningIn = false }
            do {
                let exchange = try await oauth.authenticate(config: config)
                let newSession = try await sessionManager.exchangeDiscord(exchange)
                Diagnostics.info("auth", "Discord sign-in succeeded")
                await finishSignIn(newSession)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                authState = .signedOut(String(localized: .discordLoginCancelled))
            } catch OAuthError.cancelled {
                authState = .signedOut(String(localized: .discordLoginCancelled))
            } catch {
                authState = .signedOut(userMessage(for: error))
            }
        }
    }

    func signInAsGuest() {
        guard !isSigningIn else { return }
        isSigningIn = true
        isGuestSigningIn = true
        Task {
            defer {
                isSigningIn = false
                isGuestSigningIn = false
            }
            do {
                let newSession = try await sessionManager.signInAsGuest()
                Diagnostics.info("auth", "Guest sign-in succeeded")
                await finishSignIn(newSession)
            } catch {
                authState = .signedOut(userMessage(for: error))
            }
        }
    }

    func switchGuestToDiscord() {
        Task {
            do {
                realtime.stop()
                try await sessionManager.clear()
                resetAuthenticatedState()
                authState = .signedOut()
                Diagnostics.info("auth", "Signed out")
                signInWithDiscord()
            } catch {
                errorMessage = userMessage(for: error)
            }
        }
    }

    func logout() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                realtime.stop()
                if session?.sessionType == .discord {
                    try await api.logout()
                }
                try await sessionManager.clear()
                resetAuthenticatedState()
                authState = .signedOut()
                Diagnostics.info("auth", "Signed out")
            } catch {
                errorMessage = String(localized: .logoutNotConfirmed)
                if let session { authState = .signedIn(session.user) }
            }
        }
    }

    func sceneWillBecomeActive() {
        // On the background -> inactive transition iOS gives us a short head start
        // before the scene is fully visible. Use it to refresh the player immediately.
        guard wasBackgrounded else { return }
        guard case .signedIn = authState else { return }
        refreshSharedInbox()
        let guildId = selectedGuildId

        wasBackgrounded = false
        realtime.connect(guildId: guildId)
        if let guildId { startForegroundPlayerRefresh(guildId: guildId) }
    }

    func sceneBecameActive() {
        let shouldRefreshAfterBackground = wasBackgrounded
        wasBackgrounded = false

        guard case .signedIn = authState else { return }
        refreshSharedInbox()
        let guildId = selectedGuildId
        realtime.connect(guildId: guildId)

        // Fallback for lifecycle paths that move directly from background to active.
        if shouldRefreshAfterBackground {
            if let guildId { startForegroundPlayerRefresh(guildId: guildId) }
        }
    }

    func sceneEnteredBackground() {
        wasBackgrounded = true
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        realtime.stop()
    }

    private func startForegroundPlayerRefresh(guildId: String) {
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = Task(priority: .userInitiated) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.refreshQueueAsync(guildId: guildId, reportErrors: false)
            self.foregroundRefreshTask = nil
        }
    }

    func completeOnboarding() {
        guard let session else { return }
        defaults.set(true, forKey: onboardingKey(for: session))
        onboardingCompleted = true
        manualOnboardingRequested = false
    }

    func refreshGuilds() {
        Task { await loadGuilds() }
    }

    func refreshPlayer() async {
        guard let guildId = selectedGuildId else {
            await loadGuilds()
            return
        }
        await refreshQueueAsync(guildId: guildId)
    }

    func selectGuild(_ guildId: String) {
        guard selectedGuildId != guildId else { return }
        selectionEpoch = UUID()
        channelGeneration &+= 1
        selectedGuildId = guildId
        selectedVoiceChannelId = nil
        voiceChannels = []
        actionStatuses = actionStatuses.filter { !$0.key.hasPrefix("queue.") }
        feedbackTokens = feedbackTokens.filter { !$0.key.hasPrefix("queue.") }
        activeControlAction = nil
        lastSkipOutcome = nil
        progress = nil
        targetDefaults.set(guildId, forKey: Keys.guildId)
        targetDefaults.removeObject(forKey: Keys.channelId)
        queue = nil
        presentationQueue = nil
        hasResolvedQueueState = false
        initialHeroArtworkReady = false
        cancelPresentationRecovery()
        queueRefreshGeneration &+= 1
        queueRefreshTask?.cancel()
        queueRefreshTask = nil
        queueRefreshGuildId = nil
        isLoadingQueue = false
        artworkPrefetcher.stopPrefetching()
        prefetchedArtworkRequests = []
        prefetchedArtworkKeys = []
        realtime.connect(guildId: guildId)
        Task {
            async let channels: Void = loadVoiceChannels(guildId: guildId, preserveChannel: nil)
            async let queueRefresh: Void = refreshQueueAsync(guildId: guildId)
            _ = await (channels, queueRefresh)
        }
    }

    func selectVoiceChannel(_ channelId: String) {
        selectedVoiceChannelId = channelId
        targetDefaults.set(channelId, forKey: Keys.channelId)
    }

    func dismissError() {
        errorMessage = nil
    }

    func setSearchSource(_ source: SearchSourceOption) {
        cancelSearch()
        searchSource = source
        searchResults = []
        lastCompletedSearchQuery = nil
    }

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if looksLikeURL(query) {
            cancelSearch()
            launchOperation { _ = await self.enqueueInputs([query]) }
            return
        }

        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let source = searchSource
        isSearching = true
        errorMessage = nil
        addSearchHistory(query)

        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.searchGeneration == generation {
                    self.isSearching = false
                    self.searchTask = nil
                }
            }
            do {
                let response = try await self.api.search(query: query, source: source, maxResults: 20)
                guard !Task.isCancelled, self.searchGeneration == generation else { return }
                self.searchResults = response.items
                self.lastCompletedSearchQuery = query
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.searchGeneration == generation else { return }
                self.lastCompletedSearchQuery = nil
                self.errorMessage = self.userMessage(for: error)
            }
        }
    }

    func searchFromHistory(_ query: String) {
        searchQuery = query
        performSearch()
    }

    func clearAddTrack() {
        cancelSearch()
        searchQuery = ""
        searchResults = []
        lastCompletedSearchQuery = nil
    }

    func enqueueSearchResult(_ item: SearchItemResponse) async -> Bool {
        await enqueueInputs([item.input], key: "queue.search." + item.id)
    }

    func submitSearchInput() async -> Bool {
        if let url = URLInput.firstURL(in: searchQuery) {
            return await enqueueInputs([url.absoluteString])
        }
        performSearch()
        return false
    }

    @discardableResult
    func enqueueInputs(_ inputs: [String], key: String = "queue.enqueue") async -> Bool {
        guard let guildId = selectedGuildId, let channelId = selectedVoiceChannelId else {
            errorMessage = String(localized: .selectServerChannelFirst)
            return false
        }
        return await mutateQueue(key: key, guildId: guildId) { api, token in
            try await api.enqueue(guildId: guildId, request: EnqueueRequest(
                voiceChannelId: channelId, inputs: inputs, expectedQueueVersion: token
            ))
        }
    }

    func skip() {
        performControl(.skip) { api, guild, token in
            try await api.skip(guildId: guild, request: SkipQueueRequest(skipToPosition: nil, expectedQueueVersion: token))
        }
    }

    func stop() {
        performControl(.stop, forcePresentationIdleOnSuccess: true) { api, guild, token in
            try await api.stop(guildId: guild, request: QueueMutationRequest(expectedQueueVersion: token))
        }
    }

    func toggleRepeat() {
        let enabled = !(queue?.isRepeatEnabled ?? false)
        performControl(.repeatTrack) { api, guild, token in
            try await api.setRepeat(guildId: guild, request: SetQueueRepeatRequest(isEnabled: enabled, expectedQueueVersion: token))
        }
    }

    func toggleRadio() {
        guard let queue else { return }
        if queue.radio.isEnabled {
            performControl(.radio) { api, guild, token in
                try await api.disableRadio(guildId: guild, expectedQueueVersion: token)
            }
        } else {
            guard let channel = selectedVoiceChannelId else {
                errorMessage = String(localized: .selectServerChannelFirst)
                return
            }
            performControl(.radio) { api, guild, token in
                try await api.enableRadio(guildId: guild, request: EnableRadioRequest(
                    voiceChannelId: channel, minimumDurationSeconds: queue.radio.minimumDurationSeconds ?? 60,
                    maximumDurationSeconds: queue.radio.maximumDurationSeconds ?? 600, expectedQueueVersion: token
                ))
            }
        }
    }

    func requeueNowPlaying() {
        guard let track = nowPlaying else { return }
        requeue(track, key: "queue.control.requeue")
    }

    func requeueEntry(_ entry: QueueEntryResponse) {
        requeue(entry.track, key: "queue.requeue." + entry.entryId)
    }

    private func requeue(_ track: PlaybackTrackResponse, key: String) {
        guard let guild = selectedGuildId, let channel = queue?.voiceChannelId ?? selectedVoiceChannelId else { return }
        launchOperation {
            _ = await self.mutateQueue(key: key, guildId: guild) { api, token in
                try await api.enqueue(guildId: guild, request: EnqueueRequest(
                    voiceChannelId: channel, inputs: [track.url], expectedQueueVersion: token
                ))
            }
        }
    }

    func removeQueueEntry(_ entryId: String) {
        guard let guild = selectedGuildId else { return }
        launchOperation {
            _ = await self.mutateQueue(key: "queue.remove." + entryId, guildId: guild) { api, token in
                try await api.removeQueueEntry(guildId: guild, entryId: entryId, expectedQueueVersion: token)
            }
        }
    }

    // Native List reordering is a move. Explicit swaps have a separate action.
    func moveQueueEntry(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1, let from = offsets.first, let current = queue,
              current.pendingEntries.indices.contains(from), !isMutating else { return }
        let entry = current.pendingEntries[from]
        let position = min(max(destination > from ? destination - 1 : destination, 0), current.pendingEntries.count - 1) + 1
        launchOperation {
            guard self.selectedGuildId == current.guildId, self.queue?.queueVersion == current.queueVersion else { return }
            _ = await self.mutateQueue(key: "queue.reorder", guildId: current.guildId) { api, token in
                guard token == current.queueVersion else { throw APIError.http(status: 409, problem: nil) }
                return try await api.moveQueueEntry(guildId: current.guildId, entryId: entry.entryId,
                    request: MoveQueueEntryRequest(newPosition: position, expectedQueueVersion: token))
            }
        }
    }

    func swapQueueEntry(_ entry: QueueEntryResponse, offset: Int) {
        guard let current = queue, let index = current.pendingEntries.firstIndex(where: { $0.id == entry.id }),
              current.pendingEntries.indices.contains(index + offset) else { return }
        swapQueueEntry(entry, with: current.pendingEntries[index + offset])
    }

    func swapQueueEntry(_ entry: QueueEntryResponse, with other: QueueEntryResponse) {
        guard let current = queue else { return }
        _ = swapQueueEntries(firstEntryID: entry.id, secondEntryID: other.id, expectedQueueVersion: current.queueVersion)
    }

    @discardableResult
    func swapQueueEntries(firstEntryID: String, secondEntryID: String, expectedQueueVersion: Int64) -> Bool {
        guard let current = queue, current.queueVersion == expectedQueueVersion,
              firstEntryID != secondEntryID, !isMutating,
              current.pendingEntries.contains(where: { $0.id == firstEntryID }),
              current.pendingEntries.contains(where: { $0.id == secondEntryID }) else { return false }
        launchOperation {
            guard self.selectedGuildId == current.guildId, self.queue?.queueVersion == expectedQueueVersion else { return }
            _ = await self.mutateQueue(key: "queue.reorder", guildId: current.guildId) { api, token in
                guard token == current.queueVersion else { throw APIError.http(status: 409, problem: nil) }
                return try await api.swapQueueEntries(guildId: current.guildId, request: SwapQueueEntriesRequest(
                    firstEntryId: firstEntryID, secondEntryId: secondEntryID, expectedQueueVersion: token))
            }
        }
        return true
    }

    func clearQueue() {
        performControl(nil) { api, guild, token in
            try await api.clearPendingQueue(guildId: guild, expectedQueueVersion: token)
        }
    }

    func refreshFavorites() { launchOperation { await self.refreshFavoritesAsync() } }
    func refreshFavoritesNow() async { await refreshFavoritesAsync() }

    func setFavoritesShuffle(_ enabled: Bool) {
        favoritesShuffle = enabled
        defaults.set(enabled, forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
    }

    func isFavorite(_ track: PlaybackTrackResponse) -> Bool { favorite(for: track) != nil }
    func favoriteSavedDate(for favorite: FavoriteResponse) -> Date? { favoriteSavedDates[favorite.contentUrl] }
    func isFavorite(_ track: SearchTrackResponse) -> Bool {
        favoriteByIdentity[favoriteIdentity(track.url)] != nil ||
            favoriteByIdentity["\(track.contentType.lowercased() == "youtube" ? "youtube" : "soundcloud-id"):\(track.contentId)"] != nil
    }

    func favoriteActionKey(for track: PlaybackTrackResponse) -> String {
        favoriteActionKey(contentType: track.contentType, contentId: track.contentId, url: track.url)
    }

    func favoriteActionKey(for track: SearchTrackResponse) -> String {
        favoriteActionKey(contentType: track.contentType, contentId: track.contentId, url: track.url)
    }

    private func favoriteActionKey(contentType: String, contentId: String, url: String) -> String {
        let prefix = contentType.lowercased() == "youtube" ? "youtube" : "soundcloud-id"
        let identifier = "\(prefix):\(contentId)"
        let urlIdentity = favoriteIdentity(url)
        let existing = favoriteByIdentity[identifier] ?? favoriteByIdentity[urlIdentity]
        let candidates = [identifier, urlIdentity, favoriteIdentity(existing?.contentUrl)]
            .filter { !$0.isEmpty }.map { "favorite." + $0 }
        return candidates.first { actionStatuses[$0] == .pending }
            ?? candidates.first { actionStatuses[$0] != nil }
            ?? "favorite." + (existing.map { favoriteIdentity($0.contentUrl) } ?? urlIdentity)
    }

    func toggleFavorite(_ track: PlaybackTrackResponse) {
        toggleFavorite(request: AddFavoriteRequest(contentType: track.contentType, contentId: track.contentId), url: track.url)
    }

    func toggleFavorite(_ track: SearchTrackResponse) {
        toggleFavorite(request: AddFavoriteRequest(contentType: track.contentType, contentId: track.contentId), url: track.url)
    }

    private func toggleFavorite(request: AddFavoriteRequest, url: String) {
        let prefix = request.contentType.lowercased() == "youtube" ? "youtube" : "soundcloud-id"
        if let existing = favoriteByIdentity["\(prefix):\(request.contentId)"] ?? favoriteByIdentity[favoriteIdentity(url)] { deleteFavorite(existing.contentUrl) }
        else { addFavorite(request, key: favoriteIdentity(url)) }
    }

    func addFavoriteByURL(_ input: String) async -> Bool {
        guard let request = URLInput.favoriteRequest(for: input) else {
            errorMessage = String(localized: "favoriteURLUnsupported")
            return false
        }
        return await mutateFavorite(key: favoriteIdentity(input)) {
            let favorite = try await self.api.addFavorite(request)
            return favorite
        }
    }

    func deleteFavorite(_ contentURL: String) {
        let key = favoriteIdentity(contentURL)
        launchOperation {
            _ = await self.mutateFavorite(key: key, deleting: true) {
                try await self.api.deleteFavorite(contentURL: contentURL)
                return nil
            }
        }
    }

    func playFavorite(_ favorite: FavoriteResponse) {
        launchOperation { _ = await self.enqueueInputs([favorite.contentUrl], key: "queue.favorite." + favoriteIdentity(favorite.contentUrl)) }
    }

    func queueAllFavorites() {
        guard let guild = selectedGuildId, let channel = selectedVoiceChannelId else {
            errorMessage = String(localized: .favoritesNeedTarget)
            return
        }
        let shuffle = favoritesShuffle
        launchOperation {
            _ = await self.mutateQueue(key: "queue.favorites.all", guildId: guild) { api, token in
                try await api.queueFavorites(QueueFavoritesRequest(
                    guildId: guild, voiceChannelId: channel, expectedQueueVersion: token, shuffle: shuffle))
            }
        }
    }

    private func finishSignIn(_ newSession: UserSession) async {
        errorMessage = nil
        session = newSession
        onboardingCompleted = defaults.bool(forKey: onboardingKey(for: newSession))
        favoritesShuffle = defaults.bool(forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
        await bootstrapAndPresentAuthenticatedState(user: newSession.user)
    }

    /// Keep the launch/login surface visible for a very short grace period while the
    /// authenticated state is restored. If the queue and current artwork are ready
    /// sooner, transition immediately. Otherwise enter the app after 200 ms and let
    /// the normal player skeleton carry the remaining load.
    private func bootstrapAndPresentAuthenticatedState(user: AuthUserResponse) async {
        let epoch = sessionEpoch
        localVolume.configure(isDiscord: session?.sessionType == .discord)
        realtime.connect(guildId: selectedGuildId)
        startupPresentationTask?.cancel()
        startupPresentationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.sessionEpoch == epoch else { return }
            self.presentAuthenticatedUI(user: user)
        }

        // Favorites are independent from the initial player presentation.
        Task { [weak self] in
            await self?.refreshFavoritesAsync()
        }

        await loadGuilds()
        guard sessionEpoch == epoch else { return }
        await preloadInitialPlayerArtwork()
        guard sessionEpoch == epoch else { return }

        startupPresentationTask?.cancel()
        startupPresentationTask = nil
        presentAuthenticatedUI(user: user)
    }

    private func presentAuthenticatedUI(user: AuthUserResponse) {
        guard session?.user.discordUserId == user.discordUserId else { return }
        if case .signedIn = authState { return }
        authState = .signedIn(user)
        refreshSharedInbox()
    }

    private func preloadInitialPlayerArtwork() async {
        guard let track = presentationQueue?.nowPlaying else {
            initialHeroArtworkReady = true
            return
        }
        let epoch = sessionEpoch
        let selection = selectionEpoch
        let ready = await ArtworkPreloader.preloadHero(urlString: track.artworkUrl)
        guard epoch == sessionEpoch, selection == selectionEpoch else { return }
        initialHeroArtworkReady = ready
    }

    private func loadGuilds() async {
        guard session != nil, !Task.isCancelled, !isLoadingGuilds else { return }
        let epoch = sessionEpoch
        let hadWorkingAccess = guildAccessState == .available && !guilds.isEmpty
        isLoadingGuilds = true
        if !hadWorkingAccess {
            guildAccessState = .checking
        }
        guildAccessError = nil
        defer { if sessionEpoch == epoch { isLoadingGuilds = false } }
        do {
            let loaded = try await api.getMyGuilds()
            guard sessionEpoch == epoch else { return }
            guilds = loaded.filter(\.isAvailable)
            guard !guilds.isEmpty else {
                selectedGuildId = nil
                selectedVoiceChannelId = nil
                queue = nil
                presentationQueue = nil
                hasResolvedQueueState = true
                guildAccessState = .none
                realtime.connect(guildId: nil)
                return
            }

            guildAccessState = .available
            if let selectedGuildId, !guilds.contains(where: { $0.id == selectedGuildId }) {
                self.selectedGuildId = nil
                selectedVoiceChannelId = nil
                targetDefaults.removeObject(forKey: Keys.guildId)
                targetDefaults.removeObject(forKey: Keys.channelId)
            }
            if self.selectedGuildId == nil, guilds.count == 1 {
                self.selectedGuildId = guilds[0].id
                targetDefaults.set(guilds[0].id, forKey: Keys.guildId)
            }
            if let guildId = self.selectedGuildId {
                realtime.connect(guildId: guildId)

                // Voice-channel metadata is not required to render the player. Let it
                // load independently so a slow Discord endpoint doesn't hold up the
                // initial queue snapshot and hero-artwork preload.
                let preservedChannel = selectedVoiceChannelId
                Task { [weak self] in
                    await self?.loadVoiceChannels(guildId: guildId, preserveChannel: preservedChannel)
                }
                await refreshQueueAsync(guildId: guildId)
            } else {
                hasResolvedQueueState = true
            }
        } catch is CancellationError { return } catch {
            guard sessionEpoch == epoch else { return }
            let message = userMessage(for: error)
            if hadWorkingAccess {
                // A transient guild refresh failure must not tear down a working
                // authenticated UI. Keep the current guild selection and surface
                // the failure as a normal error instead.
                guildAccessState = .available
                errorMessage = message
            } else {
                guildAccessState = .error
                guildAccessError = message
            }
        }
    }

    private func loadVoiceChannels(guildId: String, preserveChannel: String?) async {
        guard session != nil, !Task.isCancelled, selectedGuildId == guildId else { return }
        channelGeneration &+= 1
        let generation = channelGeneration
        let epoch = sessionEpoch
        isLoadingVoiceChannels = true
        defer {
            if selectedGuildId == guildId, sessionEpoch == epoch, channelGeneration == generation {
                isLoadingVoiceChannels = false
            }
        }
        do {
            let channels = try await api.getVoiceChannels(guildId: guildId).sorted { lhs, rhs in
                lhs.position == rhs.position ? lhs.name < rhs.name : lhs.position < rhs.position
            }
            // A response for a previously selected guild must never overwrite the
            // current picker after a fast guild switch.
            guard selectedGuildId == guildId, sessionEpoch == epoch, channelGeneration == generation else { return }

            voiceChannels = channels
            var channel = selectedVoiceChannelId ?? preserveChannel
            if let candidate = channel, !channels.contains(where: { $0.id == candidate }) {
                channel = nil
            }
            if channel == nil, channels.count == 1 { channel = channels[0].id }
            selectedVoiceChannelId = channel
            if let channel { targetDefaults.set(channel, forKey: Keys.channelId) }
            else { targetDefaults.removeObject(forKey: Keys.channelId) }
        } catch is CancellationError {
            return
        } catch {
            guard selectedGuildId == guildId, sessionEpoch == epoch, channelGeneration == generation else { return }
            voiceChannels = []
            selectedVoiceChannelId = nil
            errorMessage = userMessage(for: error)
        }
    }

    private func refreshQueueAsync(guildId: String, reportErrors: Bool = true) async {
        guard session != nil, !Task.isCancelled, selectedGuildId == guildId else { return }
        if queueRefreshGuildId == guildId, let queueRefreshTask {
            _ = try? await queueRefreshTask.value
            return
        }

        queueRefreshTask?.cancel()
        queueRefreshGeneration &+= 1
        let generation = queueRefreshGeneration
        queueRefreshGuildId = guildId
        isLoadingQueue = true

        let task = Task { [api] in
            try await api.getQueue(guildId: guildId)
        }
        queueRefreshTask = task

        defer {
            if queueRefreshGeneration == generation {
                queueRefreshTask = nil
                queueRefreshGuildId = nil
                isLoadingQueue = false
                if selectedGuildId == guildId {
                    hasResolvedQueueState = true
                }
            }
        }

        do {
            let snapshot = try await task.value
            guard queueRefreshGeneration == generation else { return }
            applyQueueSnapshot(snapshot)
        } catch is CancellationError {
            return
        } catch {
            guard queueRefreshGeneration == generation, selectedGuildId == guildId else { return }
            if reportErrors {
                errorMessage = userMessage(for: error)
            }
        }
    }

    private func refreshFavoritesAsync() async {
        guard session != nil, !Task.isCancelled, !isLoadingFavorites, !isMutatingFavorites else { return }
        let epoch = sessionEpoch
        let revision = favoriteRevision
        favoriteRefreshNeeded = false
        isLoadingFavorites = true
        defer {
            if sessionEpoch == epoch {
                isLoadingFavorites = false
                scheduleFavoriteReconciliationIfNeeded()
            }
        }
        do {
            let loaded = try await api.getFavorites()
            guard sessionEpoch == epoch else { return }
            guard favoriteRevision == revision else { favoriteRefreshNeeded = true; return }
            favorites = loaded
            rebuildFavoriteIndex()
        } catch is CancellationError {} catch {
            guard sessionEpoch == epoch, favoriteRevision == revision else { return }
            errorMessage = userMessage(for: error)
        }
    }

    private func scheduleFavoriteReconciliationIfNeeded() {
        guard favoriteRefreshNeeded, !isLoadingFavorites, !isMutatingFavorites, session != nil else { return }
        launchOperation { await self.refreshFavoritesAsync() }
    }

    private func addFavorite(_ request: AddFavoriteRequest, key: String) {
        launchOperation { _ = await self.mutateFavorite(key: key) { try await self.api.addFavorite(request) } }
    }

    private func mutateFavorite(
        key: String, deleting: Bool = false,
        operation: () async throws -> FavoriteResponse?
    ) async -> Bool {
        let actionKey = "favorite." + key
        guard session != nil, !Task.isCancelled, actionStatuses[actionKey] != .pending else { return false }
        let epoch = sessionEpoch
        actionStatuses[actionKey] = .pending
        favoriteRevision &+= 1
        isMutatingFavorites = true
        defer {
            if epoch == sessionEpoch {
                if actionStatuses[actionKey] == .pending { actionStatuses.removeValue(forKey: actionKey) }
                isMutatingFavorites = actionStatuses.contains { $0.key.hasPrefix("favorite.") && $0.value == .pending }
                favoriteRevision &+= 1
                scheduleFavoriteReconciliationIfNeeded()
            }
        }
        do {
            let added = try await operation()
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }
            favorites.removeAll { favoriteIdentity($0.contentUrl) == key }
            if let added {
                let identity = favoriteIdentity(added.contentUrl)
                favorites.removeAll { favoriteIdentity($0.contentUrl) == identity }
                favorites.insert(added, at: 0)
            }
            rebuildFavoriteIndex()
            finishAction(actionKey, status: .success, epoch: epoch)
            return true
        } catch is CancellationError { return false } catch {
            guard epoch == sessionEpoch else { return false }
            favoriteRefreshNeeded = true
            finishAction(actionKey, status: .failure, epoch: epoch)
            errorMessage = userMessage(for: error)
            return false
        }
    }

    private func performControl(
        _ action: PlayerControlAction?, forcePresentationIdleOnSuccess: Bool = false,
        operation: @escaping @MainActor (any KajutaBotAPI, String, Int64) async throws -> QueueSnapshotResponse
    ) {
        guard let guild = selectedGuildId else { return }
        let key = "queue.control." + (action.map { String(describing: $0) } ?? "clear")
        launchOperation {
            _ = await self.mutateQueue(key: key, guildId: guild, forceIdle: forcePresentationIdleOnSuccess, control: action) { api, token in
                try await operation(api, guild, token)
            }
        }
    }

    private func mutateQueue(
        key: String, guildId: String, forceIdle: Bool = false, control: PlayerControlAction? = nil,
        operation: @escaping @MainActor (any KajutaBotAPI, Int64) async throws -> QueueSnapshotResponse
    ) async -> Bool {
        guard session != nil, !Task.isCancelled, actionStatuses[key] != .pending else { return false }
        let epoch = sessionEpoch
        let selection = selectionEpoch
        actionStatuses[key] = .pending
        activeControlAction = control
        errorMessage = nil
        defer {
            if epoch == sessionEpoch, selection == selectionEpoch {
                if activeControlAction == control { activeControlAction = nil }
                if actionStatuses[key] == .pending { actionStatuses.removeValue(forKey: key) }
            }
        }
        do {
            let result = try await mutations.run(guildId: guildId, fetch: { [api] in
                try await api.getQueue(guildId: guildId)
            }, publish: { [weak self] snapshot in
                guard let self, self.sessionEpoch == epoch else { return }
                self.applyQueueSnapshot(snapshot)
            }, mutation: { [api] token in try await operation(api, token) })
            guard epoch == sessionEpoch, selection == selectionEpoch, !Task.isCancelled else { return false }
            if forceIdle { applyQueueSnapshot(result, forcePresentationIdle: true) }
            if control == .skip { lastSkipOutcome = result.skipOutcome }
            lastAddedTracks = result.addedTracks ?? []
            finishAction(key, status: .success, epoch: epoch)
            return true
        } catch is CancellationError { return false } catch {
            guard epoch == sessionEpoch, selection == selectionEpoch else { return false }
            finishAction(key, status: .failure, epoch: epoch)
            errorMessage = userMessage(for: error)
            return false
        }
    }

    func refreshSharedInbox() {
        guard session != nil, pendingSharedLink == nil else { return }
        do {
            pendingSharedLink = try SharedLinkInbox.appGroup().entries().first { !dismissedSharedLinks.contains($0.id) }
        } catch { Diagnostics.warning("share", "Shared inbox could not be read") }
    }

    func importSharedLink(_ entry: PendingSharedLink) async -> Bool {
        guard entry.status == .ready, pendingSharedLink?.status == .ready, hasDiscordTarget else { return false }
        do { pendingSharedLink = try SharedLinkInbox.appGroup().claim(entry) }
        catch { errorMessage = String(localized: "sharedLinkStorageFailed"); return false }
        let success = await enqueueInputs([entry.url], key: "queue.share." + entry.id.uuidString)
        if success {
            do { try SharedLinkInbox.appGroup().remove(entry) }
            catch { errorMessage = String(localized: "sharedLinkStorageFailed") }
        }
        return success
    }

    func dismissSharedLink(_ entry: PendingSharedLink, discard: Bool) {
        if discard {
            do { try SharedLinkInbox.appGroup().remove(entry) }
            catch { errorMessage = String(localized: "sharedLinkStorageFailed"); return }
        }
        dismissedSharedLinks.insert(entry.id)
        pendingSharedLink = nil
    }

    private func finishAction(_ key: String, status: ActionStatus, epoch: UUID) {
        let token = UUID()
        feedbackTokens[key] = token
        actionStatuses[key] = status
        launchOperation {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, self.sessionEpoch == epoch, self.actionStatuses[key] == status, self.feedbackTokens[key] == token else { return }
            self.actionStatuses.removeValue(forKey: key)
            self.feedbackTokens.removeValue(forKey: key)
        }
    }

    private func launchOperation(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        operationTasks[id] = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await operation()
            self.operationTasks.removeValue(forKey: id)
        }
    }

    private func applyQueueSnapshot(_ snapshot: QueueSnapshotResponse, forcePresentationIdle: Bool = false) {
        guard session != nil, selectedGuildId == snapshot.guildId else { return }
        mutations.observe(snapshot)
        if let current = queue {
            if snapshot.version < current.version { return }
            if snapshot == current && !forcePresentationIdle { return }
        }

        let previousQueue = queue
        let previousPresentation = presentationQueue
        let playbackChanged: Bool = {
            guard let nextTrack = snapshot.nowPlaying else { return false }
            guard let previousTrack = previousQueue?.nowPlaying else { return true }
            return previousTrack.id != nextTrack.id
                || previousQueue?.nowPlayingStartedAt != snapshot.nowPlayingStartedAt
                || previousQueue?.playbackInstanceId != snapshot.playbackInstanceId
        }()

        queue = snapshot
        if snapshot.nowPlaying != nil { progress = PlaybackProgressState(snapshot: snapshot) }
        hasResolvedQueueState = true
        prefetchUpcomingArtwork(from: snapshot)
        if playbackChanged {
            presentationTrackRevision &+= 1
        }

        if snapshot.nowPlaying != nil {
            presentationQueue = snapshot
            cancelPresentationRecovery()
        } else if forcePresentationIdle {
            presentationQueue = snapshot
            progress = nil
            cancelPresentationRecovery()
        } else if previousPresentation?.nowPlaying != nil {
            // The backend can briefly publish an idle snapshot while switching tracks.
            // Keep the previous presentation alive so the player never flashes "Nic nie gra".
            presentationQueue = previousPresentation
            let likelyTrackTransition =
                previousQueue?.pendingEntries.isEmpty == false ||
                previousQueue?.isRepeatEnabled == true ||
                previousQueue?.radio.isEnabled == true ||
                !snapshot.pendingEntries.isEmpty ||
                snapshot.isRepeatEnabled ||
                snapshot.radio.isEnabled
            schedulePresentationRecovery(guildId: snapshot.guildId, likelyTrackTransition: likelyTrackTransition)
        } else {
            presentationQueue = snapshot
            cancelPresentationRecovery()
        }

        if let channel = snapshot.voiceChannelId, selectedVoiceChannelId == nil {
            selectedVoiceChannelId = channel
            targetDefaults.set(channel, forKey: Keys.channelId)
        }
    }

    private func schedulePresentationRecovery(guildId: String, likelyTrackTransition: Bool) {
        if likelyTrackTransition, presentationRecoveryTask == nil {
            presentationRecoveryTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled, let self else { return }
                self.presentationRecoveryTask = nil
                guard self.selectedGuildId == guildId,
                      self.queue?.nowPlaying == nil,
                      self.presentationQueue?.nowPlaying != nil else { return }
                await self.refreshQueueAsync(guildId: guildId)
            }
        }

        guard presentationIdleTask == nil else { return }
        let grace = likelyTrackTransition ? Duration.milliseconds(2_500) : .milliseconds(900)
        presentationIdleTask = Task { [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self else { return }
            self.presentationIdleTask = nil
            guard self.selectedGuildId == guildId,
                  let current = self.queue,
                  current.nowPlaying == nil,
                  self.presentationQueue?.nowPlaying != nil else { return }
            self.presentationQueue = current
            self.progress = nil
        }
    }

    private func cancelPresentationRecovery() {
        presentationRecoveryTask?.cancel()
        presentationRecoveryTask = nil
        presentationIdleTask?.cancel()
        presentationIdleTask = nil
    }

    private func prefetchUpcomingArtwork(from snapshot: QueueSnapshotResponse) {
        let candidates = Array(snapshot.pendingEntries.prefix(2))
        let keys = candidates.map { $0.track.artworkUrl ?? "" }
        guard keys != prefetchedArtworkKeys else { return }

        if !prefetchedArtworkRequests.isEmpty {
            artworkPrefetcher.stopPrefetching(with: prefetchedArtworkRequests)
        }

        let requests = candidates.compactMap { entry in
            ArtworkRequestFactory.make(
                urlString: entry.track.artworkUrl,
                layout: .aspectRatio(16 / 9)
            )
        }
        prefetchedArtworkKeys = keys
        prefetchedArtworkRequests = requests
        guard !requests.isEmpty else { return }
        artworkPrefetcher.startPrefetching(with: requests)
    }

    private func favorite(for track: PlaybackTrackResponse) -> FavoriteResponse? {
        switch track.contentType.lowercased() {
        case "youtube":
            if let favorite = favoriteByIdentity["youtube:\(track.contentId)"] { return favorite }
        case "soundcloud":
            if let favorite = favoriteByIdentity["soundcloud-id:\(track.contentId)"] { return favorite }
        default:
            break
        }
        return favoriteByIdentity[favoriteIdentity(track.url)]
    }

    private func rebuildFavoriteIndex() {
        var index: [String: FavoriteResponse] = [:]
        var dates: [String: Date] = [:]
        index.reserveCapacity(favorites.count)
        dates.reserveCapacity(favorites.count)
        for favorite in favorites {
            index[favoriteIdentity(favorite.contentUrl)] = favorite
            dates[favorite.contentUrl] = parseISO8601(favorite.addedAt)
        }
        favoriteByIdentity = index
        favoriteSavedDates = dates
    }

    private func cancelSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func addSearchHistory(_ value: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        searchHistory.prepend(value)
        while searchHistory.count > 5 { _ = searchHistory.popLast() }
        defaults.set(Array(searchHistory), forKey: Keys.searchHistory)
    }

    private func resetAuthenticatedState() {
        sessionEpoch = UUID()
        selectionEpoch = UUID()
        channelGeneration &+= 1
        pendingSharedLink = nil
        lastAddedTracks = []
        dismissedSharedLinks = []
        mutations.reset()
        localVolume.configure(isDiscord: false)
        operationTasks.values.forEach { $0.cancel() }
        operationTasks.removeAll()
        actionStatuses = [:]
        feedbackTokens = [:]
        errorMessage = nil
        activeControlAction = nil
        lastSkipOutcome = nil
        progress = nil
        isMutatingFavorites = false
        favoriteRefreshNeeded = false
        isLoadingFavorites = false
        isLoadingGuilds = false
        isLoadingVoiceChannels = false
        isLoadingQueue = false
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        startupPresentationTask?.cancel()
        startupPresentationTask = nil
        cancelSearch()
        queueRefreshGeneration &+= 1
        queueRefreshTask?.cancel()
        queueRefreshTask = nil
        queueRefreshGuildId = nil
        artworkPrefetcher.stopPrefetching()
        prefetchedArtworkRequests = []
        prefetchedArtworkKeys = []
        session = nil
        onboardingCompleted = false
        manualOnboardingRequested = false
        guilds = []
        voiceChannels = []
        queue = nil
        presentationQueue = nil
        hasResolvedQueueState = false
        initialHeroArtworkReady = false
        presentationTrackRevision = 0
        cancelPresentationRecovery()
        favorites = []
        favoriteByIdentity = [:]
        favoriteSavedDates = [:]
        guildAccessState = .checking
        selectedGuildId = targetDefaults.string(forKey: Keys.guildId)
        selectedVoiceChannelId = targetDefaults.string(forKey: Keys.channelId)
    }

    private func onboardingKey(for session: UserSession) -> String {
        let identity = session.sessionType == .guest ? "guest" : session.user.discordUserId
        return Keys.onboardingPrefix + identity
    }

    private func looksLikeURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    private func userMessage(for error: Error) -> String {
        if error is SessionError {
            let message = String(localized: .sessionExpired)
            realtime.stop()
            resetAuthenticatedState()
            authState = .signedOut(message)
            return message
        }
        if let apiError = error as? APIError { return APIUserMessage.message(for: apiError) }
        if error is URLError { return String(localized: .networkUnavailable) }
        return error.localizedDescription
    }

    private enum Keys {
        static let appGroup = "group.com.tryniecki.KajutaBot"
        static let guildId = "selection.guildId"
        static let channelId = "selection.voiceChannelId"
        static let searchHistory = "search.history"
        static let onboardingPrefix = "onboarding.completed."
        static let favoritesShufflePrefix = "favorites.shuffle."
    }
}
