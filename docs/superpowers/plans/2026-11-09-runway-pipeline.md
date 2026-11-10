# Runway – import a kategorizace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Python CLI `runway import` (výpisy z `upload/inbox/` → deduplikovaný `app/entries.json`) a `runway categorize` (doplnění kategorií přes Azure OpenAI).

**Architecture:** Balíček `runway` v `pipeline/` (uv). Čisté jádro (parsery, ID, merge, kategorizace) pracuje s dataclassy a bytes. Přístup k ABS a LLM je za malými protokoly, testy používají in-memory fake. CLI jen skládá dohromady konfiguraci z `.env`, reálný store a reálného klienta.

**Tech Stack:** Python 3.12+ (na stroji 3.14), uv, `azure-storage-blob`, `openai` (`AzureOpenAI`), `python-dotenv`, pytest.

**Spec:** `docs/superpowers/specs/2026-11-09-runway-design.md`

## Global Constraints

- Výstupní dokument má přesně tvar ze sekce „Formát `entries.json`“ ve specu (`version: 1`, `initialBalance`, `initialBalanceCurrency`, `updatedAt`, `entries[]`). Navíc přibude `modelConfig: {"excludedTypes": [...]}` (zapisuje `categorize`, čte appka).
- Částky se interně počítají v haléřích (`int`). V JSONu je `amount` číslo se 2 desetinnými místy, výdaje záporné.
- Importer nikdy nepřepisuje `initialBalance` ani existující záznamy (včetně `category`).
- `id` = SHA-256 (hex) z `date|amount_cents|currency|ownAccount|counterAccount|counterBankCode|message|note|type|n`. `None` se zapisuje jako `""`. `n` je pořadí identického záznamu v rámci jednoho souboru.
- Potřeby (`need`): `nezbytné`, `vhodné`, `zbytné`, `nečekané`. Typ příjmu (`incomeType`): `pravidelný`, `nepravidelný`.
- `kind`: `amount_cents < 0` → `expense`, jinak `income`. Určuje se deterministicky, ne přes LLM.
- Zápis `entries.json` vždy s `if_match` na ETag (nebo `if_none_match="*"` při vytvoření). Při konfliktu skript skončí chybou a nic nepřesouvá.
- Proměnné prostředí: `AZURE_STORAGE_CONNECTION_STRING`, `RUNWAY_UPLOAD_CONTAINER` (default `upload`), `RUNWAY_APP_CONTAINER` (default `app`), `RUNWAY_OWN_ACCOUNT` (volitelné), `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_DEPLOYMENT`.

## Review Focus

1. Soubor v `inbox/`, který nejde rozparsovat (poškozený, neznámá přípona, prázdný), nesmí zablokovat ostatní soubory. Zůstane v `inbox/` a vypíše se → test v Task 5.
2. CSV, které obsahuje jen hlavičku, dá 0 záznamů bez chyby. Částka s mezerou nebo NBSP jako oddělovačem tisíců (`"-12 345,50"`) se načte správně → testy v Task 2.
3. První běh bez `entries.json` vytvoří dokument s `initialBalance: 0` a upozorní na to. Další běh `initialBalance` ručně doplněný uživatelem zachová → test v Task 4.
4. LLM vrátí neplatnou hodnotu, chybějící nebo cizí `i`. Platné záznamy se uloží, neplatné se zopakují jednou a pak zůstanou `null` → test v Task 6.
5. Dvakrát stejný import (překryv celého souboru) nepřidá nic a dvě stejné kávy v jednom souboru zůstanou dvě → test v Task 3.

---

### Task 1: Projekt a model záznamu

**Files:**
- Create: `pipeline/pyproject.toml`, `pipeline/src/runway/__init__.py`, `pipeline/src/runway/entry.py`, `pipeline/tests/test_entry.py`, `pipeline/tests/fixtures/` (kopie `pohyby.csv` a `pohyby.gpc` z kořene)

**Interfaces:**
- Produces:
  - `@dataclass Entry`: `date: datetime.date`, `amount_cents: int`, `currency: str`, `own_account: str | None`, `counter_account: str | None`, `counter_bank_code: str | None`, `message: str`, `note: str`, `type: str`, `variable_symbol: str | None`, `constant_symbol: str | None`, `specific_symbol: str | None`, `bank_transaction_id: str | None`, `source: dict`, `id: str = ""`, `category: dict | None = None`
  - `Entry.to_dict() -> dict` (camelCase klíče podle specu, `amount` = `amount_cents / 100`), `Entry.from_dict(d: dict) -> Entry`
  - `normalize_account(raw: str | None) -> str | None`: odstraní `/kód banky` a bílé znaky. `"000107-2000145399"` → `"107-2000145399"`, `"0000001234567890"` → `"1234567890"`, `""` a `"0"` → `None`. Interně: rozdělí na prefix (max 6) a číslo (10), odstraní úvodní nuly a nulový prefix vynechá.

