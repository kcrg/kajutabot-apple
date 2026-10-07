# KajutaBot iOS — analiza różnic i plan implementacji

Data: 7 października 2026 r.

## Zakres i wiarygodność analizy

Porównano bieżące pliki `D:\Repos\kajutabot-apple` (HEAD `9b4d962`, czysty katalog przed analizą) i `D:\Repos\kajutabot-android` (HEAD `13ef7bb`, liczne zmiany staged, unstaged i untracked). Punktem odniesienia jest **aktualny katalog roboczy Androida**, a nie wyłącznie jego ostatni commit. Lokalna głośność, część obsługi realtime, gestów i wyszukiwania należą do zmian roboczych. Ich obecność w kodzie nie potwierdza wydania ani poprawnego działania.

Przeczytano widoki, nawigację, modele API, sterowanie kolejką, sesję, SignalR, udostępnianie, preferencje i testy obu klientów. Obejrzano zapisany zrzut androidowego playera; może być starszy od kodu. Nie ma równoważnych zrzutów iOS, więc ocena jego wyglądu wynika z deklaracji SwiftUI. Nie kompilowano, nie uruchamiano aplikacji ani testów i nie wysyłano żądań do produkcyjnego API. Zachowanie backendu i rzeczywiste gesty wymagają późniejszej weryfikacji.

Repozytorium iOS jest natywną aplikacją **SwiftUI**, Android używa **Kotlin/Compose**. Plan zachowuje te technologie. Migracja do MAUI nie jest potrzebna do osiągnięcia zgodności funkcji i interakcji; zwiększyłaby zakres i ryzyko. Dla iOS właściwe są istniejące Swift Testing i XCUITest, odpowiedniki testów jednostkowych i UI w tym stosie.


## Aktualizacja wykonania — SwiftUI i zalecenia Apple

Plan poniżej opisuje punkt wyjścia analizy. Po decyzji użytkownika o natywnym zachowaniu iOS przyjęto dwie korekty: pozostaje systemowa zakładka wyszukiwania (`role: .search`), a przeciąganie w `List` z `EditButton` oznacza przesunięcie. Atomowy swap jest osobną jawną akcją („Zamień z…” oraz zamiana sąsiadów). Nie wprowadzamy własnego recognizera drag ani adaptera UIKit tylko dla kopiowania gestu Androida.

Status kodu i bramek odbioru opisuje [ios-implementation-status.md](D:/Repos/kajutabot-apple/docs/ios-implementation-status.md). Zapisany kod nie jest jeszcze potwierdzonym buildem ani wydaniem.

## Wniosek

Największe problemy to rozbieżny kontrakt API, niepełne interakcje kolejki i wyszukiwania oraz słabsza izolacja operacji asynchronicznych. Samo dostosowanie wyglądu pozostawiłoby problemy funkcjonalne.

Docelowo iOS powinien zapewniać te same działania, semantykę i informację zwrotną co Android, z natywnymi kontrolkami iOS. Szczególnie ważne są: powtarzalne dodawanie z wyników wyszukiwania, gesty w obu kierunkach, atomowa zamiana pozycji, radio przy pustym playerze, potwierdzenie wykonania operacji i wspólny stan kolejki.

## Macierz różnic

