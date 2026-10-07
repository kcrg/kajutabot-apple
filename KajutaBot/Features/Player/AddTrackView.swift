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
                        result(item)
                    }
                }
            } else if app.lastCompletedSearchQuery == query && !query.isEmpty && !isURL {
                ContentUnavailableView {
                    Label(.noResultsTitle, systemImage: "magnifyingglass")
                } description: { Text(.noResultsForQuery(query: query)) }
            }
        }
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
        return HStack(spacing: 12) {
            ArtworkView(urlString: item.track.artworkUrl, layout: .square(60), cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.track.title).lineLimit(2)
                if let date = item.dateLabel, !date.isEmpty { Text(date).font(.caption).foregroundStyle(.secondary) }
                Text("\(item.metricCount.formatted()) \(item.metricCaption)").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: formatDuration(item.track.durationMilliseconds)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { app.toggleFavorite(item.track) } label: {
                ActionFeedback(status: app.actionStatuses[app.favoriteActionKey(for: item.track)], symbol: favorite ? "heart.fill" : "heart")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(app.isLoadingFavorites || app.actionStatuses[app.favoriteActionKey(for: item.track)] == .pending)
            .accessibilityLabel(Text(favorite ? String(localized: .removeFavorite) : String(localized: .addFavorite)))
            Button { add(item) } label: {
                ActionFeedback(status: app.actionStatuses[key], symbol: "text.badge.plus").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(app.actionStatuses[key] == .pending)
            .accessibilityLabel(Text(.addToQueue))
            .actionFeedbackAccessibility(app.actionStatuses[key])
        }
        .swipeActions(edge: .leading) {
            Button { add(item) } label: { Label(.addToQueue, systemImage: "text.badge.plus") }
                .tint(.accentColor).disabled(app.actionStatuses[key] == .pending)
        }
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