- [ ] **Step 1:** `uv init --package --name runway pipeline`, přidat závislosti `azure-storage-blob openai python-dotenv` a dev `pytest`. Do `[project.scripts]` přidat `runway = "runway.cli:main"`.
- [ ] **Step 2: Failing test** – `test_roundtrip`: `Entry.from_dict(e.to_dict()) == e`; `e.to_dict()["amount"] == -1535.0` pro `amount_cents=-1535_00`. `test_normalize_account` s hodnotami z rozhraní výše.
- [ ] **Step 3:** `cd pipeline && uv run pytest tests/test_entry.py -v` → FAIL (import error).
- [ ] **Step 4:** Implementovat `entry.py`.
- [ ] **Step 5:** `uv run pytest tests/test_entry.py -v` → PASS.
- [ ] **Step 6: Commit** – `feat(pipeline): entry model`

### Task 2: Parsery Fio CSV a GPC

**Files:**
- Create: `pipeline/src/runway/parsers/__init__.py`, `parsers/fio_csv.py`, `parsers/gpc.py`, `pipeline/tests/test_parsers.py`

**Interfaces:**
- Produces: `parse(data: bytes, filename: str, own_account: str | None) -> list[Entry]` v `runway.parsers`. Vybírá parser podle přípony (`.csv` → `fio-csv`, `.gpc` → `gpc`, case-insensitive). Neznámá přípona → `UnsupportedFormat(Exception)`. Vrácené záznamy už mají `id` (Task 3 `assign_ids`) a `source = {"format": ..., "file": filename}`.
- Consumes: `Entry`, `normalize_account` (Task 1), `assign_ids` (Task 3). Proto se `parse` napojí na `assign_ids` až v Task 3. Do té doby testy kontrolují pole bez `id`.

**Fio CSV:** dekódovat `utf-8-sig`, `csv` s `delimiter=";"`. Mapování: `Datum` (`%d.%m.%Y`) → `date`, `Objem` → `amount_cents` (odstranit mezery a `\xa0`, `,`→`.`, `Decimal`, ×100), `Měna` → `currency`, `Protiúčet` → `counter_account` (normalizovat), `Kód banky` → `counter_bank_code` (prázdný → `None`), `Zpráva pro příjemce` → `message`, `Poznámka` → `note`, `Typ` → `type`. Symboly a ID jsou `None`. `own_account` se bere z parametru (normalizovat).

**GPC (ABO), 0-based řezy řádku:** dekódovat `cp1250`. Když výsledek obsahuje znaky mimo cp1250 nebo dekódování selže, zkusit `utf-8` s `errors="replace"` (ukázka je UTF-8 s U+FFFD). Řádek `074`: `own_account = [3:19]`. Řádek `075`:
- `[19:35]` protiúčet (16 číslic: 6 prefix + 10 číslo) → `normalize_account`
- `[35:48]` `bank_transaction_id` (bez úvodních nul)
- `[48:60]` částka v haléřích
- `[60]` kód účtování: `1`, `5` → záporná částka, `2`, `4` → kladná
- `[61:71]` VS
- `[71:81]` pole KS: `[73:77]` = kód banky protiúčtu (`"0000"` → `None`), `[77:81]` = KS
- `[81:91]` SS
- `[97:117]` text → `note` (rstrip), `message = ""`
- `[117:122]` měna ISO numeric (`"00203"` → `"CZK"`, `978` → `EUR`, `840` → `USD`, jinak číslo jako string)
- `[122:128]` datum `%d%m%y`
- `type = ""`
- Symboly `0`/prázdné → `None`, jinak bez úvodních nul. `own_account` z hlavičky má přednost před parametrem. Jiné typy řádků se ignorují.