| Obszar | Android — stan kodu | iOS — stan kodu | Klasyfikacja / priorytet |
| --- | --- | --- | --- |
| OAuth i gość | PKCE, sesja Discord i demo | PKCE, Keychain, Discord i demo | Podstawy istnieją; regresje do sprawdzenia, P0 |
| Serwery i kanały | Osobny ekran, karty serwerów i widoczna lista kanałów; „Gotowe” wymaga celu | Arkusz z dwoma menu; „Gotowe” bez takiej blokady | Mniej czytelny wybór celu, P1 |
| Nawigacja | 3 zakładki; wyszukiwanie i wybór Discord jako ekrany szczegółowe; osobne stosy zakładek | 3 główne zakładki i osobna systemowa zakładka wyszukiwania | Różny przepływ; ujednolicić w zadaniu I-04, P1 |
| Wersjonowanie kolejki | `version` do świeżości snapshotu, `queueVersion` do mutacji | Tylko `version`, mutacje zwykle `expectedVersion` | Rozbieżność kontraktu i synchronizacji, P0 |
| Dodawanie do ulubionych | `contentType` + `contentId` | `contentUrl`, opcjonalne `title` i `thumbnailUrl` | Rozbieżność kontraktu, P0 |
| Sterowanie playerem | Stop, skip, repeat, radio, serce; radio także bez utworu | Te same podstawowe akcje, ale cały zestaw tylko przy `nowPlaying` | Radio niedostępne w stanie pustym, P1 |
| Ponowne dodanie | Przycisk dla aktualnego utworu i gest dla elementu kolejki | Brak osobnej akcji | Brak funkcji, P1 |
| Wiersze kolejki | W prawo: dodaj ponownie; w lewo: usuń; serce | Serce i kosz jako przyciski; brak swipe | Brak spójnych gestów i informacji zwrotnej, P1 |
| Zmiana kolejności | Long press + drag, auto-scroll, podświetlenie celu, atomowy swap; akcje dostępności góra/dół | `.onMove`, endpoint przesunięcia; brak jawnego uchwytu/trybu edycji i analogicznej obsługi swap | Inna semantyka i niepotwierdzona dostępność gestu, P1 |
| Podsumowanie kolejki | Liczba i łączny czas z backendu, objaśnienia gestów | Sam nagłówek kolejki i przycisk czyszczenia | Brak informacji, P1 |
| Wyszukiwanie | W prawo dodaje wynik i pozostawia ekran; serce; stany per wynik | Przycisk dodania natychmiast zmienia zakładkę; brak serca i swipe | Istotna różnica przepływu, P1 |
| URL w wyszukiwaniu | Powrót po potwierdzonym enqueue | Przycisk toolbar wraca przed odpowiedzią; submit klawiatury nie wywołuje tego samego powrotu | Błąd spójności i potwierdzenia operacji, P0 |
| Metadane wyników | `dateLabel`, sformatowane `metricCount` + `metricCaption` | Czas i samo `metricCaption`; liczba i data pomijane | Niepełna informacja, P1 |
| Historia wyszukiwania | 5 wpisów | 8 wpisów | Drobna różnica preferencji, P2 |
| Ulubione | Swipe dodaj/usuń, jawne „Dodaj wszystkie N” i shuffle, otwieranie źródła przez tytuł | Przyciski dodaj/usuń; akcje zbiorcze w menu; źródło w context menu; dodatkowe dodanie URL | Funkcje częściowo istnieją, inna odkrywalność, P1 |
| Feedback i błędy | Pending/success/failure per akcja lub element; błędy na danym ekranie | Globalne flagi busy i `errorMessage`; prezentacja błędu tylko w `PlayerView` | Błędy innych zakładek mogą pozostać niewidoczne; akcje ignorowane podczas busy, P0 |
| Postęp utworu | Pozycja backendu + zegar monotoniczny; tożsamość konkretnego odtworzenia | Różnica czasu ściennego od `nowPlayingStartedAt` | Ryzyko błędnego postępu i restartu repeat, P0 |
| MiniPlayer | Ulubione i Więcej; znika na pełnoekranowych szczegółach; animacje po tożsamości playbacku | Ulubione i Więcej; systemowy accessory; wersja inline bez serca | Podstawowa widoczność zgodna; uzupełnić stany i dostęp do akcji, P2 |
| Lokalna głośność | Robocza implementacja helpera Windows, 0–200%, SignalR | Brak DTO, metod huba, kontrolera i UI | Brak funkcji, P1; zależność od backendu/helpera |
| Systemowe multimedia | Media3, metadane, skip i custom actions stop/repeat/radio/favorite; usługa współdzieli realtime | Brak integracji; po wejściu w tło SignalR jest zatrzymywany | Brak funkcji; osobne sprawdzenie możliwości platformy, P2 |
| Share | Dedykowany ekran, wynik z `addedTracks`, także playlisty, identyfikator żądania | Istniejące rozszerzenie samodzielnie wysyła URL; ogólny wynik i automatyczne zamknięcie; tylko Discord | Częściowa zgodność, P1 |
| Motyw | Systemowy/jasny/ciemny | Kolory systemowe; brak wyboru motywu | Brak ustawienia, P2 |
| Onboarding | 7 tematów i wybór celu | 3 tematy i wybór celu | Brak instrukcji kolejki, radia, mini-playera i integracji systemowej, P2 |
| Realtime / grafika | Reconnect, recovery, cache i prefetch | Reconnect, recovery, Nuke i prefetch także istnieją | Zachować, rozszerzyć; nie implementować ponownie |
| Testy | Rozbudowane źródła testów API, stanu, gestów i głośności | 7 testów pomocników/DTO, UI tylko pomiar startu | Duża luka pokrycia; uruchomienie wyłącznie na Macu |

## Rozbieżności wymagające naprawy przed rozbudową UI

### 1. Kontrakt mutacji i snapshotów kolejki

iOS koduje `expectedVersion` w DTO i query DELETE, ponieważ nie ma mapowania `CodingKeys` na inną nazwę. Android we wszystkich mutacjach wysyła `expectedQueueVersion`; jego test klienta sprawdza również, że `expectedVersion` nie występuje. Radio enable i queue-all w iOS mają właściwą nazwę pola, lecz przekazują `queue.version`, a nie brakujące `queueVersion`.

Przykład docelowego żądania według kontraktu Androida:

```json
{
  "voiceChannelId": "channel-id",
  "inputs": ["https://youtu.be/video-id"],
  "expectedQueueVersion": 11
}
```

Snapshot może równocześnie zawierać `version: 20` i `queueVersion: 11`. To dwa odrębne pola: akceptacja danych porównuje `version`, token mutacji bierze `queueVersion`. Zastępowanie jednego drugim wymagałoby potwierdzonej reguły kompatybilności backendu.

iOS pomija także `pendingEntriesCount`, `playbackInstanceId`, `playbackPositionMilliseconds`, `skipOutcome` i `addedTracks`. Dodanie tych pól umożliwia zgodny postęp, restart tego samego utworu, komunikaty skip i podsumowanie udostępnionej playlisty.

