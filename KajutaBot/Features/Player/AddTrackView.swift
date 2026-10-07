import SwiftUI

struct AddTrackView: View {
    @Bindable var app: AppState
    let queued: () -> Void
    @State private var submission: Task<Void, Never>?

    private var query: String { app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isURL: Bool { URLInput.firstURL(in: query) != nil }

    var body: some View {
        List {
            if !app.isSearching && query.isEmpty && !app.searchHistory.isEmpty {
                Section(.recentSearches) {
                    ForEach(Array(app.searchHistory), id: \.self) { query in
                        Button { app.searchFromHistory(query) } label: {
                            Label(query, systemImage: "clock.arrow.circlepath").foregroundStyle(Color.primary)
                        }
                        .trackListRow()
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !app.isSearching && app.lastCompletedSearchQuery == query && !app.searchResults.isEmpty {
                Section(.results) {
                    ForEach(app.searchResults) { item in
                        result(item).trackListRow()
                    }
                }
                .listSectionSeparator(.hidden)
            } else if !app.isSearching && app.lastCompletedSearchQuery == query && !query.isEmpty && !isURL {
                ContentUnavailableView {
                    Label(.noResultsTitle, systemImage: "magnifyingglass")
                } description: { Text(.noResultsForQuery(query: query)) }
                    .trackListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if app.isSearching { SearchLoadingView(source: app.searchSource.displayName) }
        }
        .navigationTitle(.addTrackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $app.searchQuery, prompt: Text(.searchPrompt))
        .searchScopes(Binding(get: { app.searchSource }, set: app.setSearchSource), activation: .onSearchPresentation) {
            ForEach(SearchSourceOption.allCases) { source in
                Text(source.displayName).tag(source)
            }
        }
        .onSubmit(of: .search) { submit() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isURL ? String(localized: .add) : String(localized: .search), action: submit)
                    .disabled(query.isEmpty || app.isSearching || app.actionStatuses["queue.enqueue"] == .pending)
            }
        }
        .onDisappear { submission?.cancel() }
    }

    private func result(_ item: SearchItemResponse) -> some View {
        let key = "queue.search." + item.id
        let favorite = app.isFavorite(item.track)
        let favoriteStatus = app.actionStatuses[app.favoriteActionKey(for: item.track)]
        return TrackListCard(artworkURL: item.track.artworkUrl, actionStatus: app.actionStatuses[key]) {
            Text(item.track.title)
        } details: {
            if let date = item.dateLabel, !date.isEmpty { Text(date) }
            Text("\(item.metricCount.formatted()) \(item.metricCaption)")
            Text(verbatim: formatDuration(item.track.durationMilliseconds))
        } trailing: {
            FavoriteButton(isFavorite: favorite, status: favoriteStatus, isDisabled: app.isLoadingFavorites) {
                app.toggleFavorite(item.track)
            }
        }
        .swipeActions(edge: .leading) {
            Button { add(item) } label: {
                Label {
                    Text(.addToQueue)
                } icon: { ActionFeedback(status: app.actionStatuses[key], symbol: "text.badge.plus", showsSuccess: true) }
            }
                .tint(.accentColor).disabled(app.actionStatuses[key] == .pending)
        }
        .actionFeedbackAccessibility(app.actionStatuses[key], showsSuccess: true)
        .accessibilityAction(named: Text(.addToQueue)) { add(item) }
    }

    private func add(_ item: SearchItemResponse) {
        Task { _ = await app.enqueueSearchResult(item) }
    }

    private func submit() {
        submission?.cancel()
        submission = Task {
            let completed = await app.submitSearchInput()
            if completed && !Task.isCancelled { queued() }
        }
    }
}

private struct SearchLoadingView: View {
    let source: LocalizedStringResource

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(.searching).font(.headline).foregroundStyle(Color.primary)
                Text(source).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(.inProgress))
        .allowsHitTesting(false)
    }
}