- [ ] **Step 1: Failing tests:**
  - `test_fio_csv_sample` (fixture): 4 záznamy. Třetí: `date(2024,1,4)`, `amount_cents == -153500`, `counter_account == "107-2000145399"`, `counter_bank_code == "0100"`, `note.startswith("Elektřina doplatek")`, `type == "Okamžitá odchozí platba"`. První: `amount_cents == -33219`, `counter_account is None`.
  - `test_fio_csv_header_only` → `[]`.
  - `test_fio_csv_thousands_separator`: řádek s `"-12 345,50"` a s `"1\xa0000"` → `-1234550`, `100000`.
  - `test_gpc_sample` (fixture): 3 záznamy. Všechny mají `own_account == "1234567890"`. Třetí: `amount_cents == -153500`, `counter_account == "107-2000145399"`, `counter_bank_code == "0100"`, `bank_transaction_id == "10000000003"`, `variable_symbol == "1234512345"`, `currency == "CZK"`, `date == date(2024,1,4)`.
  - `test_gpc_credit_and_storno`: syntetické řádky `075` s kódy 2, 4, 5 → znaménka `+`, `+`, `-`.
  - `test_gpc_cp1250`: ukázka překódovaná tak, že `"Nákup"` je v bytes cp1250 → `note.startswith("Nákup")`.
  - `test_unknown_extension` → `UnsupportedFormat`.
- [ ] **Step 2:** `uv run pytest tests/test_parsers.py -v` → FAIL.
- [ ] **Step 3:** Implementovat parsery.
- [ ] **Step 4:** `uv run pytest -v` → PASS.
- [ ] **Step 5: Commit** – `feat(pipeline): fio csv and gpc parsers`

### Task 3: ID a merge dokumentu

**Files:**
- Create: `pipeline/src/runway/document.py`, `pipeline/tests/test_document.py`
- Modify: `pipeline/src/runway/parsers/__init__.py` (volat `assign_ids` na výstup)

**Interfaces:**
- Produces:
  - `assign_ids(entries: list[Entry]) -> list[Entry]`: nastaví `id` podle Global Constraints, `n` počítá výskyty stejného základu v pořadí seznamu.
  - `@dataclass Document`: `initial_balance: float`, `initial_balance_currency: str`, `updated_at: str | None`, `entries: list[Entry]`, `model_config: dict`, `extra: dict` (neznámé klíče se zachovají).
  - `Document.new() -> Document` (`initial_balance=0`, `"CZK"`, `model_config={}`)
  - `Document.from_json(data: bytes) -> Document`, `Document.to_json() -> bytes` (UTF-8, `ensure_ascii=False`, `indent=2`, entries seřazené podle `(date, id)`)
  - `merge(doc: Document, new: list[Entry], imported_at: str) -> int`: přidá záznamy s dosud neznámým `id`, nastaví jim `source["importedAt"]` a vrátí počet přidaných. Existující záznamy nemění.

- [ ] **Step 1: Failing tests:**
  - `test_identical_rows_get_distinct_ids`: dva identické záznamy → dvě různá `id`.
  - `test_ids_stable_across_files`: stejný seznam parsovaný dvakrát → stejná `id`.
  - `test_merge_overlap`: merge `[a, b]`, pak `[b, c]` → celkem 3, druhý merge vrátí 1.
  - `test_merge_keeps_category`: existující záznam s `category={...}`, merge jeho kopie bez kategorie → kategorie zůstane.
  - `test_json_roundtrip_preserves_initial_balance_and_unknown_keys`.
- [ ] **Step 2:** `uv run pytest tests/test_document.py -v` → FAIL.
- [ ] **Step 3:** Implementovat. Hash: `hashlib.sha256("|".join(parts).encode()).hexdigest()`.
- [ ] **Step 4:** `uv run pytest -v` → PASS.
- [ ] **Step 5: Commit** – `feat(pipeline): ids, document and merge`

### Task 4: Storage vrstva

**Files:**
- Create: `pipeline/src/runway/storage.py`, `pipeline/tests/fakes.py`, `pipeline/tests/test_storage_fake.py`

**Interfaces:**
- Produces:
  - `class ConcurrencyError(Exception)`
  - `Protocol Store`:
    - `list_inbox() -> list[str]` (názvy blobů pod `inbox/`, bez „složek“)
    - `read_upload(name: str) -> bytes`
    - `move_to_processed(name: str) -> None` (`inbox/x` → `processed/x`; existuje-li cíl, přidá suffix s časovým razítkem)
    - `load_document() -> tuple[Document, str | None]` (ETag; když blob neexistuje → `(Document.new(), None)`)
    - `save_document(doc: Document, etag: str | None) -> str` (nový ETag; nesoulad → `ConcurrencyError`)
  - `AzureBlobStore(connection_string: str, upload_container: str, app_container: str)` – implementace přes `BlobServiceClient`. `entries.json` se nahraje s `content_type="application/json; charset=utf-8"`. Move = `start_copy_from_url` + `delete_blob`; v rámci jednoho účtu je kopírování synchronní, jinak polling.
  - `tests/fakes.py`: `InMemoryStore(Store)` se stejnou sémantikou ETagu.