**Potwierdzone:** oba klienty wysyłają inne payloady. **Niepotwierdzone:** czy wdrożony backend nadal toleruje starsze pola. Nie można na tej podstawie stwierdzić, że wszystkie obecne żądania iOS kończą się błędem. Pierwszy krok implementacji to potwierdzenie kontraktu backendu/OpenAPI lub uzyskanie zanonimizowanych fixture payloadów.

### 2. Kontrakt dodawania ulubionych

Android dodaje ulubiony utwór przez identyfikator treści:

```json
{ "contentType": "YouTube", "contentId": "video-id" }
```

iOS wysyła URL, tytuł i miniaturę. Ujednolicić request i przejąć tytuł/miniaturę z odpowiedzi serwera. Wyniki wyszukiwania już zawierają potrzebne identyfikatory.

Dodatkowe iOS „Dodaj ulubiony przez URL” wymaga osobnego rozwiązania: resolvera backendu lub jednoznacznego rozpoznania wspieranych URL-i. Nie należy zmieniać go w enqueue, bo zapis ulubionego nie powinien zmieniać odtwarzania. Jeśli API nie oferuje resolwera, priorytetem jest dodawanie sercem z playera/wyników; akcję URL trzeba dostosować do potwierdzonego kontraktu.

### 3. Zakończenie akcji i widoczność błędów

`AddTrackView` wywołuje `queued()` zaraz po `enqueueSearchResult` albo `performSearch`, a te metody jedynie uruchamiają `Task`. Zmiana zakładki uruchamia też `clearAddTrack`. Nawigacja nie jest dowodem sukcesu; brak celu, busy i błąd sieci mogą wystąpić już po opuszczeniu ekranu. Z kolei wysłanie URL klawiaturą nie ma identycznej ścieżki nawigacji.

`FavoritesView`, `MoreView` i `AddTrackView` nie prezentują globalnego `errorMessage`, które wyświetla tylko player. Każdy widok potrzebuje własnego stanu błędu/operacji lub wspólnego prezentera dostępnego w bieżącym kontekście. Nie dodawać wielu niezależnych alertów obserwujących to samo pole.

### 4. Współbieżność i izolacja sesji

`moveQueueEntry` omija globalną blokadę mutacji, zapisuje optymistyczny snapshot bez zwiększenia wersji i przy błędzie bezwarunkowo wykonuje `queue = current`. Jeśli w międzyczasie przyjdą nowsze dane albo użytkownik zmieni serwer, rollback może przywrócić stary snapshot. To ryzyko wynikające z kolejności instrukcji, bez potwierdzenia wykonaniem.

`queueAllFavorites` i zwykłe enqueue używają różnych flag busy, choć zmieniają tę samą kolejkę. `refreshFavoritesAsync` nie ma ochrony przed nadpisaniem nowszej mutacji starszą odpowiedzią GET. Część zadań nie jest zapamiętana i anulowana przy wylogowaniu. `SessionManager` współdzieli refresh w jednym actorze, ale po `await` nie sprawdza generacji sesji przed `commit`; anulowanie zadania samo nie stanowi ochrony przed zapisem spóźnionego wyniku.

Zastosować generację sesji oraz kontrolę kontekstu przed każdym zapisem danych i błędów. Samo porównanie `guildId` nie chroni przed logout/login na tym samym serwerze ani sekwencją A → B → A.

## Docelowy sposób interakcji

### Nawigacja i wybór celu

Zachować trzy główne zakładki i osobną systemową zakładkę wyszukiwania iOS 26. Przycisk lupy w playerze otwiera tę zakładkę. Każda ma własny `NavigationStack`. URL wraca do playera po potwierdzonym dodaniu, a dodanie wyniku pozostawia wyszukiwanie otwarte. Wybór serwera/kanału jest natywnym arkuszem z listą i przyciskami Cancel/Done.

Osobne ścieżki `NavigationStack` utrzymują stan każdej zakładki. Wyjście z wyszukiwania czyści query/results dopiero po zamknięciu widoku, bez niszczenia treści podczas animacji. W widoku Więcej powrót z Kontakt/Biblioteki zachowuje oczekiwany stos.

Wybór Discord prezentuje serwery z nazwą i ikoną oraz kanały jako listę z widocznym zaznaczeniem. Gość widzi kanały serwera demo. „Gotowe” wymaga poprawnego celu. Zmiana serwera od razu usuwa stare kanały i wybór kanału; spóźnione odpowiedzi są odrzucane. Player pokazuje bieżący cel i widoczny stan „Wybierz kanał”. Zachować rozróżnienie wybranego celu nowych enqueue od kanału, na którym aktualnie działa kolejka.

### Player i kolejka

