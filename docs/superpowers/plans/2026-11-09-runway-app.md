# Runway – Flutter appka Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android appka, která po zadání statického hesla stáhne `entries.json` z kontejneru `app` a na jedné obrazovce (mockup A) ukáže runway ve třech scénářích podle nastaveného nového příjmu.

**Architecture:** Výpočet je čistá Dart funkce nad parsovaným dokumentem (`domain/`) a nese většinu testů. Načítání dat (`data/`) jde přes HTTP GET se SAS URL a s cache v souboru. UI používá jeden `ChangeNotifier` (`AppState`) a dvě obrazovky. Tajné hodnoty přicházejí při buildu přes `--dart-define-from-file=.dart-defines.json`.

**Tech Stack:** Flutter (stable), Dart 3, balíčky `http`, `crypto`, `shared_preferences`, `path_provider`, `intl`. Testy: `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-09-runway-design.md` (sekce „Appka – chování“, „Bezpečnost appky“)
**Mockup A:** `.superpowers/brainstorm/20169-1794180380/content/main-screen.html` (první karta)

## Global Constraints

- Jen Android. Výstupem je release APK pro ruční instalaci.
- Appka jen čte. Nikdy nezapisuje na ABS.
- V kódu ani v repu není SAS ani heslo. Build-time defines jsou `RUNWAY_SAS_URL`, `RUNWAY_PASSWORD_SALT` a `RUNWAY_PASSWORD_HASH` (hex SHA-256 z `salt + heslo`, UTF-8).
- Vstupy: nový příjem 0–100 000 Kč (posuvník s krokem 1 000 a pole pro přesnou hodnotu), úspory (default `initialBalance`, lze přepsat), období 3/6/12/24 měsíců (default 12), přepínač „započítat nečekané výdaje“ (default vypnuto). Vše se pamatuje v `shared_preferences`.
- Scénáře a texty karet: „Utrácíme jako dosud“, „Bez zbytných“, „Jen nezbytné“. Barvy podle mockupu A: červená `#C0504D`, oranžová `#D89A2B`, zelená `#4A9A5A`.
- Počítá se jen s `currency == "CZK"`. Typy z `modelConfig.excludedTypes` se do výdajů nezapočítávají. Nekategorizované výdaje se počítají jako `nezbytné`. Nepravidelné příjmy se nepočítají.
- Okno průměru: konec = měsíc posledního záznamu, pokud je den ≥ 25, jinak předchozí měsíc. Okno má N měsíců včetně konce. Dělitel = počet měsíců v okně s aspoň jedním (CZK) záznamem.
- Runway = úspory ÷ (měsíční výdaj scénáře − nový příjem). Jmenovatel ≤ 0 → „∞ – vystačí“. Úspory ≤ 0 → 0 měsíců.

## Review Focus

1. Dokument bez záznamů v okně (např. období 3 měsíce a staré výpisy) → karty ukážou „Žádná data v období“, žádné dělení nulou → test v Task 2.
2. `entries.json` ještě neexistuje (HTTP 404) nebo není síť a cache je prázdná → obrazovka s chybou a tlačítkem „Zkusit znovu“, žádný pád → test v Task 3.
3. Neznámé nebo chybějící pole v JSONu (`category: null`, chybějící `modelConfig`, chybějící `currency`) → parser je tolerantní → test v Task 1.
4. Pole pro přesný příjem: prázdné, záporné, nečíselné nebo nad 100 000 → hodnota se ořízne do rozsahu a posuvník se nerozbije → test v Task 4.
5. Expirovaný SAS (HTTP 403) → hláška „Přístup k datům vypršel“ a fallback na cache → test v Task 3.

---

### Task 0: Prostředí a projekt