- [ ] **Step 1: Failing test** (`test_storage_fake.py`): `save_document` se starým ETagem → `ConcurrencyError`; `load_document` na prázdném store → `etag is None` a `initial_balance == 0`; `move_to_processed` dvakrát stejné jméno → obě verze v `processed/`.
- [ ] **Step 2:** `uv run pytest tests/test_storage_fake.py -v` → FAIL.
- [ ] **Step 3:** Implementovat `storage.py` a `fakes.py`.
- [ ] **Step 4:** `uv run pytest -v` → PASS.
- [ ] **Step 5: Commit** – `feat(pipeline): blob storage layer`

### Task 5: Import CLI

**Files:**
- Create: `pipeline/src/runway/importer.py`, `pipeline/src/runway/cli.py`, `pipeline/tests/test_importer.py`

**Interfaces:**
- Produces:
  - `@dataclass ImportReport`: `added: int`, `processed_files: list[str]`, `failed_files: dict[str, str]`, `created_document: bool`
  - `run_import(store: Store, own_account: str | None, now: datetime) -> ImportReport`. Pořadí: načíst dokument → parsovat každý soubor (chyba nebo `UnsupportedFormat` → `failed_files`, pokračovat) → merge → `updated_at` → `save_document` (jen když je co přidat nebo dokument vznikl) → teprve potom `move_to_processed` úspěšně rozparsovaných souborů.
  - `cli.main(argv: list[str] | None = None) -> int`: `argparse` s podpříkazy `import` a `categorize` (ten až v Task 6). `.env` se hledá v `pipeline/` přes `load_dotenv`. Výpis: počet přidaných záznamů, zpracované a selhané soubory. Když `created_document`: `"Vytvořen nový entries.json – doplňte ručně initialBalance."`. Návratový kód 1, pokud selhal aspoň jeden soubor nebo došlo ke `ConcurrencyError`.
- [ ] **Step 1: Failing tests** (s `InMemoryStore`):
  - `test_import_sample_files`: inbox `pohyby.csv` + `pohyby.gpc` → `added == 7`, oba soubory v `processed/`, `created_document`.
  - `test_reimport_adds_nothing`: znovu nahrát `pohyby.csv` → `added == 0`.
  - `test_bad_file_does_not_block`: inbox s `pohyby.csv`, `junk.txt` a `broken.gpc` (náhodné bytes) → `added == 4`, `junk.txt` a `broken.gpc` ve `failed_files` a zůstávají v `inbox/`.
  - `test_initial_balance_preserved`: dokument s `initial_balance=420000` → po importu stále `420000`.
  - `test_concurrency_error_moves_nothing`: store, jehož `save_document` vyhodí `ConcurrencyError` → výjimka se propaguje a inbox je beze změny.
- [ ] **Step 2:** `uv run pytest tests/test_importer.py -v` → FAIL.
- [ ] **Step 3:** Implementovat `importer.py` a `cli.py` (zatím jen `import`).
- [ ] **Step 4:** `uv run pytest -v` → PASS.
- [ ] **Step 5: Commit** – `feat(pipeline): import command`

### Task 6: Kategorizace

**Files:**
- Create: `pipeline/config/categories.json`, `pipeline/src/runway/categories.py`, `pipeline/src/runway/categorizer.py`, `pipeline/tests/test_categorizer.py`
- Modify: `pipeline/src/runway/cli.py` (podpříkaz `categorize [--all] [--batch-size 30]`)

**`config/categories.json`** – `expenseTypes` (`id`, `description`, volitelně `excludeFromModel`), `needs` (`id`, `description`), `incomeTypes` (`id`, `description`). Typy výdajů a jejich ID přesně podle specu: `bydlení`, `energie`, `živobytí`, `doprava`, `zdraví`, `děti`, `pojištění`, `poplatky a předplatné`, `komunikace`, `oblečení`, `volný čas`, `dovolená`, `dary`, `spoření a investice` (`excludeFromModel: true`), `ostatní`. Popisy jsou krátké, česky, s příklady.
- `nečekané`: „jednorázový neplánovaný výdaj – oprava auta, spotřebiče, náhlý zdravotní výdaj“.
- `pravidelný`: „výplata, přeposlaná výplata, pravidelný příjem“.
- `nepravidelný`: „přeplatky, vratky, reklamace, jednorázové příjmy“.

