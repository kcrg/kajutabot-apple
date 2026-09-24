import AuthenticationServices
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
}

@MainActor
@Observable
final class AppState {
    let config: AppConfig
    let realtime: RealtimeClient

    private let sessionManager: SessionManager
    private let api: KajutaBotAPIClient
    private let oauth = DiscordOAuthService()
    private let defaults: UserDefaults
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
    var isMutating = false
    var activeControlAction: PlayerControlAction?
    var errorMessage: String?

    var searchQuery = ""
    var searchSource: SearchSourceOption = .youtube
    var searchResults: [SearchItemResponse] = []
    var searchHistory: [String] = []
    var isSearching = false
    var lastCompletedSearchQuery: String?

    var favorites: [FavoriteResponse] = []
    private var favoriteByIdentity: [String: FavoriteResponse] = [:]
    var isLoadingFavorites = false
    var isMutatingFavorites = false
    var favoritesShuffle = false

    var manualOnboardingRequested = false
    var onboardingCompleted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let appConfig = AppConfig()
        config = appConfig
        let authAPI = AuthAPIClient(baseURL: appConfig.apiBaseURL)
        let manager = SessionManager(store: KeychainSessionStore(), authAPI: authAPI)
        sessionManager = manager
        api = KajutaBotAPIClient(baseURL: appConfig.apiBaseURL, sessionManager: manager)
        realtime = RealtimeClient(baseURL: appConfig.apiBaseURL) {
            try await manager.accessToken()
        }
        let artworkPipeline = ArtworkImagePipeline.make(apiBaseURL: appConfig.apiBaseURL) {
            try await manager.accessToken()
        }
        ImagePipeline.shared = artworkPipeline
        artworkPrefetcher = ImagePrefetcher(
            pipeline: artworkPipeline,
            destination: .memoryCache,
            maxConcurrentRequestCount: 2
        )
        selectedGuildId = defaults.string(forKey: Keys.guildId)
        selectedVoiceChannelId = defaults.string(forKey: Keys.channelId)
        searchHistory = defaults.stringArray(forKey: Keys.searchHistory) ?? []
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
        guard case .signedIn = authState, let guildId = selectedGuildId else { return }

