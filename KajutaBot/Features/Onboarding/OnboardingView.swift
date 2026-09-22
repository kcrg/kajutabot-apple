import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: String
    let title: String
    let description: String
    let image: String
}

private let onboardingPages: [OnboardingPage] = [
    .init(id: "player", title: "Steruj tym, co gra na Discordzie", description: "Telefon działa jak pilot do KajutaBota na wybranym kanale głosowym. Widzisz aktualny utwór i postęp, możesz pominąć lub zatrzymać odtwarzanie, włączyć powtarzanie i zapisać utwór do ulubionych.", image: "onboarding_player"),
    .init(id: "queue", title: "Kolejka pod pełną kontrolą", description: "Zmieniaj kolejność utworów, usuwaj pojedyncze pozycje, wyczyść kolejkę albo szybko otwórz wyszukiwanie z poziomu odtwarzacza.", image: "onboarding_queue"),
    .init(id: "share", title: "Dodawaj muzykę na swój sposób", description: "Wpisz nazwę utworu albo wklej bezpośredni link. Wyniki możesz pobierać z YouTube, SoundCloud albo z bazy KajutaBota.", image: "onboarding_share"),
    .init(id: "favorites", title: "Ulubione zawsze pod ręką", description: "Zapisuj utwory na później, dodawaj je pojedynczo lub wrzuć wszystkie ulubione do kolejki naraz — również w losowej kolejności.", image: "onboarding_favorites"),
    .init(id: "radio", title: "Radio, gdy skończy się kolejka", description: "Gdy zwykła kolejka się opróżni, radio może automatycznie dobrać kolejny utwór z cache KajutaBota.", image: "onboarding_radio"),
    .init(id: "mini", title: "Sterowanie zostaje z Tobą", description: "Miniplayer pozostaje nad dolną nawigacją na pozostałych ekranach, więc aktualny utwór i szybkie akcje są zawsze pod ręką.", image: "onboarding_miniplayer"),
]

struct OnboardingView: View {
    @Bindable var app: AppState
    @State private var page = 0

    private var selectionIndex: Int { onboardingPages.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("KajutaBot")
                    .font(.title2.bold())
                Spacer()
                if app.manualOnboardingRequested && app.onboardingCompleted {
                    Button("Zamknij") { app.manualOnboardingRequested = false }
                } else if page < selectionIndex {
                    Button("Pomiń") { withAnimation(.snappy) { page = selectionIndex } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(onboardingPages.enumerated()), id: \.offset) { index, item in
                    FeaturePage(page: item, guestIntro: app.isGuest && index == 0)
                        .tag(index)
                }
                SelectionPage(app: app)
                    .tag(selectionIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(0...selectionIndex, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.snappy, value: page)
                }
            }
            .padding(.vertical, 14)

            HStack(spacing: 12) {
                if page > 0 {
                    Button("Wstecz") {
                        withAnimation(.snappy) { page -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                Button(page == selectionIndex ? (app.manualOnboardingRequested ? "Gotowe" : "Zaczynamy") : "Dalej") {
                    if page == selectionIndex {
                        app.completeOnboarding()
                    } else {
                        withAnimation(.snappy) { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(page == selectionIndex && !app.hasDiscordTarget)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }
}

private struct FeaturePage: View {
    let page: OnboardingPage
    let guestIntro: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Image(page.image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                .frame(maxWidth: 520, maxHeight: 330)
                .padding(.horizontal, 24)
            Spacer(minLength: 4)
            Text(guestIntro ? "Wypróbuj KajutaBota bez konta" : page.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(guestIntro ? "Tryb gościa daje dostęp do serwera demonstracyjnego i większości funkcji aplikacji bez logowania przez Discord." : page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 12)
        }
    }
}

private struct SelectionPage: View {
    @Bindable var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 16)
                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 92))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                Text("Gdzie chcesz sterować botem?")
                    .font(.title2.bold())
                Text(app.isGuest
                     ? "Serwer demonstracyjny jest już wybrany. Wybierz kanał głosowy; możesz go później zmienić z ekranu odtwarzacza."
                     : "Wybierz serwer Discord, a potem kanał głosowy. Ten wybór możesz później zmienić z ekranu odtwarzacza.")
                    .foregroundStyle(.secondary)
                DiscordTargetPicker(app: app, showGuildPicker: !app.isGuest)
            }
            .padding(.horizontal, 20)
        }
    }
}
