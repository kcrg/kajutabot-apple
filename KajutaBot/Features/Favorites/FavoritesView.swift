import SwiftUI

struct FavoritesView: View {
    @Bindable var app: AppState
    @State private var showAddFavorite = false
    @State private var newFavoriteURL = ""
    @State private var addTask: Task<Void, Never>?

    var body: some View {
        List {
            if app.favorites.isEmpty && app.isLoadingFavorites {
                ProgressView { Text(.loading) }.frame(maxWidth: .infinity)
            } else if app.favorites.isEmpty {
                ContentUnavailableView {
                    Label(.noFavoritesTitle, systemImage: "heart")
                } description: { Text(.noFavoritesDescription) }
            } else {
                Section {
                    Button { app.queueAllFavorites() } label: {
                        Label {
                            Text(.favoritesAddAll(count: app.favorites.count))
                        } icon: { ActionFeedback(status: app.actionStatuses["queue.favorites.all"], symbol: "text.badge.plus") }
                    }
                    .disabled(app.actionStatuses["queue.favorites.all"] == .pending)
                    Toggle(String(localized: .shuffleOrder), isOn: Binding(get: { app.favoritesShuffle }, set: app.setFavoritesShuffle))
                }
                Section {
                    ForEach(app.favorites) { favorite in row(favorite) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.favoritesTitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { app.refreshFavorites() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(app.isLoadingFavorites).accessibilityLabel(Text(.refresh))
                Button { app.dismissError(); showAddFavorite = true } label: { Image(systemName: "heart.badge.plus") }
                    .accessibilityLabel(Text(.addByURL))
            }
        }
        .refreshable { await app.refreshFavoritesNow() }
        .sheet(isPresented: $showAddFavorite) {
            NavigationStack {
                Form {
                    TextField(String(localized: .trackLink), text: $newFavoriteURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("favoriteURLHelp").font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle(.addToFavoritesTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(.cancel) { showAddFavorite = false }.disabled(app.isMutatingFavorites) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.add) {
                            addTask = Task {
                                if await app.addFavoriteByURL(newFavoriteURL), !Task.isCancelled {
                                    newFavoriteURL = ""
                                    showAddFavorite = false
                                }
                            }
                        }
                        .disabled(newFavoriteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isMutatingFavorites)
                    }
                }
                .operationError(app)
            }
            .interactiveDismissDisabled(app.isMutatingFavorites)
            .presentationDetents([.medium, .large])
            .onDisappear { addTask?.cancel() }
        }
    }

    private func row(_ favorite: FavoriteResponse) -> some View {
        let identity = favoriteIdentity(favorite.contentUrl)
        let queueKey = "queue.favorite." + identity
        let deleteKey = "favorite." + identity
        return HStack(spacing: 12) {
            ArtworkView(urlString: favorite.thumbnailUrl, layout: .square(60), cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                if let url = URLInput.firstURL(in: favorite.contentUrl) {
                    Link(favorite.title, destination: url).lineLimit(2)
                } else { Text(favorite.title).lineLimit(2) }
                if let date = parseISO8601(favorite.addedAt) {
                    Text(.favoriteSaved(date: date.formatted(date: .numeric, time: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button { app.playFavorite(favorite) } label: {
                ActionFeedback(status: app.actionStatuses[queueKey], symbol: "text.badge.plus")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless).disabled(app.actionStatuses[queueKey] == .pending)
            .accessibilityLabel(Text(.addToQueue))
            .actionFeedbackAccessibility(app.actionStatuses[queueKey])
            if app.actionStatuses[deleteKey] != nil {
                ActionFeedback(status: app.actionStatuses[deleteKey], symbol: "heart")
            }
        }
        .swipeActions(edge: .leading) {
            Button { app.playFavorite(favorite) } label: { Label(.addToQueue, systemImage: "text.badge.plus") }
                .tint(.accentColor).disabled(app.actionStatuses[queueKey] == .pending)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { app.deleteFavorite(favorite.contentUrl) } label: { Label(.removeFavorite, systemImage: "trash") }
                .tint(.red).disabled(app.actionStatuses[deleteKey] == .pending)
        }
        .contextMenu {
            Button { app.playFavorite(favorite) } label: { Label(.addToQueue, systemImage: "text.badge.plus") }
            Button(role: .destructive) { app.deleteFavorite(favorite.contentUrl) } label: { Label(.removeFavorite, systemImage: "trash") }
        }
        .accessibilityAction(named: Text(.addToQueue)) { app.playFavorite(favorite) }
        .accessibilityAction(named: Text(.removeFavorite)) { app.deleteFavorite(favorite.contentUrl) }
    }
}
