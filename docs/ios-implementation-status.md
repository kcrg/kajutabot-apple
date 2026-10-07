# KajutaBot iOS — status implementacji i odbiór

7 października 2026. Zmiany zapisane w katalogu roboczym; bez kompilacji, uruchomienia aplikacji, testów Swift ani żądań do produkcyjnego API. Android pozostał nietknięty. Punktem odniesienia jest jego aktualny, zmodyfikowany katalog roboczy.

## Wprowadzone zmiany

| Etap planu | Kod w tej zmianie | Status odbioru |
| --- | --- | --- |
| I-01 | Wspólne DTO aplikacji/Share; `queueVersion`, `expectedQueueVersion`, count, playback instance/position, skip outcome, addedTracks, favorite po ID, endpoint swap | Wymaga potwierdzenia kontraktu wdrożonego backendu; brak fallbacku `version` → `queueVersion` |
| I-02 | Protokoły API/Keychain, generacja sesji, współdzielony refresh, koordynator wszystkich mutacji kolejki, ochrona odczytów ulubionych i wyboru kanału | Źródła testów dopisane; dalsze wydzielenie PlayerStore/FavoritesStore pozostaje refaktoryzacją |
| I-03 | Wspólny monotoniczny postęp; stany per akcja, lokalizowane błędy widoczne w zakładkach i arkuszach; feedback VoiceOver; komunikat restartu repeat | Gesty, wygląd i dostępność nie zostały sprawdzone na urządzeniu |
| I-04–06 | Natywne Search, List/EditButton, wybór Discord, radio bez utworu, requeue, swipe, move i jawny swap dowolnych wpisów, metadane wyników, serca, akcje zbiorcze ulubionych, historia 5 wpisów | Scenariusze UI wymagają Maca/iPhone’a |
| I-07 | Share z UI SwiftUI i wynikiem addedTracks, gość, wspólny Keychain, App Group inbox, claim przed POST, brak automatycznego replay nieznanego wyniku | App Group, Keychain i koordynacja między procesami wymagają urządzenia i podpisu |
| I-08 | Sesyjny socket SignalR, osobna subskrypcja guild, stan/draft głośności 0–200%, natywny Slider, event/read race, invoke Completion, debounce wskaźnika 100 ms, limit 10 s, ostatnia oczekująca intencja | Wymaga serwera z helperem Windows i rzeczywistego SignalR |
| I-09 | System/jasny/ciemny przez AppStorage, rozszerzona pomoc, PL/EN, Sentry zamiast Pulse i ukrytej konsoli | DSN nie jest skonfigurowany; pakiety i telemetria wymagają odbioru na Macu |
| I-10 | Udokumentowany kierunek oficjalnego RemoteMediaSession | Nie wdrożono; potrzebny SDK i próba na urządzeniu |
| I-11 | Testy kontraktów HTTP/DTO, kolejki, sesji, progress, inbox i głośności; workflow macOS z coverage | Workflow dodany, nie uruchomiony; pełne XCUITest funkcji i odbiór wydania pozostają do wykonania |

## Decyzje dotyczące SwiftUI

- `@MainActor @Observable` dla stanu aplikacji, playera i głośności; `@State` dla lokalnej prezentacji i `@Bindable` dla bindings. Istniejący `SessionManager` pozostaje aktorem.
- `List`, `EditButton`, `swipeActions`, `NavigationStack`, systemowa zakładka Search, natywny Slider i systemowy mini-player accessory. UIKit pozostaje tylko hostem wymaganym przez Share Extension.
- Przeciągnięcie przesuwa element. Osobna akcja „Zamień z…” wybiera drugi wpis w arkuszu i wykonuje swap. Menu i akcje VoiceOver udostępniają te działania także bez gestów.
- Wynik wyszukiwania można dodać wielokrotnie bez opuszczania ekranu. URL zmienia zakładkę dopiero po potwierdzonym sukcesie. Stop i czyszczenie wymagają potwierdzenia; usunięcie nie ma pełnego swipe.
- `TimelineView` aktualizuje widoczny postęp bez timera żyjącego w AppState. Obliczenia używają systemUptime i pozycji backendu; brak pozycji daje stan nieznany zamiast czasu wyliczonego z zegara ściennego.

Natywne gesty i dostępne alternatywy są zgodne z kierunkiem [Apple HIG: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures). To nie stanowi potwierdzenia jakości VoiceOver ani układu po kompilacji.

## Semantyka operacji

Mutacje kolejki są serializowane per guild. REST i realtime porównują `version`, mutacje używają `queueVersion`. Reorder nie jest automatycznie przenoszony na nowszą wersję kolejki. Po niepotwierdzonym POST następuje jeden odczyt; brak automatycznego ponowienia. Odświeżenie tokena po 401 pozostaje ograniczone do jednej próby, przy sprawdzaniu tożsamości sesji.

Share nie obraca refresh tokena. Wygasła lub zmieniona sesja, brak sesji/celu i nieudany odczyt zapisują link do jawnego zatwierdzenia w aplikacji. Claim pliku jest koordynowany przez NSFileCoordinator. Receipt `outcomeUnknown` nigdy nie wywołuje automatycznie POST. Bez idempotency backendu nie da się zapewnić exactly-once po utracie odpowiedzi. Zapisane linki wygasają po 7 dniach; nie zawierają tokenów.

