import SwiftUI

struct AddTrackView: View {
    let app: AppState
    let queued: () -> Void

    private var trimmedQuery: String { app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isURL: Bool {
        let lower = trimmedQuery.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    var body: some View {
        List {
            Section {
                Picker(String(localized: .searchSource), selection: Binding(
                    get: { app.searchSource },
                    set: { app.setSearchSource($0) }
                )) {
                    ForEach(SearchSourceOption.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !app.searchHistory.isEmpty && trimmedQuery.isEmpty {
                Section(.recentSearches) {
                    ForEach(Array(app.searchHistory), id: \.self) { query in
                        Button {
                            app.searchFromHistory(query)
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if app.isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView { Text(.searching) }
                        Spacer()
                    }
                    .padding(.vertical, 22)
                }
            } else if app.lastCompletedSearchQuery == trimmedQuery && !app.searchResults.isEmpty {
                Section(.results) {
                    ForEach(app.searchResults) { item in
                        SearchResultRow(item: item) {
                            app.enqueueSearchResult(item)
                            queued()
                        }
                    }
                }
            } else if app.lastCompletedSearchQuery == trimmedQuery && !trimmedQuery.isEmpty && !isURL {
                Section {
                    ContentUnavailableView {
                        Label(.noResultsTitle, systemImage: "magnifyingglass")
                    } description: {
                        Text(.noResultsForQuery(query: trimmedQuery))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .adaptiveContentWidth(AppLayout.primaryContentMaxWidth)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(.addTrackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: Binding(
                get: { app.searchQuery },
                set: { app.searchQuery = $0 }
            ), prompt: Text(.searchPrompt))
        .onSubmit(of: .search) {
            app.performSearch()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isURL ? String(localized: .add) : String(localized: .search)) {
                    app.performSearch()
                    if isURL {
                        queued()
                    }
                }
                .disabled(trimmedQuery.isEmpty || app.isSearching || app.isMutating)
            }
        }
    }
}

private struct SearchResultRow: View {
    let item: SearchItemResponse
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(urlString: item.track.artworkUrl, layout: .square(60), cornerRadius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.track.title)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(formatDuration(item.track.durationMilliseconds))
                    Text(item.metricCaption)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: add) {
                Image(systemName: "text.badge.plus")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(.addToQueue))
        }
        .padding(.vertical, 4)
    }
}