- [ ] **Step 1: Prerekvizity (uživatel)** – Flutter SDK (stable) a Android Studio (Android SDK, cmdline-tools) nejsou nainstalované. Požádat uživatele o instalaci, např. `winget install Google.AndroidStudio` a Flutter z https://docs.flutter.dev/get-started/install/windows. Pak `flutter doctor --android-licenses`.
- [ ] **Step 2:** Ověřit `flutter doctor`. Toolchain Flutter a Android musí být ✓.
- [ ] **Step 3:** `flutter create --org cz.runway --project-name runway_app --platforms android app`. Přidat závislosti z Tech Stack (`flutter pub add ...`). V `android/app/src/main/AndroidManifest.xml` zkontrolovat permission `INTERNET` (release ho potřebuje).
- [ ] **Step 4:** `app/tool/hash_password.dart`: `dart run tool/hash_password.dart <heslo>` vygeneruje náhodnou 16bajtovou sůl (hex). Vypíše ji a zároveň ji spolu s hashem sloučí do `app/.dart-defines.json` a zachová `RUNWAY_SAS_URL`.
- [ ] **Step 5:** `cd app && flutter test` (výchozí widget test smazat) → `No tests ran` / zelené. Commit `chore(app): scaffold flutter project`.

### Task 1: Model dokumentu

**Files:**
- Create: `app/lib/data/entries_document.dart`, `app/test/entries_document_test.dart`

**Interfaces:**
- Produces:
  - `class AppEntry { final DateTime date; final int amountCents; final String currency; final String? categoryKind; final String? expenseType; final String? need; final String? incomeType; }`
  - `class EntriesDocument { final double initialBalance; final String? updatedAt; final List<AppEntry> entries; final Set<String> excludedTypes; factory EntriesDocument.fromJson(Map<String, dynamic>); }`
  - `amountCents = (amount * 100).round()`. Chybějící `currency` → `"CZK"`. Chybějící `modelConfig` → prázdná množina.
- [ ] **Step 1: Failing tests:**
  - `parses spec example`: JSON příklad ze specu doplněný o `category: {"kind":"expense","type":"energie","need":"nezbytné"}` → `amountCents == -153500`, `need == "nezbytné"`, `initialBalance == 420000`.
  - `tolerates null category and missing modelConfig`.
  - `reads excludedTypes`.
- [ ] **Step 2:** `flutter test test/entries_document_test.dart` → FAIL.
- [ ] **Step 3:** Implementovat.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat(app): entries document model`.

### Task 2: Výpočet runway

**Files:**
- Create: `app/lib/domain/runway_calculator.dart`, `app/test/runway_calculator_test.dart`

**Interfaces:**
- Consumes: `EntriesDocument`, `AppEntry` (Task 1)
- Produces:
  - `enum Scenario { asUsual, withoutDiscretionary, essentialOnly }`
  - `class RunwayInput { final double savings; final double newMonthlyIncome; final int windowMonths; final bool includeUnexpected; final DateTime today; }`
  - `class ScenarioResult { final Scenario scenario; final double monthlySpend; final double? runwayMonths /* null = ∞ */; final DateTime? depletionDate; final Map<String, double> monthlyByType; }`
  - `class RunwayResult { final List<ScenarioResult> scenarios /* pořadí enumu */; final int monthsWithData; final int windowMonths; final double regularMonthlyIncome; final int uncategorizedCount; final int nonCzkCount; final bool hasData; }`
  - `RunwayResult calculateRunway(EntriesDocument doc, RunwayInput input)`
- Potřeby ve scénářích: `asUsual` = {nezbytné, vhodné, zbytné}, `withoutDiscretionary` = {nezbytné, vhodné}, `essentialOnly` = {nezbytné}. Když je `includeUnexpected`, přidá se do všech tří `nečekané`. Nekategorizovaný výdaj (`categoryKind == null && amountCents < 0`) se počítá jako `nezbytné` s typem `"nezařazeno"`.
- `depletionDate` = `today` + celé měsíce (kalendářně) + `round(zbytek × 30)` dní.

- [ ] **Step 1: Failing tests** (helper `e(date, kč, {need, type, incomeType})`):
  - `window ends in last month when last entry day >= 25`: poslední záznam 2026-10-27, okno 3 → měsíce 8, 9, 10.
  - `window ends previous month when last entry day < 25`: poslední 2026-10-10 → 7, 8, 9.
  - `divides by months with data`: okno 12, data jen ve 2 měsících, výdaje nezbytné 20 000 a 10 000 → `monthlySpend` u `essentialOnly` = 15 000, `monthsWithData == 2`.
  - `scenario sums`: v jednom měsíci nezbytné 10 000, vhodné 5 000, zbytné 3 000, nečekané 2 000 → bez přepínače 18 000 / 15 000 / 10 000, s přepínačem 20 000 / 17 000 / 12 000.
  - `runway`: úspory 300 000, výdaj 25 000, příjem 10 000 → `runwayMonths == 20`. `today = 2026-11-09` → `depletionDate == 2028-07-09`.
  - `infinite when income covers spend` → `runwayMonths == null`.
  - `zero savings → 0 months`.
  - `excluded types and non-CZK ignored, counted`: „spoření a investice“ −50 000 se nezapočítá. EUR záznam → `nonCzkCount == 1`.
  - `uncategorized counted as essential`.
  - `regular income only`: pravidelný 60 000 + nepravidelný 3 000 v jednom měsíci → `regularMonthlyIncome == 60000`.
  - `no data in window` → `hasData == false`, `runwayMonths` všech `null`, bez výjimky.
- [ ] **Step 2:** `flutter test test/runway_calculator_test.dart` → FAIL.
- [ ] **Step 3:** Implementovat.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat(app): runway calculator`.