- Przycisk „Dodaj ponownie” dla aktualnego utworu. Dodaje jego URL na koniec przez istniejące enqueue; preferuje kanał aktualnej kolejki, jak Android. Nowe pozycje dostają nowe `entryId`.
- Radio pozostaje widoczne, gdy brak `nowPlaying`. Można je włączyć po wyborze celu i uzyskaniu snapshotu, a wyłączyć także bez aktualnie wybranego kanału. Zachować min/max 60/600 s jako istniejące fallbacki; nie dodawać nowych ustawień radia bez potrzeby.
- W prawo na wierszu: dodaj ponownie; w lewo: usuń. Serce pozostaje osobnym przyciskiem. Używać `swipeActions` na istniejącym `List`, z akcjami leading/trailing; pełny swipe zatwierdza jedną operację. Natywne wsparcie opisuje [dokumentacja Apple](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)).
- Natywna edycja `List` przesuwa pozycję przez `.onMove`. Osobne menu „Zamień z…” realizuje atomowy swap dowolnych dwóch wpisów. Dla `[A,B,C,D]` swap A z C daje `[C,B,A,D]`, a natywne przesunięcie A na pozycję C daje `[B,C,A,D]`. Te różne intencje mają oddzielne akcje i endpointy.
- System `List` odpowiada za gest edycji, uchwyt i przewijanie. Używać `entryId`, nigdy `contentId` jako tożsamości; kolejka może zawierać duplikaty. Nie zmieniać listy optymistycznie przed potwierdzeniem HTTP.
- Przed drop sprawdzić sesję, serwer i wersję snapshotu zapamiętaną na początku gestu. Po zmianie danych anulować lub ponownie uzgodnić działanie; nie wysyłać ślepo starej operacji.
- Akcje „Zamień z poprzednim/następnym” dostępne dla VoiceOver i w menu. Dostępny przycisk/menu zapewnia też użycie bez gestu.
- Nagłówek kolejki: liczba, łączny czas, objaśnienie swipe i drag, czyszczenie. Stop i czyszczenie zachowują potwierdzenie; pojedyncze usunięcie ma feedback i bezpieczną obsługę błędu.

Wybór implementacji drag trzeba sprawdzić na docelowym iOS 26.2: istniejące `.onMove` nie realizuje semantyki swap ani pełnego feedbacku. Zacząć od `List` i natywnych mechanizmów; jeśli nie zapewnią wymaganego gestu, użyć ograniczonego adaptera UIKit dla listy. Nie uzależniać tej funkcji od podniesienia minimalnej wersji systemu. Nie obiecywać współdziałania swipe/long press/scroll bez próby na urządzeniu.

### Wyszukiwanie i ulubione

- Tekst → jawne wyszukanie; URL → enqueue. Toolbar i submit klawiatury wywołują tę samą intencję. Obsłużyć również link z dodatkowym tekstem przez jeden wspólny parser URL.
- Wynik: okładka, tytuł, data jeśli dostępna, lokalnie sformatowana liczba i podpis metryki, serce. Czas można zachować jako dodatkową informację.
- Swipe w prawo dodaje pojedynczy wynik **bez zamykania wyszukiwania**; użytkownik może dodać kolejne. Alternatywą jest przycisk/menu i akcja VoiceOver.
- Zatwierdzenie wklejonego URL wraca do playera dopiero po sukcesie. Błąd zachowuje tekst i pokazuje komunikat na miejscu. Operacja o nieznanym wyniku najpierw synchronizuje kolejkę; nie wysyła automatycznie POST ponownie.
- Historia: 5 najnowszych, deduplikacja bez rozróżniania wielkości liter. Źródła YouTube/SoundCloud/Database zachować; zmianę źródła i zamknięcie zabezpieczyć generacją zapytań.
- Ulubione: w prawo enqueue, w lewo usuń; jawne „Dodaj wszystkie (N)” i shuffle. Menu pozostaje dla rzadszych akcji. Tytuł lub „Otwórz źródło” otwiera tylko dopuszczalny URL HTTP(S).
- Każda akcja ma `idle → pending → success/failure → idle`, identyfikator operacji i krótki feedback. Nie znika po nieudanym usunięciu. Sukces nie jest tożsamy z chwilowym ukryciem wiersza.

### Mini-player, motyw i pomoc

Zachować mini-player na Ulubionych i Więcej; aktualny Android także ukrywa go na playerze i szczegółach, mimo ogólniejszego opisu w onboardingu. Kliknięcie otwiera player, pozostałe akcje to serce i skip. Wersja zminimalizowana iOS może być prostsza, ale wszystkie akcje muszą być dostępne po rozwinięciu. Postęp i stan busy pochodzą z tego samego store co pełny player.

Dodać motyw Systemowy/Jasny/Ciemny przez preferencję i `preferredColorScheme`. Rozszerzyć pomoc o kolejkę/gesty, radio, mini-player i share. Informacja o systemowym sterowaniu pojawia się dopiero na wersjach iOS, dla których integracja została wykonana i sprawdzona. Lokalna głośność jest objaśniana jako odsłuch na Windows/Discord Desktop, a nie głośność telefonu.

### Lokalna głośność helpera Windows

Portować zachowanie z `docs/local-volume.md` i `LocalVolumeController.kt`, z użyciem istniejącego PlaybackHub:

