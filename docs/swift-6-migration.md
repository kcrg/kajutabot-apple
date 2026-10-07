# Migracja do Swift 6

Wszystkie osiem konfiguracji targetów (aplikacja, Share Extension, testy jednostkowe i UI; Debug/Release) używa `SWIFT_VERSION = 6.0`. Deployment target iOS pozostaje **26.2**, również dla konfiguracji testów dziedziczących ustawienie projektu. Swift 6 oznacza tryb języka; wymagany toolchain pozostaje Xcode 26.2+ ze Swift 6.2+, potrzebny również dla istniejącego UI. [Oficjalny opis trybu Swift 6](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/) wyjaśnia, że pełna kontrola współbieżności jest w tym trybie obowiązkowa.

`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` zachowuje jawne granice obecnej architektury: AppState, SwiftUI, realtime i kontrolery UI na MainActor; SessionManager i ShareArtworkLoader jako własne aktory; DTO, parsery i klient HTTP bez izolacji UI. Pozostaje włączone Approachable Concurrency. Nie dodano wyciszania diagnostyki ani importów `@preconcurrency`.

Zmiany kodu:

- Generyczne odpowiedzi/żądania HTTP wymagają `Sendable`. Dekodowanie JSON w klientach REST/auth używa `@concurrent`, aby nie dziedziczyło MainActor od wywołującego UI przy włączonym Approachable Concurrency. [Model wykonania Swift 6.2](https://www.swift.org/blog/swift-6.2-released/).
- Callbacki UI/realtime mają jawny typ `@MainActor`. Callbacki item providera, OAuth i URLSession mają `@Sendable`, a delegate drop jest izolowany do MainActor. Zakończenie animacji przekazuje czyszczenie stanu do MainActor.
- `NSItemProvider` jest obsługiwany na MainActor, a jego callback ekstrahuje URL przed wznowieniem continuation. Obiekt `NSSecureCoding` nie jest zwracany przez async ani przekazywany pomiędzy aktorami. Nie dodano automatycznych powtórzeń enqueue.
- Wspólny parser dat używa wartości `Date.ISO8601FormatStyle` z `Sendable` zamiast współdzielonych mutowalnych ISO8601DateFormatter z `nonisolated(unsafe)`. Obsługuje UTC, offset i ułamki sekund; korzystają z niego aplikacja i rozszerzenie.
- Wartości stanu, postępu, tożsamości/układu animacji i onboarding mają deklaracje `Sendable`. Cache obrazów pozostaje wyłącznie w aktorze, konfiguracja NSCache odbywa się przed przypisaniem do jego stanu. UIImage ma systemową zgodność [Sendable](https://developer.apple.com/documentation/uikit/uiimage), nie dodano własnej niekontrolowanej zgodności obrazu.
- Delegaty Nuke i URLSession mają tylko niezmienny stan Sendable; usunięto ich `@unchecked Sendable`. Sprawdzono kontrakt [Nuke 13.2.0 Delegate](https://github.com/kean/Nuke/blob/13.2.0/Sources/Nuke/Pipeline/ImagePipeline%2BDelegate.swift) i aktor [SignalRClient 1.0.0 HubConnection](https://github.com/dotnet/signalr-client-swift/blob/v1.0.0/Sources/SignalRClient/HubConnection.swift). Nie zmieniano pinów ani trybu języka zewnętrznych pakietów.
- Atrapy sesji, rejestrator HTTP i globalny handler URLProtocol używają [Mutex](https://developer.apple.com/documentation/synchronization/mutex). Pozostałe `@unchecked Sendable` dotyczy wyłącznie testowego subclass URLProtocol, który dziedziczy tę zgodność z Foundation. Cały współdzielony stan tej atrapy jest chroniony przez Mutex; suite HTTP pozostaje serialized. ControlledGate ogranicza Value do Sendable.

## Weryfikacja

Na Windowsie wykonano przegląd granic izolacji, sygnatur bibliotek/SDK, ustawień projektu i diff. Nie uruchomiono kompilatora Swift, testów Swift ani aplikacji iOS. Nowe testy parsera sprawdzają offset, precyzję i równoczesne parsowanie wielu formatów; są przygotowane do uruchomienia na Macu.

Odbiór na Macu z Xcode 26.2+:

```sh
xcodebuild -version
xcodebuild -project KajutaBot.xcodeproj -scheme KajutaBot -showBuildSettings
xcodebuild -project KajutaBot.xcodeproj -scheme KajutaBot -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KajutaBot.xcodeproj -scheme KajutaBot -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project KajutaBot.xcodeproj -scheme KajutaBot -showdestinations
```

W ustawieniach sprawdzić tryb Swift 6 i deployment 26.2 dla obu konfiguracji. App build obejmuje również Share Extension. Z listy destinations wybrać dostępny symulator iOS 26.2, a następnie uruchomić testy:

```sh
xcodebuild -project KajutaBot.xcodeproj -scheme KajutaBot -destination 'platform=iOS Simulator,id=UDID_SYMULATORA_26_2' CODE_SIGNING_ALLOWED=NO test
```

Schemat KajutaBot zawiera oba targety testowe. Sprawdzić również udostępnienie URL/playlisty na podpisanym urządzeniu, login/refresh/logout, realtime, drag kolejki i animację Player ↔ mini-player. Kontrole statyczne nie potwierdzają poprawności typowania ani wykonania callbacków w SDK konkretnego Xcode; rozstrzygają to powyższe buildy i odbiór.
