import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    let symbol: String
}

private let onboardingPages: [OnboardingPage] = [
    .init(
        id: "player",
        title: .onboardingPlayerTitle,
        description: .onboardingPlayerDescription,
        symbol: "play.circle.fill"
    ),
    .init(
        id: "search",
        title: .onboardingSearchTitle,
        description: .onboardingSearchDescription,
        symbol: "magnifyingglass.circle.fill"
    ),
    .init(
        id: "favorites",
        title: .onboardingFavoritesTitle,
        description: .onboardingFavoritesDescription,
        symbol: "heart.circle.fill"
    ),
]

struct OnboardingView: View {
    let app: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private var selectionIndex: Int { onboardingPages.count }
    private var showsBackButton: Bool { page > 0 }
    private var isLastPage: Bool { page == selectionIndex }
    private var isManualGuide: Bool { app.manualOnboardingRequested && app.onboardingCompleted }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(onboardingPages.enumerated()), id: \.element.id) { index, item in
                        FeaturePage(page: item, showsGuestNote: app.isGuest && index == 0)
                            .tag(index)
                    }

                    SelectionPage(app: app)
                        .tag(selectionIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                navigationButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
            }
            .navigationTitle(isManualGuide ? String(localized: .guideTitle) : "KajutaBot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isManualGuide {
                        Button(.done) {
                            performAnimated {
                                app.manualOnboardingRequested = false
                            }
                        }
                    } else if page < selectionIndex {
                        Button(.configure) {
                            setPage(selectionIndex)
                        }
                    }
                }
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button {
                    setPage(page - 1)
                } label: {
                    Label(.back, systemImage: "chevron.left")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }

            Button {
                if isLastPage {
                    performAnimated {
                        app.completeOnboarding()
                    }
                } else {
                    setPage(page + 1)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(isLastPage ? (isManualGuide ? String(localized: .done) : String(localized: .getStarted)) : String(localized: .next))
                    Image(systemName: isLastPage ? "checkmark" : "chevron.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(isLastPage && !app.hasDiscordTarget)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.28), value: showsBackButton)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.24), value: isLastPage)
    }

    private func setPage(_ newPage: Int) {
        performAnimated {
            page = newPage
        }
    }

    private func performAnimated(_ changes: @escaping () -> Void) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.28)) {
            changes()
        }
    }
}

private struct FeaturePage: View {
    let page: OnboardingPage
    let showsGuestNote: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 18)

                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    Image(systemName: page.symbol)
                        .font(.system(size: 78, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: 520)

                VStack(spacing: 10) {
                    Text(page.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(page.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if showsGuestNote {
                        Label(.guestDemoNote, systemImage: "person.crop.circle.badge.checkmark")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 560)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .adaptiveContentWidth(AppLayout.onboardingContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SelectionPage: View {
    let app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 18)

                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 82))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text(.targetQuestion)
                    .font(.title2.bold())

                Text(app.isGuest ? String(localized: .guestTargetDescription) : String(localized: .discordTargetDescription))
                    .foregroundStyle(.secondary)

                DiscordTargetPicker(app: app, showGuildPicker: !app.isGuest)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
