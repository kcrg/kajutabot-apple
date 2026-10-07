import SwiftUI

struct AddTrackView: View {
    @Bindable var app: AppState
    let queued: () -> Void
    @State private var submission: Task<Void, Never>?

    private var query: String { app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isURL: Bool { URLInput.firstURL(in: query) != nil }

    var body: some View {
        List {
            Section {
                Picker(String(localized: .searchSource), selection: Binding(
                    get: { app.searchSource }, set: { app.setSearchSource($0) }
                )) {
                    ForEach(SearchSourceOption.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }
            if query.isEmpty && !app.searchHistory.isEmpty {
                Section(.recentSearches) {
                    ForEach(Array(app.searchHistory), id: \.self) { query in
                        Button { app.searchFromHistory(query) } label: {
                            Label(query, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                        }
                    }
                }
            }
            if app.isSearching {
                Section { ProgressView { Text(.searching) }.frame(maxWidth: .infinity) }
            } else if app.lastCompletedSearchQuery == query && !app.searchResults.isEmpty {
                Section(.results) {
                    ForEach(app.searchResults) { item in
                        result(item).trackListRow()
                    }
                }
            } else if app.lastCompletedSearchQuery == query && !query.isEmpty && !isURL {
                ContentUnavailableView {
                    Label(.noResultsTitle, systemImage: "magnifyingglass")
                } description: { Text(.noResultsForQuery(query: query)) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.addTrackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $app.searchQuery, prompt: Text(.searchPrompt))
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
            Button { app.toggleFavorite(item.track) } label: {
                ActionFeedback(status: favoriteStatus, symbol: favorite ? "heart.fill" : "heart")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingFavorites || favoriteStatus == .pending)
            .actionFeedbackAccessibility(favoriteStatus)
            .accessibilityLabel(Text(favorite ? String(localized: .removeFavorite) : String(localized: .addFavorite)))
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