- DTO `installed`, `online`, `available`, `volume: Int?`; walidacja zależności stanów i zakresu 0–200.
- `GetLocalVolumeState()` po połączeniu/reconnect; `LocalVolumeStateChanged` aktualizuje obserwację; `SetLocalVolume(Int)` oczekuje completion, timeout 10 s. Brak nowego endpointu REST i drugiego socketu.
- Stan przypisany do konta, niezależny od wybranego serwera. Zmiana subskrypcji serwera nie jest zmianą właściciela lokalnej głośności. Refaktoryzacja realtime oddziela połączenie sesji od subskrypcji guild.
- Przycisk tylko dla Discord i potwierdzonego `installed=true`. Offline nie oznacza odinstalowania. Brak danych nie pokazuje sztucznego 100%; prezentować „—” i blokować niedostępny/stary stan.
- Natywny arkusz z suwakiem 0–200%, krok 1, procentem, stabilnym miejscem na feedback i błędy. Wyjaśnienie w dostępności. Zamknięcie gestem/poza arkuszem; nie trzeba kopiować przezroczystego scrim Androida.
- Event nie przestawia draftu podczas gestu. Koniec gestu zatwierdza jedną komendę; w czasie wysyłania przechowywana jest najwyżej ostatnia zatwierdzona intencja. Zmiana wartości przez VoiceOver także musi kończyć się zatwierdzeniem.
- Event i completion mają różne role: completion kończy wysyłanie, event potwierdza obserwowaną wartość. Spinner dopiero po 100 ms dla bieżącej komendy, anulowany przy completion/błędzie/disconnect.
- Licznik eventów chroni snapshot przed nadpisaniem nowszej obserwacji; generacja połączenia i sesji odrzuca stare callbacki. Błąd powoduje pojedynczy odczyt stanu, bez automatycznego retry `Set`.
- Logout, disconnect, reconnect i utrata dostępności usuwają oczekujące intencje. Starszy backend bez metod local volume nie blokuje zwykłego playera.

### Udostępnianie

Zachować istniejące Share Extension: na iOS to poprawny sposób przyjmowania share, nie musi uruchamiać pełnej aplikacji jak Android. Uzupełnić o wynik operacji z odpowiedzi enqueue: jeden utwór z tytułem/okładką lub liczba/lista `addedTracks` dla playlisty. Błędy i brak celu pozostają czytelne; zamknięcie nie jest jedyną formą feedbacku.

Rozszerzenie obecnie odrzuca gościa. Docelowo uwzględnić guest flow, jeśli dopuszcza go ten sam kontrakt backendu. Przy braku sesji/celu zachować bezpieczny pending URL w App Group i przetwarzać po otwarciu aplikacji oraz wyborze celu. Próba przekazania użytkownika do aplikacji musi używać wspieranego mechanizmu rozszerzeń; nie zakładać dowolnego `openURL` z Share Extension.

Wydzielić wspólne DTO, parser URL i reguły sesji dla obu targetów. Każda intencja ma identyfikator; pojedynczy URL nie może być wysłany raz przez extension i ponownie przez aplikację. Lokalny identyfikator chroni przed podwójną obsługą intencji, lecz **nie zapewnia idempotencji backendu** po timeout.

Aktualne app i extension niezależnie odświeżają i zapisują tę samą sesję Keychain; actor w aplikacji nie synchronizuje drugiego procesu. Preferowany wariant to jeden właściciel odświeżania i przekazanie oczekującej intencji, gdy rozszerzenie nie może użyć ważnego tokena. Jeśli bezpośredni refresh extension ma zostać, uzgodnić z backendem rotację tokenów i mechanizm koordynacji między procesami. Samo współdzielenie kodu nie usuwa tego wyścigu. Sprawdzić App Group, podpisane uprawnienia i migrację Keychain na urządzeniu; nie ma podstaw do uznania konfiguracji za błędną wyłącznie przez brak osobnego wpisu keychain-sharing w plikach.

### Integracja z systemem i tłem — osobny eksperyment

Android utrzymuje własną usługę Media3 i realtime poza UI. iOS teraz zatrzymuje SignalR w tle. Nie należy zakładać, że port Media3 na `MPRemoteCommandCenter` zapewni równoważne działanie zablokowanego telefonu.