### Task 3: Načítání dat a heslo

**Files:**
- Create: `app/lib/config.dart`, `app/lib/data/repository.dart`, `app/lib/auth/password.dart`, `app/test/repository_test.dart`, `app/test/password_test.dart`

**Interfaces:**
- Produces:
  - `config.dart`: `const sasUrl = String.fromEnvironment('RUNWAY_SAS_URL')`, `passwordSalt`, `passwordHash` (stejným způsobem).
  - `bool verifyPassword(String input, {required String salt, required String hash})` – SHA-256 hex z `utf8(salt + input)`, porovnání bez ohledu na velikost písmen.
  - `blobUrl(String containerSasUrl, String blob) -> Uri` – vloží `/<blob>` před `?`.
  - `sealed class LoadResult`: `Loaded(EntriesDocument doc, {required bool fromCache, String? warning})` | `LoadFailed(String message)`
  - `class EntriesRepository { EntriesRepository({required http.Client client, required String sasUrl, required Future<File> Function() cacheFile}); Future<LoadResult> load(); }` – GET `entries.json`. Při 200 uloží tělo do cache a vrátí `Loaded(fromCache: false)`. Jinak vrátí cache s `warning` (403 → „Přístup k datům vypršel“, 404 → „Data zatím nejsou nahraná“, výjimka → „Offline – zobrazuji uložená data“). Bez cache vrátí `LoadFailed` se stejnou hláškou.
- [ ] **Step 1: Failing tests** (`MockClient` z `package:http/testing.dart`, cache v `Directory.systemTemp.createTemp()`):
  - `blobUrl inserts blob before query`: `https://a.blob.core.windows.net/app?sv=1&sig=x` → `https://a.blob.core.windows.net/app/entries.json?sv=1&sig=x`.
  - `200 caches and returns`.
  - `403 falls back to cache with warning`.
  - `404 without cache → LoadFailed("Data zatím nejsou nahraná")`.
  - `socket exception without cache → LoadFailed`.
  - `verifyPassword`: sůl `"ab"`, heslo `"heslo"` → hash spočítaný v testu přes `crypto` → `true`; špatné heslo → `false`.
