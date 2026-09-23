import SwiftUI

enum AppTab: Hashable {
    case player
    case favorites
    case more
    case search
}

struct MainTabView: View {
    let app: AppState
    @State private var selectedTab: AppTab = .player

    private var showsMiniPlayer: Bool {
        app.nowPlaying != nil && selectedTab != .player && selectedTab != .search
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(String(localized: .playerTitle), systemImage: "music.note.list", value: .player) {
                NavigationStack {
                    PlayerView(app: app)
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
                        selectedTab = .player
                    }
                }
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .tabViewBottomAccessory(isEnabled: showsMiniPlayer) {
            MiniPlayerView(app: app) {
                selectedTab = .player
            }
        }
        .tabBarMinimizeBehavior(tabBarMinimizeBehavior)
        .onChange(of: selectedTab) { previousTab, newTab in
            if previousTab == .search && newTab != .search {
                app.clearAddTrack()
            }
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
