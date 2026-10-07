import SwiftUI

struct FavoritesView: View {
    let app: AppState

    var body: some View {
        List {
            if app.favorites.isEmpty && app.isLoadingFavorites {
                ProgressView { Text(.loading) }.frame(maxWidth: .infinity)
                    .trackListRow()
            } else if app.favorites.isEmpty {
                ContentUnavailableView {
                    Label(.noFavoritesTitle, systemImage: "heart")
                } description: { Text(.noFavoritesDescription) }
                    .trackListRow()
            } else {
                Section {
                    Button { app.queueAllFavorites() } label: {
                        Label {
                            Text(.favoritesAddAll(count: app.favorites.count))
                        } icon: {
                            ActionFeedback(status: app.actionStatuses["queue.favorites.all"],
                                symbol: "text.badge.plus", showsSuccess: true)
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(app.actionStatuses["queue.favorites.all"] == .pending)
                    .actionFeedbackAccessibility(app.actionStatuses["queue.favorites.all"], showsSuccess: true)
                    .trackListRow()
                    Toggle(String(localized: .shuffleOrder), isOn: Binding(get: { app.favoritesShuffle }, set: app.setFavoritesShuffle))
                        .trackListRow()
                }
                .listSectionSeparator(.hidden)
                Section {
                    ForEach(app.favorites) { favorite in row(favorite).trackListRow() }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.favoritesTitle)
        .refreshable { await app.refreshFavoritesNow() }
    }

    private func row(_ favorite: FavoriteResponse) -> some View {
        let identity = favoriteIdentity(favorite.contentUrl)
        let queueStatus = app.actionStatuses["queue.favorite." + identity]
        let deleteStatus = app.actionStatuses["favorite." + identity]
        let removing = deleteStatus == .pending || deleteStatus == .failure
        let rowStatus = removing ? deleteStatus : queueStatus
        return TrackListCard(artworkURL: favorite.thumbnailUrl, actionStatus: rowStatus,
            actionSymbol: removing ? "trash" : "text.badge.plus", confirmsAction: !removing) {
            if let url = URLInput.httpURL(favorite.contentUrl) {
                Link(favorite.title.isEmpty ? favorite.contentUrl : favorite.title, destination: url)
            } else {
                Text(favorite.title.isEmpty ? favorite.contentUrl : favorite.title)
            }
        } details: {
            if let date = app.favoriteSavedDate(for: favorite) {
                Text(.favoriteSaved(date: date.formatted(date: .numeric, time: .omitted)))
            }
        } trailing: {
            EmptyView()
        }
        .swipeActions(edge: .leading) {
            Button { app.playFavorite(favorite) } label: {
                Label {
                    Text(.addToQueue)
                } icon: { ActionFeedback(status: queueStatus, symbol: "text.badge.plus", showsSuccess: true) }
            }
            .tint(.accentColor).disabled(queueStatus == .pending || deleteStatus == .pending)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { app.deleteFavorite(favorite.contentUrl) } label: {
                Label {
                    Text(.removeFavorite)
                } icon: { ActionFeedback(status: deleteStatus, symbol: "trash") }
            }
            .tint(.red).disabled(deleteStatus == .pending)
        }
        .actionFeedbackAccessibility(rowStatus, showsSuccess: !removing)
        .accessibilityAction(named: Text(.addToQueue)) { app.playFavorite(favorite) }
        .accessibilityAction(named: Text(.removeFavorite)) { app.deleteFavorite(favorite.contentUrl) }
    }
}