- [ ] **Step 2:** `flutter test` → FAIL.
- [ ] **Step 3:** Implementovat.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat(app): data repository and password check`.

### Task 4: Stav, obrazovky a build

**Files:**
- Create: `app/lib/state/app_state.dart`, `app/lib/ui/login_screen.dart`, `app/lib/ui/home_screen.dart`, `app/lib/ui/scenario_card.dart`, `app/test/app_state_test.dart`, `app/test/home_screen_test.dart`
- Modify: `app/lib/main.dart`, `README.md` (sekce Appka)

**Interfaces:**
- Consumes: `calculateRunway`, `RunwayInput`, `RunwayResult` (Task 2), `EntriesRepository`, `LoadResult`, `verifyPassword` (Task 3)
- Produces: `class AppState extends ChangeNotifier`
  - pole: `loggedIn`, `load` (`LoadResult?`), `newIncome`, `savingsOverride` (`double?`), `windowMonths`, `includeUnexpected`
  - getter `RunwayResult? result`
  - metody: `login(String) -> bool`, `logout()`, `refresh()`, `setNewIncome(double)` (clamp 0–100 000), `setSavings(double?)` (`null` = zpět na `initialBalance`), `setWindow(int)`, `setIncludeUnexpected(bool)`
  - vše kromě `load` se persistuje přes `SharedPreferences` (v testech `SharedPreferences.setMockInitialValues`)

**UI podle mockupu A:**
- Login: pole pro heslo a tlačítko. Při chybě „Nesprávné heslo“.
- Home: AppBar „Runway“ s akcemi obnovit a odhlásit. Pull-to-refresh.
- Případný `warning` / `updatedAt` se zobrazí jako banner.
- Vstupy:
  - nový příjem: `Slider` (divisions 100) + `TextField` s číselnou klávesnicí
  - úspory: `TextField` s ikonou reset
  - období: `SegmentedButton` 3/6/12/24
  - přepínač „Započítat nečekané výdaje“
- Řádek „Dosavadní pravidelný příjem: X Kč/měs.“
- Tři `ScenarioCard`: popisek a „X Kč/měs.“, velké číslo „12,8 měs.“ nebo „∞ – vystačí“, „do února 2028“ (`intl`, locale `cs`). Po klepnutí se rozbalí `monthlyByType` seřazené sestupně.
- Pod kartami poznámky: „Průměr ze N měsíců s daty“ (+ upozornění, když je jich méně než okno), počet nezařazených a ne-CZK záznamů.
- `hasData == false` → místo karet text „Žádná data v období“.

- [ ] **Step 1: Failing tests:**
  - `app_state_test`: `setNewIncome(-5)` → 0, `setNewIncome(250000)` → 100000. Nastavení přežije nový `AppState` (stejné mock prefs). `login` špatně → `false`, správně → `true` a `loggedIn` se persistuje.
  - `home_screen_test` (widget, `AppState` s fake repository vracejícím dokument se 2 měsíci dat): najde texty „Utrácíme jako dosud“, „Bez zbytných“, „Jen nezbytné“. Zadání `200000` do pole příjmu → hodnota 100 000 a karty ukazují „∞ – vystačí“. Dokument bez dat → „Žádná data v období“.
- [ ] **Step 2:** `flutter test` → FAIL.
- [ ] **Step 3:** Implementovat stav a UI. `main.dart`: `initializeDateFormatting('cs')`, `ChangeNotifierProvider`-less: `ListenableBuilder` nad `AppState`.
- [ ] **Step 4:** `flutter test` → PASS. `flutter analyze` → `No issues found!`.
- [ ] **Step 5: Build:** `dart run tool/hash_password.dart <heslo od uživatele>` (heslo zadá uživatel přes `!`, agent ho nepíše do souborů), pak `flutter build apk --release --dart-define-from-file=.dart-defines.json` → `build/app/outputs/flutter-apk/app-release.apk`. README: postup buildu a instalace (`adb install` nebo zkopírovat APK do telefonu a povolit instalaci z neznámých zdrojů). Release podpis: debug klíč stačí pro ruční instalaci (moje volba).
- [ ] **Step 6:** Commit `feat(app): ui and release build`.