GetLocalVolumeState i SetLocalVolume mają deadline. Set używa `invoke`, ponieważ `send` nie czeka na hub Completion. Odczyt, zdarzenie i zakończenie komendy mają osobną semantykę; zakończenie nie udaje obserwacji. Zmiana guild nie czyści draftu, utrata transportu lub sesji czyści oczekujące intencje. Starszy hub bez tej funkcji nie blokuje playera. Sygnatury sprawdzono w [SignalRClient 1.0.0](https://github.com/dotnet/signalr-client-swift/blob/v1.0.0/Sources/SignalRClient/HubConnection.swift).

## Telemetria i zależności

Pulse/PulseProxy/PulseUI i nieużywane AsyncAlgorithms usunięto. Sentry 9.24.0 jest przypięte w projekcie do wersji, której publiczny pakiet i opcje sprawdzono w źródłach. Nie oznacza to, że jest to najnowsza wersja. `KAJUTABOT_SENTRY_DSN` należy przekazać ustawieniem builda; pusty lub nierozwinięty DSN nie uruchamia SDK.

Diagnostyka przyjmuje StaticString i nie zapisuje URL, wyszukiwań, tokenów ani tekstu błędów serwera. Wyłączono automatyczne network breadcrumbs, capture failed requests, network tracing, screenshots, view hierarchy i introspekcję pamięci. Przed wydaniem sprawdzić payload crasha i ustawienie „Prevent Storing of IP Addresses” w projekcie Sentry. [Opcje SDK 9.24.0](https://github.com/getsentry/sentry-cocoa/blob/9.24.0/Sources/Swift/Options.swift).

Package.resolved zachowuje wcześniejsze piny używanych bibliotek i usuwa usunięte zależności; pin Sentry musi zostać dopisany przez rzeczywisty resolve w Xcode. Przejściowy plik ma wspierany format v2. Nie fabrykowano rewizji pakietu ani wyników rozwiązywania zależności. Przed wydaniem zapisać wygenerowany kompletny lock.

## Sterowanie systemowe — następny etap I-10

Aplikacja steruje playbackiem poza iPhonem. Oficjalny [RemoteMediaSession](https://developer.apple.com/documentation/nowplaying/remotemediasession) służy do przedstawiania takich sesji systemowi; [Publishing remote media sessions](https://developer.apple.com/documentation/nowplaying/publishing-remote-media-sessions) opisuje rozszerzenie oraz aktualizacje. [Release notes iOS 27](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) wymieniają problemy tych sesji i środowiska push tokenów. Dostępność symboli, wymogi podpisu i zakres działania należy ostatecznie potwierdzić w docelowym SDK. Minimum projektu pozostaje iOS 26.2.

Następny eksperyment na Macu: osobny adapter i target RemoteMediaSessionExtension, availability gate i feature flag, wspólne snapshoty/metadane, obsługiwane przez API komendy oraz czyszczenie sesji przy logout. Aktualizacje w tle wymagają osobnego rozwiązania (w tym możliwej obsługi push przez backend), a nie żyjącego stale WebSocketu. Sprawdzić start w foreground/background, blokadę ekranu, odbiór komend i zgodność starszego iOS. Nie dodano fikcyjnego AVPlayera, cichego audio ani uprawnienia background audio.

## Weryfikacja wykonana na Windowsie

Przegląd źródeł i sygnatur użytego SignalR/Sentry; parsowanie struktury OpenStep projektu i jego referencji; JSON katalogu tłumaczeń i pinu zależności; XML plist/entitlements; obecność tłumaczeń nowych kluczy w PL/EN; git diff --check. To kontrole strukturalne, nie walidacja Swift, kompilacja ani test aplikacji.

## Bramka na Macu

1. Xcode 26.2+, otwarcie projektu, Resolve Package Dependencies i zapis nowego Package.resolved. Kompilacja Debug oraz Release aplikacji i Share Extension; pełne diagnostics concurrency.
2. Uruchomienie KajutaBotTests z coverage na iOS 26.2. Workflow `.github/workflows/ios-validation.yml` wykonuje resolve i te testy na macOS 26/Xcode 26.2 bez podpisu. Nie używa produkcyjnych danych w testach kontraktów.
3. Odbiór manualny: 320/375 pt i iPad, największe rozmiary Dynamic Type, VoiceOver, Reduce Motion, PL/EN, systemowy/jasny/ciemny. Sprawdzić czy toolbar, akcje wierszy i mini-player się mieszczą; nic nie znika pod klawiaturą.
4. Queue/search/favorites: wiele kliknięć, wynik vs URL, snapshot w czasie reorder, błąd 409/429/5xx, timeout po commit, duplikaty entryId/contentId, repeat restart, radio bez utworu, zmiana guild A→B→A i kanału podczas odczytu, logout w czasie mutacji/refresh.
5. Share na podpisanym urządzeniu: Safari/YouTube/SoundCloud/plain text, playlisty, gość, brak i wygasła sesja, brak celu, jednoczesne uruchomienie app/extension, utrata odpowiedzi i receipt unknown. Zweryfikować limit pamięci rozszerzenia.
6. Helper Windows: 0/100/200%, brak helpera/offline/unavailable, stary hub, read po event, event przed Completion, wiele drag podczas komendy, timeout, reconnect, zmiana guild i logout. VoiceOver musi zatwierdzać regulację, nie tylko zmieniać draft.
7. Przed TestFlight: potwierdzenie kontraktu backendu, podpis/App Group/Keychain, payload Sentry i dSYM, pomiar startu i pamięci Instruments. Rozszerzone XCUITest, pełne wydzielenie feature stores i obsługa Retry-After pozostają następnymi pracami po pierwszej bramce kompilacji.
