import SwiftUI

struct FavoritesView: View {
    let app: AppState
    @State private var newFavoriteURL = ""
    @State private var showAddFavorite = false

    var body: some View {
        List {
            if app.favorites.isEmpty && app.isLoadingFavorites {
                ForEach(0..<5, id: \.self) { _ in
                    FavoriteSkeletonRow()
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if app.favorites.isEmpty {
                ContentUnavailableView {
                    Label(.noFavoritesTitle, systemImage: "heart")
                } description: {
                    Text(.noFavoritesDescription)
                }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(app.favorites) { favorite in
                    FavoriteRow(app: app, favorite: favorite)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.favoritesTitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { app.refreshFavorites() } label: { Image(systemName: "arrow.clockwise") }
                Menu {
                    Toggle(String(localized: .shuffleOrder), isOn: Binding(
                        get: { app.favoritesShuffle },
                        set: app.setFavoritesShuffle
                    ))
                    Button {
                        app.queueAllFavorites()
                    } label: {
                        Label(.favoritesAddAll(count: app.favorites.count), systemImage: "text.badge.plus")
                    }
                    .disabled(app.favorites.isEmpty || app.isMutatingFavorites)
                    Divider()
                    Button { showAddFavorite = true } label: {
                        Label(.addByURL, systemImage: "heart.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await app.refreshFavoritesNow() }
        .sheet(isPresented: $showAddFavorite) {
            NavigationStack {
                Form {
                    Section(.trackLink) {
                        ZStack(alignment: .leading) {
                            if newFavoriteURL.isEmpty {
                                Text(verbatim: "https://youtube.com/…")
                                    .foregroundStyle(.primary.opacity(0.62))
                                    .allowsHitTesting(false)
                            }

                            TextField("", text: $newFavoriteURL)
                                .foregroundStyle(.primary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .accessibilityLabel(Text(.trackLink))
                        }
                    }
                }
                .navigationTitle(.addToFavoritesTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(.cancel) { showAddFavorite = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.add) {
                            app.addFavoriteByURL(newFavoriteURL)
                            newFavoriteURL = ""
                            showAddFavorite = false
                        }
                        .disabled(newFavoriteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct FavoriteRow: View {
    let app: AppState
    let favorite: FavoriteResponse

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                urlString: favorite.thumbnailUrl,
                layout: .square(64),
                cornerRadius: 10
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(favorite.title)
                    .lineLimit(2)
                if let date = parseISO8601(favorite.addedAt) {
                    Text(.favoriteSaved(date: date.formatted(date: .numeric, time: .omitted)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button { app.playFavorite(favorite) } label: {
                Image(systemName: "text.badge.plus")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(.addToQueue))

            Button(role: .destructive) { app.deleteFavorite(favorite.contentUrl) } label: {
                Image(systemName: "trash")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(.removeFavorite))
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .contextMenu {
            if let url = URL(string: favorite.contentUrl) {
                Link(destination: url) { Label(.openSource, systemImage: "safari") }
            }
        }
    }
}

private struct FavoriteSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 12)
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .redacted(reason: .placeholder)
    }
}
