import AuthenticationServices
import Foundation
import Observation
import SwiftUI

enum AppAuthState: Equatable {
    case restoring
    case signedOut(String? = nil)
    case signedIn(AuthUserResponse)
    case recoverableError(String)
}

enum GuildAccessState {
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
    private var initialized = false
    private var session: UserSession?
    private var presentationRecoveryTask: Task<Void, Never>?
    private var presentationIdleTask: Task<Void, Never>?

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
    var isMutating = false
    var activeControlAction: PlayerControlAction?
    var errorMessage: String?
    var noticeMessage: String?

    var searchQuery = ""
    var searchSource: SearchSourceOption = .youtube
    var searchResults: [SearchItemResponse] = []
    var searchHistory: [String] = []
    var isSearching = false

    var favorites: [FavoriteResponse] = []
    var isLoadingFavorites = false
    var isMutatingFavorites = false
    var favoritesShuffle = false

    var manualOnboardingRequested = false

    var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = AppConfig()
        let authAPI = AuthAPIClient(baseURL: config.apiBaseURL)
        let manager = SessionManager(store: KeychainSessionStore(), authAPI: authAPI)
        sessionManager = manager
        api = KajutaBotAPIClient(baseURL: config.apiBaseURL, sessionManager: manager)
        realtime = RealtimeClient(baseURL: config.apiBaseURL) {
            try await manager.accessToken()
        }
        selectedGuildId = defaults.string(forKey: Keys.guildId)
        selectedVoiceChannelId = defaults.string(forKey: Keys.channelId)
        searchHistory = defaults.stringArray(forKey: Keys.searchHistory) ?? []
        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
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
    var nowPlaying: TrackResponse? { presentationQueue?.nowPlaying }

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var shouldShowOnboarding: Bool {
        guard session != nil, guildAccessState == .available else { return false }
        return manualOnboardingRequested || !onboardingCompleted
    }

