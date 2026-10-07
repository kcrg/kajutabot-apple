import SwiftUI

enum AppTab: Hashable {
    case player
    case favorites
    case more
    case search
}

struct MainTabView: View {
    @Bindable var app: AppState
    @State private var selectedTab: AppTab = .player
    @State private var playerTransition = PlayerTransition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var showsMiniPlayer: Bool {
        app.nowPlaying != nil && selectedTab != .player && selectedTab != .search
    }

    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: selectTab)) {
            Tab(String(localized: .playerTitle), systemImage: "music.note.list", value: .player) {
                NavigationStack {
                    PlayerView(app: app) { selectTab(.search) }
                }
            }

            Tab(String(localized: .favoritesTitle), systemImage: "heart.text.square", value: .favorites) {
                NavigationStack {
                    FavoritesView(app: app)
                }
            }

            Tab(String(localized: .moreTitle), systemImage: "ellipsis", value: .more) {
                NavigationStack {
                    MoreView(app: app)
                }
            }

            Tab(value: .search, role: .search) {
                NavigationStack {
                    AddTrackView(app: app) {
                        selectTab(.player)
                    }
                }
            }
        }
        .sheet(item: $app.pendingSharedLink) { entry in SharedImportView(app: app, entry: entry) }
        .task { app.refreshSharedInbox() }
        .operationError(app)
        .tabViewSearchActivation(.searchTabSelection)
        .tabViewBottomAccessory(isEnabled: showsMiniPlayer) {
            MiniPlayerView(app: app) {
                selectTab(.player)
            }
        }
        .tabBarMinimizeBehavior(tabBarMinimizeBehavior)
        .environment(playerTransition)
        .overlay { PlayerTransitionOverlay(transition: playerTransition) }
        .onChange(of: app.presentationTrackRevision) { _, _ in playerTransition.cancel() }
        .onChange(of: app.nowPlaying?.id) { _, _ in playerTransition.cancel() }
        .onChange(of: app.selectedGuildId) { _, _ in playerTransition.cancel() }
        .onChange(of: app.pendingSharedLink?.id) { _, _ in playerTransition.cancel() }
        .onChange(of: reduceMotion) { _, _ in playerTransition.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playerTransition.cancel() }
        }
        .onDisappear { playerTransition.cancel() }
    }

    private func selectTab(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        playerTransition.begin(from: transitionLocation(selectedTab), to: transitionLocation(tab),
            track: app.nowPlaying, revision: app.presentationTrackRevision, reduceMotion: reduceMotion)
        if selectedTab == .search { app.clearAddTrack() }
        selectedTab = tab
    }

    private func transitionLocation(_ tab: AppTab) -> PlayerTransitionLocation? {
        switch tab {
        case .player: .player
        case .favorites, .more: .miniPlayer
        case .search: nil
        }
    }

    private var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        switch selectedTab {
        case .favorites, .more:
            return .onScrollDown
        case .player, .search:
            return .never
        }
    }
}