Najpierw sprawdzić dedykowany [Now Playing framework](https://developer.apple.com/documentation/nowplaying) i obsługę sesji zdalnych oraz dostępność API w SDK i na minimalnym iOS 26.2. Następnie ocenić zakres starszych [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) / Now Playing Info. Nie obiecywać dostępności wszystkich custom actions Androida na karcie systemowej iOS.

Według [dokumentacji trybów pracy w tle Apple](https://developer.apple.com/documentation/Xcode/configuring-background-execution-modes) aplikacja zwykle jest zawieszana, a tryb audio dotyczy odtwarzania słyszalnej treści. KajutaBot jest pilotem i nie odtwarza muzyki na telefonie. Z tego wynika potrzeba osobnej oceny modelu zdalnej sesji; nie dodawać sztucznego odtwarzania ciszy ani trybu audio tylko do utrzymywania socketu.

Wynikiem eksperymentu ma być decyzja: wspierana zdalna sesja i zakres wersji iOS albo ograniczony wariant integracji. Ewentualne App Intents/Widget/Live Activity traktować jako odrębny zakres, z oceną aktualizacji backendu/APNs i czasu wykonania. Nie zastępują automatycznie działającego w tle SignalR. Do czasu weryfikacji zachować skuteczne odświeżenie po powrocie do aplikacji i oznaczenie danych nieaktualnych.

## Plan implementacji i zależności

P0 — poprawność kontraktów i stanu; P1 — podstawowa zgodność funkcji/interakcji; P2 — pozostałe ustawienia, animacje i integracja platformowa.

| Zadanie | Priorytet / zależność | Zakres i pliki iOS | Kryterium odbioru |
| --- | --- | --- | --- |
| **I-01 Kontrakty API** | P0; pierwsze | `Models.swift`, `KajutaBotAPIClient.swift`, współdzielone DTO extension; nowe fixture/testy | Wszystkie mutacje wysyłają `expectedQueueVersion` z `queueVersion`; snapshot rozróżnia wersje i dekoduje nowe pola; favorite dodaje po ID; backend/fixtures potwierdzają shape |
| **I-02 Stan i współbieżność** | P0; I-01 | Wydzielenie `PlayerStore`, `FavoritesStore`, `QueueMutationCoordinator`, protokołów API/store/clock z `AppState`; `SessionManager`, `RealtimeClient` | Mutacje jednego guild wykonują się kolejno, także queue-all/requeue; wynik poprzedniej sesji nie zapisuje stanu ani błędu; timeout nie powtarza POST; refresh nie cofa ulubionych |
| **I-03 Postęp i feedback** | P0; I-01–02 | Wspólny `PlaybackProgressState`, `ActionStatus`, lokalizowane błędy; `PlayerView`, `MiniPlayerView`, `AddTrackView`, `FavoritesView`, `MoreView` | Monotoniczny postęp z pozycji backendu, reset po nowym playbackInstanceId; każdy ekran pokazuje wynik swojej akcji; brak fałszywego sukcesu/nawigacji |
| **I-04 Nawigacja i wybór Discord** | P1; I-02 | `MainTabView`, nowa trasa Search/DiscordSelection, `DiscordTargetPicker` | 3 główne zakładki + systemowa Search, oddzielne stosy; widoczny przycisk dodania; powrót z detali spójny; stare kanały nie pojawiają się po zmianie guild |
| **I-05 Player i gesty kolejki** | P1; I-01–04 | `PlayerView`, komponent wiersza akcji, `SwapQueueEntriesRequest` i klient swap | Radio działa przy pustym playerze; requeue z playera/wiersza; swipe; swap A↔C zgodny z backendem; natywne Edit/onMove oraz jawne i dostępnościowe zamiany; liczba i czas kolejki |
| **I-06 Search i Favorites** | P1; I-01–05 | `AddTrackView`, `FavoritesView`, współdzielony komponent wyniku/ulubionego | Dodanie wyniku pozostawia search; można dodać kilka pozycji; serca są zsynchronizowane; URL zamyka dopiero po sukcesie; metadata i akcje zbiorcze są widoczne |
| **I-07 Share** | P1; I-01–03, I-04 dla pending URL | `ShareViewController`, wspólny moduł źródeł, App Group inbox, koordynacja auth | Jeden share → jedno zlecenie; wynik z addedTracks; gość/brak celu/błąd mają określone ścieżki; refresh app+extension nie gubi sesji |
| **I-08 Local volume** | P1; I-02–03; kontrakt helpera potwierdzony | DTO, `RealtimeClient`, nowy `LocalVolumeController`, `LocalVolumeSheet`, przycisk w playerze | Pełne reguły 0–200%, snapshot/event/completion, 100 ms/10 s, coalescing, brak stale intent po reconnect i logout |
| **I-09 Motyw, pomoc, dostępność i telemetry** | P2; I-04–08 | Preferencje motywu, `MoreView`, `OnboardingView`, `Localizable.xcstrings`, `Diagnostics`, zależności projektu | Wszystkie nowe działania opisane i dostępne dla VoiceOver; PL/EN, duży tekst, Reduce Motion; Sentry jako jedyny system telemetry zgodnie z instrukcją projektu |
| **I-10 Systemowe sterowanie** | P2; eksperyment można zacząć po I-01–03 | Nowy adapter/extension systemowych sesji zależnie od wyniku sprawdzenia API | Udokumentowany wspierany zakres iOS; próba na urządzeniu w tle i po blokadzie; brak deklaracji nieobsługiwanych akcji; logout usuwa starą sesję |
| **I-11 Odbiór na Macu i urządzeniu** | Bramka wydania; testy przygotowywane w każdym zadaniu | `KajutaBotTests`, `KajutaBotUITests`, projekt/scheme i CI macOS | Build app i extension, uruchomione testy i scenariusze ręczne; żadnego zadania z UI/tłem nie uznawać za w pełni zweryfikowane na podstawie review na Windows |

W I-02 wydzielać moduły stopniowo, razem ze zmienianą funkcją. `AppState` pozostaje koordynatorem wejścia/auth/nawigacji, a nie miejscem każdej akcji playera. Małe protokoły umożliwiają kontrolowane odpowiedzi API, Keychain i zegara w testach. W obrębie procesu koordynator serializuje wszystkie mutacje kolejki; extension pozostaje osobnym procesem i nadal wymaga tokena wersji backendu.

Koordynator pobiera brakujący token przed mutacją. Po 409 synchronizuje kolejkę i komunikuje konflikt; po 503/timeout/błędzie transportu uzgadnia stan bez automatycznego ponowienia operacji. Jeśli synchronizacja też zawiedzie, unieważnia token przed kolejną akcją. Podgląd drag ma osobną warstwę prezentacji i nie nadpisuje authoritative snapshotu.

Obsługa błędów mapuje `errorCode`, status HTTP, `currentQueueVersion` i `Retry-After` na komunikaty PL/EN: konflikt wersji, konflikt zapisu, pełna kolejka, niedostępna treść, inny kanał kolejki, brak dostępu, 429, timeout i niezgodny kontrakt. Błąd auth trwały oddzielić od chwilowego braku sieci. Nie prezentować użytkownikowi surowych błędów dekodera.

Telemetria: istniejący Pulse/PulseProxy/PulseUI w Release odbiega od instrukcji „Sentry only”. I-09 zastępuje go Sentry i usuwa ukrytą konsolę Pulse oraz jej wpisy w Bibliotekach. Zachować redakcję sekretów; nie przesyłać body auth, tokenów, kodów OAuth, surowych wyszukiwań ani URL-i użytkownika. Nie dodawać kolejnego systemu logowania sieci. Szczegóły konfiguracji SDK zweryfikować podczas implementacji.

## Scenariusze testów i odbioru

Poniższe testy są **do przygotowania i wykonania w implementacji**. Ich obecność w tym planie nie oznacza wyniku PASS.

| Zestaw | Najważniejsze przypadki | Weryfikacja |
| --- | --- | --- |
| Kontrakt | Wszystkie body i DELETE query; różne version/queueVersion; swap; favorites po ID; optional fields; playlist addedTracks | Swift Testing + podstawiony URLSession/URLProtocol; fixtures z potwierdzonego backendu |
| Mutacje i sesja | Enqueue + queue-all + swap; event wyprzedza REST; 409; 503/timeout o nieznanym wyniku; logout w trakcie; konto B; guild A→B→A; spóźniony refresh tokena | Testy sterowanych odpowiedzi i generacji, bez prawdziwej sieci |
| Player | Pusty player → radio; wyłączenie radio bez wybranego kanału; repeat ten sam contentId, nowy instance; skipOutcome; przejściowy null → nowy utwór; stop kończy podtrzymaną prezentację | Testy projekcji + XCUITest |
| Postęp | Różny zegar telefonu/serwera; korekta zegara ściennego; anchor backendu; brak pozycji/duration; clamp; reconnect; tło→foreground | Testy z zegarem monotonicznym i ręcznie na iPhonie |
| Gesty kolejki | Swipe oba kierunki, jeden request na akcję; long press vs pionowy scroll; auto-scroll; A↔C; duplikaty; zmiana snapshotu podczas drag; błąd bez cofnięcia nowszego stanu | XCUITest i ręczna próba na małym/dużym ekranie |
| Wyszukiwanie | 3 źródła; zmiana query/source podczas odpowiedzi; kilka enqueue bez zamknięcia; serce; URL i URL+tekst; toolbar/klawiatura; brak celu; błąd zachowuje query; powrót usuwa query po wyjściu | Swift Testing + XCUITest |
| Ulubione | GET nie cofa świeżego add/delete; normalizacja YT/SC; konto i gość; queue-all/shuffle; failure nie usuwa; brak celu; źródło HTTP(S) | Swift Testing + XCUITest |
| Share | YouTube/SoundCloud/Safari/plain text; pojedynczy utwór/playlist; gość; brak sesji/celu; token wygasły; app+extension równocześnie; timeout bez automatycznego retry; ponowne otwarcie pending intencji | Testy parsera/inbox; testy integracji Keychain/App Group na urządzeniu |
| Local volume | Gość/nieznane/installed/offline/available; null; 0/100/200; gesture; event przed completion; brak eventu; race snapshot/event; ostatnia intencja; 100 ms; 10 s; helper busy; reconnect/token/account change; starszy hub | Swift Testing z czasem kontrolowanym + iPhone/Windows helper/Discord Desktop |
| Nawigacja i dostępność | Zachowanie stosu, systemowy back/swipe; mini-player; VoiceOver bez drag/swipe; slider accessibility; Dynamic Type; PL/EN; jasny/ciemny; Reduce Motion; iPad rotation/split view | XCUITest + ręczne sprawdzenie |
| System / performance | Blokada ekranu, tło, zerwana sieć, inna app audio, logout; zimny start, obrazy przy długiej kolejce, tick tylko widocznego postępu | Fizyczne urządzenie, Instruments i bramka macOS; po eksperymencie I-10 |

Zachować istniejący prefetch dwóch kolejnych okładek i cache Nuke. Nie przechodzić na własny renderowany co klatkę scroll ani globalny timer odświeżający całe `AppState`. Tick postępu należy do małego widoku; odświeżenia z sieci pozostają zdarzeniowe. Dostępnościowa informacja o czasie nie powinna być odczytywana przy każdym ticku.

## Proponowane etapy dostarczenia

1. **Fundament:** I-01–03. Naprawione kontrakty, wspólny stan mutacji i sesji, wiarygodny postęp i wynik operacji. Pierwsza bramka kompilacji/testów na Macu.
2. **Podstawowa zgodność użycia:** I-04–06. Ujednolicona nawigacja, wybór celu, radio, requeue, swipe/swap, wyszukiwanie i ulubione. Próby gestów i dostępności na urządzeniu.
3. **Integracje:** I-07–08. Share i helper Windows, z osobnym odbiorem auth między procesami oraz protokołu głośności.
4. **Uzupełnienia i wydanie:** I-09, zaakceptowany zakres I-10 i pełne I-11. Funkcje systemowe pozostają oddzielne od zgodności podstawowych działań, dopóki nie zostanie potwierdzone wsparcie platformy.

Na Windows można przygotować zmiany w źródłach Swift, fixture, źródła testów i review kontraktów. Faktyczne zakończenie implementacji wymaga Maca/Xcode: kompilacji obu targetów, rozwiązania zależności, podpisów/uprawnień i wykonania testów. Ten etap planowania dostarcza dokument, bez zmian produkcyjnego kodu.

## Najważniejsze źródła w repozytoriach

Numery linii odnoszą się do stanu roboczego podczas analizy i mogą zmienić się przy kolejnych edycjach.

| Ustalenie | iOS | Android |
| --- | --- | --- |
| Modele kolejki i tokeny mutacji | [Models.swift](D:/Repos/kajutabot-apple/KajutaBot/Core/Models/Models.swift:111), [klient](D:/Repos/kajutabot-apple/KajutaBot/Core/Networking/KajutaBotAPIClient.swift:29) | [QueueModels.kt](D:/Repos/kajutabot-android/api/src/main/kotlin/com/tryniecki/kajutabot/api/model/queue/QueueModels.kt:15), [test wszystkich mutacji](D:/Repos/kajutabot-android/api/src/test/kotlin/com/tryniecki/kajutabot/api/client/KajutaBotApiClientTest.kt:33) |
| Request ulubionych | [AddFavoriteRequest](D:/Repos/kajutabot-apple/KajutaBot/Core/Models/Models.swift:223) | [FavoriteModels.kt](D:/Repos/kajutabot-android/api/src/main/kotlin/com/tryniecki/kajutabot/api/model/favorites/FavoriteModels.kt:14) |
| Nawigacja i mini-player | [MainTabView.swift](D:/Repos/kajutabot-apple/KajutaBot/Shared/MainTabView.swift:14) | [KajutaBotApp.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/KajutaBotApp.kt), [MiniPlayer.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/MiniPlayer.kt) |
| Przedwczesne zamknięcie search | [AddTrackView.swift](D:/Repos/kajutabot-apple/KajutaBot/Features/Player/AddTrackView.swift:54), [enqueue](D:/Repos/kajutabot-apple/KajutaBot/AppState.swift:407) | [enqueueSearchResult](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/PlayerViewModel.kt:786), [SearchScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/SearchScreen.kt:280) |
| Swap / rollback / serializacja | [moveQueueEntry](D:/Repos/kajutabot-apple/KajutaBot/AppState.swift:482), [queue-all](D:/Repos/kajutabot-apple/KajutaBot/AppState.swift:575) | [QueueMutationCoordinator.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/data/repository/QueueMutationCoordinator.kt:41), [swapEntries](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/PlayerViewModel.kt:995), [QueueSwap.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/QueueSwap.kt) |
| Radio i requeue | [NowPlayingCard](D:/Repos/kajutabot-apple/KajutaBot/Features/Player/PlayerView.swift:141), [toggleRadio](D:/Repos/kajutabot-apple/KajutaBot/AppState.swift:443) | [PlayerScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/PlayerScreen.kt:969), [requeueNowPlaying](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/PlayerViewModel.kt:885) |
| Postęp | [ModelUtilities.swift](D:/Repos/kajutabot-apple/KajutaBot/Core/Models/ModelUtilities.swift) | [PlaybackProgress.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/PlaybackProgress.kt) |
| Realtime / głośność | [RealtimeClient.swift](D:/Repos/kajutabot-apple/KajutaBot/Core/Realtime/RealtimeClient.swift) | [metody huba](D:/Repos/kajutabot-android/api/src/main/kotlin/com/tryniecki/kajutabot/api/client/KajutaBotRealtimeClient.kt:77), [kontroler](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/LocalVolumeController.kt), [specyfikacja](D:/Repos/kajutabot-android/docs/local-volume.md) |
| Sesja i share | [SessionManager.swift](D:/Repos/kajutabot-apple/KajutaBot/Core/Auth/SessionManager.swift:37), [ShareViewController.swift](D:/Repos/kajutabot-apple/KajutaBotShareExtension/ShareViewController.swift:242) | [SharedTrackScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/player/SharedTrackScreen.kt), [SessionManager.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/auth/SessionManager.kt) |
| Ulubione i starszy refresh | [refreshFavoritesAsync](D:/Repos/kajutabot-apple/KajutaBot/AppState.swift:783), [FavoritesView.swift](D:/Repos/kajutabot-apple/KajutaBot/Features/Favorites/FavoritesView.swift) | [FavoritesViewModel.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/favorites/FavoritesViewModel.kt), [FavoritesScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/favorites/FavoritesScreen.kt) |
| Pomoc / telemetry / testy | [OnboardingView.swift](D:/Repos/kajutabot-apple/KajutaBot/Features/Onboarding/OnboardingView.swift:10), [Diagnostics.swift](D:/Repos/kajutabot-apple/KajutaBot/Core/Diagnostics.swift), [testy](D:/Repos/kajutabot-apple/KajutaBotTests/KajutaBotTests.swift) | [OnboardingScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/onboarding/OnboardingScreen.kt:74), [MoreScreen.kt](D:/Repos/kajutabot-android/app/src/main/java/com/tryniecki/kajutabot/ui/more/MoreScreen.kt:196) |