    var onboardingCompleted: Bool {
        guard let session else { return false }
        return defaults.bool(forKey: onboardingKey(for: session))
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
            authState = .signedIn(restored.user)
            favoritesShuffle = defaults.bool(forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
            await bootstrapAuthenticatedState()
        } catch {
            authState = .recoverableError("Nie można odczytać bezpiecznego magazynu sesji.")
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
                authState = .signedOut("Logowanie przez Discord zostało anulowane.")
            } catch OAuthError.cancelled {
                authState = .signedOut("Logowanie przez Discord zostało anulowane.")
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
                errorMessage = "Serwer nie potwierdził wylogowania. Sesja pozostała aktywna."
                if let session { authState = .signedIn(session.user) }
            }
        }
    }

    func sceneBecameActive() {
        guard case .signedIn = authState else { return }
        if let guildId = selectedGuildId { realtime.connect(guildId: guildId) }
    }

    func sceneBecameInactive() {
        realtime.stop()
    }

    func completeOnboarding() {
        guard let session else { return }
        defaults.set(true, forKey: onboardingKey(for: session))
        manualOnboardingRequested = false
    }

    func refreshGuilds() {
        Task { await loadGuilds() }
    }

    func selectGuild(_ guildId: String) {
        guard selectedGuildId != guildId else { return }
        selectedGuildId = guildId
        selectedVoiceChannelId = nil
        defaults.set(guildId, forKey: Keys.guildId)
        defaults.removeObject(forKey: Keys.channelId)
        queue = nil
        presentationQueue = nil
        cancelPresentationRecovery()
        realtime.connect(guildId: guildId)
        Task {
            await loadVoiceChannels(guildId: guildId, preserveChannel: nil)
            await refreshQueueAsync(guildId: guildId)
        }
    }

    func selectVoiceChannel(_ channelId: String) {
        selectedVoiceChannelId = channelId
        defaults.set(channelId, forKey: Keys.channelId)
    }

    func refreshQueue() {
        guard let guildId = selectedGuildId else { return }
        Task { await refreshQueueAsync(guildId: guildId) }
    }

    func dismissMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    func setSearchSource(_ source: SearchSourceOption) {
        searchSource = source
        searchResults = []
    }

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        if looksLikeURL(query) {
            enqueueInputs([query])
            return
        }
        isSearching = true
        errorMessage = nil
        addSearchHistory(query)
        Task {
            defer { isSearching = false }
            do {
                let response = try await api.search(query: query, source: searchSource)
                searchResults = response.items
            } catch {
                errorMessage = userMessage(for: error)
            }
        }
    }

    func searchFromHistory(_ query: String) {
        searchQuery = query
        performSearch()
    }

    func clearAddTrack() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    func enqueueSearchResult(_ item: SearchItemResponse) {
        enqueueInputs([item.input])
    }

    func enqueueInputs(_ inputs: [String]) {
        guard let guildId = selectedGuildId, let channelId = selectedVoiceChannelId else {
            errorMessage = "Najpierw wybierz serwer i kanał głosowy."
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
                applyQueueSnapshot(response.snapshot)
                if response.operation.succeeded {
                    noticeMessage = "Dodano do kolejki."
                } else {
                    errorMessage = response.operation.message ?? "Nie udało się dodać utworu."
                }
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
        performControl(.repeatTrack, successMessage: enabled ? "Powtarzanie włączone" : "Powtarzanie wyłączone") { api, guildId, version in
            try await api.setRepeat(guildId: guildId, request: SetQueueRepeatRequest(isEnabled: enabled, expectedVersion: version))
        }
    }

    func toggleRadio() {
        guard let queue else { return }
        if queue.radio.isEnabled {
            performControl(.radio, successMessage: "Radio wyłączone", forcePresentationIdleOnSuccess: true) { api, guildId, version in
                try await api.disableRadio(guildId: guildId, expectedVersion: version)
            }
            return
        }
        guard let channelId = selectedVoiceChannelId else {
            errorMessage = "Najpierw wybierz serwer i kanał głosowy."
            return
        }
        let minDuration = queue.radio.minimumDurationSeconds ?? 60
        let maxDuration = queue.radio.maximumDurationSeconds ?? 600
        performControl(.radio, successMessage: "Radio włączone", forcePresentationIdleOnSuccess: true) { api, guildId, version in
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
                applyQueueSnapshot(response.snapshot)
                if !response.operation.succeeded { errorMessage = response.operation.message ?? "Nie udało się usunąć utworu." }
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
                    request: MoveQueueEntryRequest(entryId: moved.entryId, newPosition: newPosition, expectedVersion: current.version)
                )
                applyQueueSnapshot(response.snapshot)
                if !response.operation.succeeded {
                    errorMessage = response.operation.message ?? "Nie udało się zmienić pozycji utworu."
                }
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

    func setFavoritesShuffle(_ enabled: Bool) {
        favoritesShuffle = enabled
        defaults.set(enabled, forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
        noticeMessage = enabled ? "Losowanie włączone" : "Losowanie wyłączone"
    }

    func isFavorite(_ track: TrackResponse) -> Bool {
        let identities = favoriteIdentities(for: track)
        return favorites.contains { identities.contains(favoriteIdentity($0.contentUrl)) }
    }

    func toggleFavorite(_ track: TrackResponse) {
        let identities = favoriteIdentities(for: track)
        if let existing = favorites.first(where: { identities.contains(favoriteIdentity($0.contentUrl)) }) {
            deleteFavorite(existing.contentUrl)
        } else {
            addFavorite(contentURL: track.url, title: track.title, thumbnailURL: track.thumbnailUrl)
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
                noticeMessage = "Usunięto z ulubionych."
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    func playFavorite(_ favorite: FavoriteResponse) {
        enqueueInputs([favorite.contentUrl])
    }

    func queueAllFavorites() {
        guard let guildId = selectedGuildId, let channelId = selectedVoiceChannelId else {
            errorMessage = "Wybierz serwer i kanał głosowy w Odtwarzaczu, aby dodać ulubione."
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
                applyQueueSnapshot(response.snapshot)
                if response.operation.succeeded { noticeMessage = "Dodano ulubione do kolejki." }
                else { errorMessage = response.operation.message ?? "Nie udało się dodać ulubionych." }
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    private func finishSignIn(_ newSession: UserSession) async {
        session = newSession
        authState = .signedIn(newSession.user)
        favoritesShuffle = defaults.bool(forKey: Keys.favoritesShufflePrefix + favoritesOwnerKey)
        await bootstrapAuthenticatedState()
    }

    private func bootstrapAuthenticatedState() async {
        await loadGuilds()
        await refreshFavoritesAsync()
    }

    private func loadGuilds() async {
        isLoadingGuilds = true
        guildAccessState = .checking
        guildAccessError = nil
        defer { isLoadingGuilds = false }
        do {
            let loaded = try await api.getMyGuilds()
            guilds = loaded.filter(\.isAvailable)
            guard !guilds.isEmpty else {
                selectedGuildId = nil
                selectedVoiceChannelId = nil
                queue = nil
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
                await loadVoiceChannels(guildId: guildId, preserveChannel: selectedVoiceChannelId)
                await refreshQueueAsync(guildId: guildId)
            }
        } catch {
            guildAccessState = .error
            guildAccessError = userMessage(for: error)
        }
    }

    private func loadVoiceChannels(guildId: String, preserveChannel: String?) async {
        isLoadingVoiceChannels = true
        defer { isLoadingVoiceChannels = false }
        do {
            let channels = try await api.getVoiceChannels(guildId: guildId).sorted { lhs, rhs in
                lhs.position == rhs.position ? lhs.name < rhs.name : lhs.position < rhs.position
            }
            voiceChannels = channels
            var channel = preserveChannel
            if channel != nil && !channels.contains(where: { $0.id == channel! }) { channel = nil }
            if channel == nil, channels.count == 1 { channel = channels[0].id }
            selectedVoiceChannelId = channel
            if let channel { defaults.set(channel, forKey: Keys.channelId) }
            else { defaults.removeObject(forKey: Keys.channelId) }
        } catch {
            voiceChannels = []
            selectedVoiceChannelId = nil
            errorMessage = userMessage(for: error)
        }
    }

    private func refreshQueueAsync(guildId: String) async {
        isLoadingQueue = true
        defer { isLoadingQueue = false }
        do {
            let snapshot = try await api.getQueue(guildId: guildId)
            applyQueueSnapshot(snapshot)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func refreshFavoritesAsync() async {
        isLoadingFavorites = true
        defer { isLoadingFavorites = false }
        do { favorites = try await api.getFavorites() }
        catch { errorMessage = userMessage(for: error) }
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
                noticeMessage = "Dodano do ulubionych."
            } catch { errorMessage = userMessage(for: error) }
        }
    }

    private func performControl(
        _ action: PlayerControlAction?,
        successMessage: String? = nil,
        forcePresentationIdleOnSuccess: Bool = false,
        operation: @escaping (KajutaBotAPIClient, String, Int64?) async throws -> QueueMutationResponse
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
                applyQueueSnapshot(response.snapshot, forcePresentationIdle: forcePresentationIdleOnSuccess)
                if response.operation.succeeded { noticeMessage = successMessage }
                else { errorMessage = response.operation.message ?? "Operacja nie powiodła się." }
            } catch { await handleMutationError(error) }
        }
    }

    private func handleMutationError(_ error: Error) async {
        if let apiError = error as? APIError,
           apiError.statusCode == 409 || apiError.problem?.errorCode == "queue_version_conflict",
           let guildId = selectedGuildId {
            if let fresh = try? await api.getQueue(guildId: guildId) {
                applyQueueSnapshot(fresh)
                errorMessage = "Kolejka zmieniła się w międzyczasie. Odświeżono stan."
                return
            }
        }
        errorMessage = userMessage(for: error)
    }

    private func applyQueueSnapshot(_ snapshot: QueueSnapshotResponse, forcePresentationIdle: Bool = false) {
        guard selectedGuildId == snapshot.guildId else { return }
        if let current = queue, snapshot.version < current.version { return }

        let previousQueue = queue
        let previousPresentation = presentationQueue
        queue = snapshot

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

    private func addSearchHistory(_ value: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        searchHistory.insert(value, at: 0)
        if searchHistory.count > 8 { searchHistory.removeLast(searchHistory.count - 8) }
        defaults.set(searchHistory, forKey: Keys.searchHistory)
    }

    private func resetAuthenticatedState() {
        session = nil
        guilds = []
        voiceChannels = []
        queue = nil
        presentationQueue = nil
        cancelPresentationRecovery()
        favorites = []
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
            let message = "Sesja wygasła. Zaloguj się ponownie."
            realtime.stop()
            resetAuthenticatedState()
            authState = .signedOut(message)
            return message
        }
        if let apiError = error as? APIError { return apiError.localizedDescription }
        if error is URLError { return "Brak połączenia z serwerem. Spróbuj ponownie." }
        return error.localizedDescription
    }

    private enum Keys {
        static let guildId = "selection.guildId"
        static let channelId = "selection.voiceChannelId"
        static let searchHistory = "search.history"
        static let themeMode = "theme.mode"
        static let onboardingPrefix = "onboarding.completed."
        static let favoritesShufflePrefix = "favorites.shuffle."
    }
}
