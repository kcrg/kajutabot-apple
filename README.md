# KajutaBot for iOS

Natywny klient KajutaBot w SwiftUI, przeniesiony funkcjonalnie z aplikacji Android/Kotlin.

## Wymagania

- Xcode 26.3+
- iOS 26.2+ (zgodnie z ustawieniem utworzonego projektu)
- działający KajutaBot Control API

## Konfiguracja

W targetcie **KajutaBot → Build Settings → User-Defined** ustaw:

- `KAJUTABOT_API_BASE_URL` — domyślnie `https://api.kajuta.tryniecki.eu`
- `KAJUTABOT_DISCORD_CLIENT_ID` — Client ID aplikacji Discord

Redirect URI używany przez iOS ma postać:

`discord-<CLIENT_ID>:/authorize/callback`

Ten sam redirect URI musi być dozwolony w konfiguracji OAuth aplikacji Discord i po stronie backendu.

Własne wartości runtime są deklarowane w `Config/Info.plist` jako `$(KAJUTABOT_...)`. Xcode rozwija je z Build Settings i scala z generowanym Info.plist targetu. Nie używamy własnych `INFOPLIST_KEY_KAJUTABOT_*`, ponieważ Xcode nie generuje dowolnych user-defined kluczy tym mechanizmem.

## Zaimplementowane

- Discord OAuth 2.0 + PKCE przez `ASWebAuthenticationSession`
- logowanie jako gość
- Keychain dla sesji i automatyczne odświeżanie tokenów
- wybór serwera Discord i kanału głosowego
- player: now playing, progress, stop, skip, repeat, radio
- kolejka: usuwanie, czyszczenie i zmiana kolejności
- wyszukiwanie YouTube / SoundCloud / bazy oraz dodawanie URL
- ulubione, shuffle i dodawanie całej listy
- miniplayer nad dolną nawigacją
- oficjalny klient Microsoft `SignalRClient` z `QueueUpdated`, heartbeatami i automatycznym reconnectem
- onboarding z grafikami przeniesionymi z projektu Android
- jasny / ciemny / systemowy motyw
- diagnostyka połączenia realtime

## Struktura

- `Core/Auth` — OAuth, Keychain, sesja/token refresh
- `Core/Networking` — REST API
- `Core/Realtime` — warstwa domenowa nad oficjalnym klientem SignalR
- `Core/Models` — kontrakty API
- `Features/*` — ekrany iOS/SwiftUI
- `Shared` — wspólne komponenty UI

Warstwa aplikacyjna korzysta głównie z frameworków systemowych Apple. Zewnętrzne zależności przez Swift Package Manager to **Nuke/NukeUI 13.x** do ładowania i cache obrazów (`LazyImage`) oraz oficjalny **Microsoft SignalRClient 1.0.x** do realtime.

## Różnice platformowe względem Androida

- Androidowy `ACTION_SEND` nie ma bezpośredniego odpowiednika wewnątrz głównego targetu iOS. Odbieranie linków bezpośrednio z systemowego Share Sheet wymaga osobnego **Share Extension**; w tej wersji link można wkleić w ekranie dodawania utworu.
- Androidowy `Media3`/foreground service nie został odwzorowany przez sztuczną lokalną sesję audio. KajutaBot steruje odtwarzaniem zdalnym na Discordzie, więc iOS nie deklaruje, że sam odtwarza dźwięk. Integrację z `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` warto dodać osobno tylko jeśli świadomie chcemy zdalne sterowanie w Lock Screen/Control Center.

## Release / performance

Konfiguracja **Release** jest ustawiona pod wydajność runtime:

- Swift `-O` (Optimize for Speed)
- Whole Module Optimization
- dead-code stripping oraz stripping symboli Swift
- `ENABLE_TESTABILITY = NO`
- `ENABLE_PREVIEWS = NO` dla targetu aplikacji
- dSYM pozostaje włączony (`DWARF with dSYM`) do symbolikacji crashy
- `ONLY_ACTIVE_ARCH = NO` dla prawidłowego archiwum dystrybucyjnego

Nie są używane `-Ounchecked` ani wyłączanie runtime safety checks.

`ArtworkView` używa Nuke 13 `ImageRequest.ThumbnailOptions`, aby dekodować bitmapy bliżej docelowego rozmiaru renderowania. Małe miniatury dostają budżet 3× rozmiaru punktowego, a hero artwork ma limit 1536 px. Ogranicza to koszt dekodowania i zużycie pamięci bez pogarszania jakości UI.

Do dystrybucji użyj **Product → Archive**. Domyślna akcja Archive w schemacie Xcode korzysta z konfiguracji Release.

## Launch screen

Aplikacja używa statycznego `LaunchScreen.storyboard` z adaptacyjnym jasnym/ciemnym tłem oraz logo KajutaBot. Launch screen nie wykonuje kodu ani animacji — po uruchomieniu system zastępuje go właściwym SwiftUI.