        wasBackgrounded = false
        realtime.connect(guildId: guildId)
        startForegroundPlayerRefresh(guildId: guildId)
    }

    func sceneBecameActive() {
        let shouldRefreshAfterBackground = wasBackgrounded
        wasBackgrounded = false

        guard case .signedIn = authState, let guildId = selectedGuildId else { return }
        realtime.connect(guildId: guildId)

        // Fallback for lifecycle paths that move directly from background to active.
        if shouldRefreshAfterBackground {
            startForegroundPlayerRefresh(guildId: guildId)
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
        selectedGuildId = guildId
        selectedVoiceChannelId = nil
        defaults.set(guildId, forKey: Keys.guildId)
        defaults.removeObject(forKey: Keys.channelId)
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
        defaults.set(channelId, forKey: Keys.channelId)
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
            enqueueInputs([query])
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
                let response = try await self.api.search(query: query, source: source)
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

    func enqueueSearchResult(_ item: SearchItemResponse) {
        enqueueInputs([item.input])
    }

    func enqueueInputs(_ inputs: [String]) {
        guard let guildId = selectedGuildId, let channelId = selectedVoiceChannelId else {
            errorMessage = String(localized: .selectServerChannelFirst)
            return
        }
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        Task {
            defer { isMutating = false }
            do {
                let response = try await api.enqueue(
                    guildId: guildId,
                    request: EnqueueRequest(voiceChannelId: channelId, inputs: inputs, expectedVersion: queue?.version)
                )
                applyQueueSnapshot(response)
            } catch {
                await handleMutationError(error)
            }
        }
    }

    func skip() { performControl(.skip) { api, guildId, version in try await api.skip(guildId: guildId, request: SkipQueueRequest(skipToPosition: nil, expectedVersion: version)) } }
    func stop() {
        performControl(.stop, forcePresentationIdleOnSuccess: true) { api, guildId, version in
            try await api.stop(guildId: guildId, request: QueueMutationRequest(expectedVersion: version))
        }
    }

    func toggleRepeat() {
        let enabled = !(queue?.isRepeatEnabled ?? false)
        performControl(.repeatTrack) { api, guildId, version in
            try await api.setRepeat(guildId: guildId, request: SetQueueRepeatRequest(isEnabled: enabled, expectedVersion: version))
        }
    }

    func toggleRadio() {
        guard let queue else { return }
        if queue.radio.isEnabled {
            performControl(.radio, forcePresentationIdleOnSuccess: true) { api, guildId, version in
                try await api.disableRadio(guildId: guildId, expectedVersion: version)
            }
            return
        }
        guard let channelId = selectedVoiceChannelId else {
            errorMessage = String(localized: .selectServerChannelFirst)
            return
        }
        let minDuration = queue.radio.minimumDurationSeconds ?? 60
        let maxDuration = queue.radio.maximumDurationSeconds ?? 600
        performControl(.radio, forcePresentationIdleOnSuccess: true) { api, guildId, version in
            try await api.enableRadio(
                guildId: guildId,
                request: EnableRadioRequest(
                    voiceChannelId: channelId,
                    minimumDurationSeconds: minDuration,
                    maximumDurationSeconds: maxDuration,
                    expectedQueueVersion: version
                )
            )
        }
    }

    func removeQueueEntry(_ entryId: String) {
        guard let guildId = selectedGuildId, !isMutating else { return }
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                let response = try await api.removeQueueEntry(guildId: guildId, entryId: entryId, expectedVersion: queue?.version)
                applyQueueSnapshot(response)
            } catch { await handleMutationError(error) }
        }
    }

    func moveQueueEntry(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1, let from = offsets.first, let current = queue, current.pendingEntries.indices.contains(from) else { return }
        var preview = current.pendingEntries
        let moved = preview.remove(at: from)
        let adjusted = min(max(destination > from ? destination - 1 : destination, 0), preview.count)
        preview.insert(moved, at: adjusted)
        let newPosition = adjusted + 1
        let optimistic = QueueSnapshotResponse(
            guildId: current.guildId,
            voiceChannelId: current.voiceChannelId,
            nowPlaying: current.nowPlaying,
            nowPlayingFromRadio: current.nowPlayingFromRadio,
            radio: current.radio,
            pendingEntries: preview.enumerated().map { index, entry in
                QueueEntryResponse(entryId: entry.entryId, position: index + 1, track: entry.track)
            },
            pendingDurationMilliseconds: current.pendingDurationMilliseconds,
            version: current.version,
            nowPlayingStartedAt: current.nowPlayingStartedAt,
            isRepeatEnabled: current.isRepeatEnabled
        )
        queue = optimistic
        Task {
            do {
                let response = try await api.moveQueueEntry(
                    guildId: current.guildId,
                    entryId: moved.entryId,
                    request: MoveQueueEntryRequest(newPosition: newPosition, expectedVersion: current.version)
                )
                applyQueueSnapshot(response)
            } catch {
                queue = current
                await handleMutationError(error)
            }
        }
    }

    func clearQueue() {
        guard let guildId = selectedGuildId else { return }
        performControl(nil) { api, _, version in
            try await api.clearPendingQueue(guildId: guildId, expectedVersion: version)
        }
    }

    func refreshFavorites() {
        Task { await refreshFavoritesAsync() }
    }

    func refreshFavoritesNow() async {
        await refreshFavoritesAsync()
    }

    func setFavoritesShuffle(_ enabled: Bool) {
        favoritesShuffle = enabled
        defaults.set(enabled, forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
    }

    func isFavorite(_ track: PlaybackTrackResponse) -> Bool {
        favorite(for: track) != nil
    }

    func toggleFavorite(_ track: PlaybackTrackResponse) {
        if let existing = favorite(for: track) {
            deleteFavorite(existing.contentUrl)
        } else {
            addFavorite(contentURL: track.url, title: track.title, thumbnailURL: track.artworkUrl)
        }
    }

    func addFavoriteByURL(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addFavorite(contentURL: value, title: nil, thumbnailURL: nil)
    }

    func deleteFavorite(_ contentURL: String) {
        guard !isMutatingFavorites else { return }
        isMutatingFavorites = true
        Task {
            defer { isMutatingFavorites = false }
            do {
                try await api.deleteFavorite(contentURL: contentURL)
                let identity = favoriteIdentity(contentURL)
                favorites.removeAll { favoriteIdentity($0.contentUrl) == identity }
                rebuildFavoriteIndex()
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    func playFavorite(_ favorite: FavoriteResponse) {
        enqueueInputs([favorite.contentUrl])
    }

    func queueAllFavorites() {
        guard let guildId = selectedGuildId, let channelId = selectedVoiceChannelId else {
            errorMessage = String(localized: .favoritesNeedTarget)
            return
        }
        guard !isMutatingFavorites else { return }
        isMutatingFavorites = true
        Task {
            defer { isMutatingFavorites = false }
            do {
                let response = try await api.queueFavorites(
                    QueueFavoritesRequest(
                        guildId: guildId,
                        voiceChannelId: channelId,
                        expectedQueueVersion: queue?.version,
                        shuffle: favoritesShuffle
                    )
                )
                applyQueueSnapshot(response)
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    private func finishSignIn(_ newSession: UserSession) async {
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
        startupPresentationTask?.cancel()
        startupPresentationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.presentAuthenticatedUI(user: user)
        }

        // Favorites are independent from the initial player presentation.
        Task { [weak self] in
            await self?.refreshFavoritesAsync()
        }

        await loadGuilds()
        await preloadInitialPlayerArtwork()

        startupPresentationTask?.cancel()
        startupPresentationTask = nil
        presentAuthenticatedUI(user: user)
    }

    private func presentAuthenticatedUI(user: AuthUserResponse) {
        guard session?.user.discordUserId == user.discordUserId else { return }
        if case .signedIn = authState { return }
        authState = .signedIn(user)
    }

    private func preloadInitialPlayerArtwork() async {
        guard let track = presentationQueue?.nowPlaying else {
            initialHeroArtworkReady = true
            return
        }
        initialHeroArtworkReady = await ArtworkPreloader.preloadHero(urlString: track.artworkUrl)
    }

    private func loadGuilds() async {
        guard !isLoadingGuilds else { return }
        let hadWorkingAccess = guildAccessState == .available && !guilds.isEmpty
        isLoadingGuilds = true
        if !hadWorkingAccess {
            guildAccessState = .checking
        }
        guildAccessError = nil
        defer { isLoadingGuilds = false }
        do {
            let loaded = try await api.getMyGuilds()
            guilds = loaded.filter(\.isAvailable)
            guard !guilds.isEmpty else {
                selectedGuildId = nil
                selectedVoiceChannelId = nil
                queue = nil
                presentationQueue = nil
                hasResolvedQueueState = true
                guildAccessState = .none
                realtime.stop()
                return
            }

            guildAccessState = .available
            if let selectedGuildId, !guilds.contains(where: { $0.id == selectedGuildId }) {
                self.selectedGuildId = nil
                selectedVoiceChannelId = nil
                defaults.removeObject(forKey: Keys.guildId)
                defaults.removeObject(forKey: Keys.channelId)
            }
            if self.selectedGuildId == nil, guilds.count == 1 {
                self.selectedGuildId = guilds[0].id
                defaults.set(guilds[0].id, forKey: Keys.guildId)
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
        } catch {
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
        isLoadingVoiceChannels = true
        defer {
            if selectedGuildId == guildId {
                isLoadingVoiceChannels = false
            }
        }
        do {
            let channels = try await api.getVoiceChannels(guildId: guildId).sorted { lhs, rhs in
                lhs.position == rhs.position ? lhs.name < rhs.name : lhs.position < rhs.position
            }
            // A response for a previously selected guild must never overwrite the
            // current picker after a fast guild switch.
            guard selectedGuildId == guildId else { return }

            voiceChannels = channels
            var channel = preserveChannel
            if let candidate = channel, !channels.contains(where: { $0.id == candidate }) {
                channel = nil
            }
            if channel == nil, channels.count == 1 { channel = channels[0].id }
            selectedVoiceChannelId = channel
            if let channel { defaults.set(channel, forKey: Keys.channelId) }
            else { defaults.removeObject(forKey: Keys.channelId) }
        } catch is CancellationError {
            return
        } catch {
            guard selectedGuildId == guildId else { return }
            voiceChannels = []
            selectedVoiceChannelId = nil
            errorMessage = userMessage(for: error)
        }
    }

    private func refreshQueueAsync(guildId: String, reportErrors: Bool = true) async {
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
        guard !isLoadingFavorites else { return }
        isLoadingFavorites = true
        defer { isLoadingFavorites = false }
        do {
            favorites = try await api.getFavorites()
            rebuildFavoriteIndex()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func addFavorite(contentURL: String, title: String?, thumbnailURL: String?) {
        guard !isMutatingFavorites else { return }
        isMutatingFavorites = true
        Task {
            defer { isMutatingFavorites = false }
            do {
                let added = try await api.addFavorite(AddFavoriteRequest(contentUrl: contentURL, title: title, thumbnailUrl: thumbnailURL))
                let identity = favoriteIdentity(added.contentUrl)
                favorites.removeAll { favoriteIdentity($0.contentUrl) == identity }
                favorites.insert(added, at: 0)
                rebuildFavoriteIndex()
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    private func performControl(
        _ action: PlayerControlAction?,
        forcePresentationIdleOnSuccess: Bool = false,
        operation: @escaping (KajutaBotAPIClient, String, Int64?) async throws -> QueueSnapshotResponse
    ) {
        guard let guildId = selectedGuildId, !isMutating else { return }
        isMutating = true
        activeControlAction = action
        errorMessage = nil
        Task {
            defer {
                isMutating = false
                activeControlAction = nil
            }
            do {
                let response = try await operation(api, guildId, queue?.version)
                applyQueueSnapshot(response, forcePresentationIdle: forcePresentationIdleOnSuccess)
            } catch { await handleMutationError(error) }
        }
    }

    private func handleMutationError(_ error: Error) async {
        if let apiError = error as? APIError,
           apiError.statusCode == 409 || apiError.problem?.errorCode == "queue_version_conflict",
           let guildId = selectedGuildId {
            if let fresh = try? await api.getQueue(guildId: guildId) {
                applyQueueSnapshot(fresh)
                errorMessage = String(localized: .queueChangedRefreshed)
                return
            }
        }
        errorMessage = userMessage(for: error)
    }

    private func applyQueueSnapshot(_ snapshot: QueueSnapshotResponse, forcePresentationIdle: Bool = false) {
        guard selectedGuildId == snapshot.guildId else { return }
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
                || activeControlAction == .skip
        }()

        queue = snapshot
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
            defaults.set(channel, forKey: Keys.channelId)
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
        index.reserveCapacity(favorites.count)
        for favorite in favorites {
            index[favoriteIdentity(favorite.contentUrl)] = favorite
        }
        favoriteByIdentity = index
    }

    private func cancelSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func addSearchHistory(_ value: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        searchHistory.insert(value, at: 0)
        if searchHistory.count > 8 { searchHistory.removeLast(searchHistory.count - 8) }
        defaults.set(searchHistory, forKey: Keys.searchHistory)
    }

    private func resetAuthenticatedState() {
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
        guildAccessState = .checking
        selectedGuildId = defaults.string(forKey: Keys.guildId)
        selectedVoiceChannelId = defaults.string(forKey: Keys.channelId)
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
        if let apiError = error as? APIError { return apiError.localizedDescription }
        if error is URLError { return String(localized: .networkUnavailable) }
        return error.localizedDescription
    }

    private enum Keys {
        static let guildId = "selection.guildId"
        static let channelId = "selection.voiceChannelId"
        static let searchHistory = "search.history"
        static let onboardingPrefix = "onboarding.completed."
        static let favoritesShufflePrefix = "favorites.shuffle."
    }
}
