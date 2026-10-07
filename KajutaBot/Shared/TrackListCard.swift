import SwiftUI

/// Shared geometry for queue entries, favorites and search results.
struct TrackListCard<Title: View, Details: View, Trailing: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let artworkURL: String?
    var position: Int? = nil
    var actionStatus: ActionStatus? = nil
    var actionSymbol = "text.badge.plus"
    var confirmsAction = true
    @ViewBuilder let title: () -> Title
    @ViewBuilder let details: () -> Details
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(urlString: artworkURL, layout: .square(64), cornerRadius: 12)
                .overlay(alignment: .bottomTrailing) {
                    ActionFeedback(status: actionStatus, symbol: actionSymbol, showsSuccess: confirmsAction)
                        .padding(3)
                        .background(.regularMaterial, in: Circle())
                        .opacity(actionStatus == nil ? 0 : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: actionStatus)
                        .allowsHitTesting(false)
                }
            VStack(alignment: .leading, spacing: 4) {
                title().font(.body).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                details().font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, position == nil ? 0 : 16)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            if let position {
                Text(verbatim: "\(position)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .accessibilityLabel(Text(.queuePosition(position: position)))
            }
        }
    }
}

private struct TrackListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    func trackListRow() -> some View { modifier(TrackListRow()) }
}