**Interfaces:**
- Produces:
  - `load_categories(path: Path) -> CategoryConfig` (dataclass: `expense_types: list[dict]`, `needs: list[dict]`, `income_types: list[dict]`, `excluded_types: list[str]`)
  - `Protocol LlmClient`: `complete_json(system: str, user: str, schema: dict) -> dict`
  - `AzureLlmClient(endpoint, api_key, deployment)`: `AzureOpenAI(...).chat.completions.create(model=deployment, messages=[...], response_format={"type": "json_schema", "json_schema": {"name": "result", "strict": True, "schema": schema}}, temperature=0)` → `json.loads(content)`. Verze API bude parametr s rozumným defaultem.
  - `categorize(entries: list[Entry], cfg: CategoryConfig, llm: LlmClient, batch_size: int, now: str, model: str, on_batch: Callable[[], None]) -> list[Entry]` – vrátí záznamy, které zůstaly bez kategorie. Záznamy se rozdělí podle `kind`. Výdaje dostanou schéma `{"items": [{"i": int, "type": enum(expense ids), "need": enum(needs)}]}`, příjmy `{"items": [{"i": int, "incomeType": enum}]}`. `i` je index v dávce. Odpovědi s neznámým `i` nebo neplatnou hodnotou se ignorují. Chybějící záznamy se zopakují jednou v nové dávce. Výsledek zapíše `category = {"kind", "type"/"need" nebo "incomeType", "model", "categorizedAt"}`. `on_batch` se volá po každé dávce, kvůli průběžnému uložení.
  - CLI `categorize`: `load_document` → vybrat záznamy s `category is None` (`--all`: všechny, kategorie se nejprve vymaže) → `categorize(..., on_batch=uložit)` s aktualizací ETagu → nastavit `doc.model_config["excludedTypes"]` → uložit. Vypsat počet kategorizovaných a nekategorizovaných.
- LLM prompt (system): česky. Úkol, seznam kategorií s popisy z configu, pravidlo „vyber výhradně z uvedených hodnot“. User zpráva: JSON pole `{i, date, amount, counterAccount, message, note, type}`.

- [ ] **Step 1: Failing tests** (s `FakeLlm`, který vrací naskriptované odpovědi a zaznamenává volání):
  - `test_expenses_and_income_split`: 2 výdaje + 1 příjem → 2 volání, výdaje mají `kind == "expense"` a `need`, příjem má `incomeType`.
  - `test_invalid_values_retried_once`: první odpověď dá jednomu záznamu `need: "luxus"` a druhý vynechá. Retry dá jen druhý → první zůstane `None` a je ve vráceném seznamu. Celkem 2 volání.
  - `test_foreign_index_ignored`: odpověď obsahuje `i: 99` → ignorováno, bez výjimky.
  - `test_schema_enums_from_config`: schéma předané LLM obsahuje přesně `id` z configu.
  - `test_batching`: 65 výdajů, `batch_size=30` → 3 volání, `on_batch` zavolán 3×.
  - `test_categories_json_valid`: skutečný `config/categories.json` se načte. `excluded_types == ["spoření a investice"]`, `needs` jsou přesně 4 hodnoty z Global Constraints.
- [ ] **Step 2:** `uv run pytest tests/test_categorizer.py -v` → FAIL.
- [ ] **Step 3:** Implementovat `categories.py`, `categorizer.py` a CLI podpříkaz.
- [ ] **Step 4:** `uv run pytest -v` → PASS.
- [ ] **Step 5: Commit** – `feat(pipeline): llm categorization`

### Task 7: End-to-end proti Azure

Předpoklad: provisioning je aplikovaný a `pipeline/.env` existuje.

**Files:**
- Modify: `README.md` (sekce Pipeline: nahrání do `upload/inbox/`, `uv run runway import`, ruční doplnění `initialBalance`, `uv run runway categorize`)

- [ ] **Step 1:** Nahrát **jen** `pohyby.csv`: `az storage blob upload --connection-string "$AZURE_STORAGE_CONNECTION_STRING" -c upload -n inbox/pohyby.csv -f pohyby.csv`. GPC obsahuje stejné platby a mezi formáty se nededuplikuje, proto ho nenahrávat; GPC pokrývají unit testy.
- [ ] **Step 2:** `cd pipeline && uv run runway import` → výstup obsahuje `4` přidané záznamy a upozornění na `initialBalance`. Po opětovném nahrání `pohyby.csv` druhé spuštění → `0` přidaných.
- [ ] **Step 3:** `uv run runway categorize`. Stáhnout `app/entries.json` a ověřit:
  - všechny 4 záznamy mají `category`
  - nákup v Rossmannu má `type == "živobytí"`
  - elektřina má `energie` a `nezbytné`
  - `modelConfig.excludedTypes` je přítomný
- [ ] **Step 4:** Druhé `uv run runway categorize` → `0` kategorizovaných (žádné LLM volání).
- [ ] **Step 5: Commit** – `docs: pipeline usage`
