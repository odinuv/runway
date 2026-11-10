# Runway domácnosti – návrh

Datum: 2026-11-09

## Záměr

Domácnost chce průběžně plánovat „co kdyby“: kdyby vypadl pravidelný příjem a nahradil ho jiný (nižší) příjem, jak dlouho vydrží úspory? Odpověď má záviset na tom, jak moc se domácnost uskromní. Data pocházejí ze skutečných bankovních výpisů. Výdaje kategorizuje LLM, aby se nemusely třídit ručně. Výsledek se prohlíží v mobilní appce.

Uživatel: kdokoliv, kdo zná statické heslo (v praxi členové domácnosti). Nejde o krizový nástroj. Appka slouží k průběžnému plánování.

## Cíle

1. **Import** – skript načte výpisy z Azure Blob Storage (ABS), rozparsuje je (Fio CSV a ABO/GPC), normalizuje je do jednoho JSONu s polem `entries` a uloží ho zpět na ABS bez duplicit.
2. **Kategorizace** – skript doplní ke každému záznamu kategorii přes Azure AI (Azure OpenAI): typ výdaje, potřebu a u příjmů pravidelnost.
3. **Appka** – Flutter pro Android modeluje runway při novém příjmu ve třech scénářích škrtání.
4. **Provisioning** – Terraform v `provisioning/` založí potřebné Azure zdroje (storage se dvěma kontejnery a Azure OpenAI).

## Non-goals

- Ruční oprava kategorií (v appce ani jinde).
- Zápis z appky na ABS. Appka data jen čte.
- iOS, Google Play a obchody obecně. APK se instaluje ručně.
- Automatické / plánované spouštění skriptů. Skripty se spouštějí ručně.
- Více uživatelů, uživatelské účty a skutečná autentizace.
- Prognózy, inflace a sezónnost. Model je prostý průměr.

## Anti-goals

- Import nesmí zdvojit platby při překrývajících se výpisech. Nesmí ale ani sloučit dvě skutečné stejné platby (dvě kávy po 65 Kč ve stejný den z jednoho výpisu).
- LLM si nesmí vymýšlet kategorie mimo daný seznam.
- Opakované spuštění kategorizace nesmí přepisovat už kategorizované záznamy ani zbytečně platit za LLM volání.
- Credentials zapečené v appce nesmí umožnit data smazat nebo změnit.

## Omezení a vstupy

- Vstupní soubory: `pohyby.csv` a `pohyby.gpc` v kořeni projektu (ukázky).
- **Fio CSV:** UTF-8 s BOM, CRLF, oddělovač `;`, všechny hodnoty v uvozovkách, desetinná čárka, datum `dd.mm.yyyy`. Sloupce: `Datum;Objem;Měna;Protiúčet;Kód banky;Zpráva pro příjemce;Poznámka;Typ`. CSV **neobsahuje vlastní číslo účtu**. U karetních plateb chybí protiúčet.
- **GPC (ABO, Fio):** pevná délka řádků. Záznam `074` je hlavička s vlastním účtem, jménem a zůstatky. Záznamy `075` jsou transakce (vlastní účet, protiúčet, ID transakce, částka v haléřích, kód účtování 1/2/4/5, VS/KS/SS, text max. 20 znaků, měna, datum). Skutečné GPC z Fia je v **windows-1250**. Ukázkový `pohyby.gpc` byl při ukládání poškozen: diakritika je nahrazena znakem U+FFFD. Parser má zkusit cp1250 a při selhání UTF-8 s náhradou znaků.
- Objem dat je malý: stovky až nízké tisíce záznamů ročně. Celý JSON se klidně načítá a přepisuje vcelku.
- Výpisy se nahrávají zřídka a mohou se časově překrývat.

## Rozhodnuté (uživatelem)

- Formát výstupu: JSON s polem objektů `entries`, normalizovaný tak, aby šly přidat i další formáty výpisů.
- Deduplikace: primární klíč může být složený ze všech sloupců.
- Počáteční stav úspor je ručně zapsaná hodnota v JSONu. V appce ji jde při modelování přepsat.
- Kategorie jsou předem daný seznam ve dvou dimenzích. Uživatel ho může později upravit, LLM ho měnit nesmí.
  - **typ** (např. bydlení, živobytí – jídlo a drogerie, …)
  - **potřeba**: `nezbytné` (elektřina), `vhodné` (pojištění), `zbytné` (dovolená), `nečekané` (jednorázové neplánované výdaje, např. oprava)
- U příjmů LLM určí, zda jde o **pravidelný** příjem (výplata, „přeposlaná výplata“), nebo o **nepravidelný** (přeplatek za vodu, vratka reklamace…). Jiné druhy příjmů prakticky nejsou.
- V modelu nový příjem nahrazuje pravidelný příjem.
- Normální měsíční výdaj je průměr za posledních 12 měsíců. Období jde v appce nastavit.
- Importuje se **jeden účet**. Převody mezi vlastními účty domácnosti se proto řešit nemusí. „Přeposlaná výplata“ přichází z cizího účtu a je to pravidelný příjem.
- Azure zdroje zatím neexistují. Vytvoří je Terraform v adresáři `provisioning/`.
- Na ABS budou **dva kontejnery**: jeden pro nahrávání výpisů a druhý, ze kterého si appka stahuje výsledný JSON.
- Appka: Flutter pro Android, APK se instaluje ručně. Credentials k ABS jsou zapečené v appce, přihlašuje se statickým heslem.
- Hlavní obrazovka podle mockupu **A**: nahoře vstupy (nový příjem, úspory, období průměru), pod nimi tři barevné karty scénářů, každá s měsíčním výdajem, počtem měsíců runway a datem, kdy dojdou peníze.
- Tři scénáře: *jako dosud* (všechny výdaje), *bez zbytných* (nezbytné + vhodné), *jen nezbytné*.
- Zahrnutí výdajů s potřebou `nečekané` je volitelné (přepínač v appce).

## Mé volby (možné změnit)

**Architektura a prostředí**
- Skripty v Pythonu 3.12+ (`azure-storage-blob`, `openai` s Azure klientem), v adresáři `scripts/` (nebo jako balíček `runway/` se dvěma CLI příkazy `import` a `categorize`). Spouštějí se ručně z počítače.
- Konfigurace přes proměnné prostředí / `.env`: `AZURE_STORAGE_CONNECTION_STRING`, `RUNWAY_UPLOAD_CONTAINER` (výchozí `upload`), `RUNWAY_APP_CONTAINER` (výchozí `app`), `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_DEPLOYMENT`. Hodnoty jdou vyplnit z výstupů Terraformu.
- Rozložení na ABS:
  - kontejner `upload`:
    - `inbox/` – sem uživatel nahraje výpisy (`*.csv`, `*.gpc`)
    - `processed/` – sem import po úspěšném zpracování soubor přesune
  - kontejner `app`:
    - `entries.json` – výsledný soubor, jediný, který čte appka

**Provisioning (`provisioning/`, Terraform, provider `azurerm`)**
- Resource group, storage account (Standard LRS, privátní kontejnery, bez anonymního přístupu), kontejnery `upload` a `app`.
- Azure OpenAI účet (`azurerm_cognitive_account`, kind `OpenAI`) a jeden model deployment. Název a verze modelu jsou proměnné. Výchozí je aktuální levný „mini“ model, který je v regionu dostupný; konkrétní hodnotu ověří implementace.
- Region je proměnná, výchozí `swedencentral` (široká dostupnost OpenAI modelů v EU).
- SAS token **jen pro čtení** (`r`, případně `l`) na kontejner `app` s platností jako proměnnou (výchozí 2 roky) – výstup označený jako `sensitive`. Z něj se při buildu appky složí URL.
- Výstupy: connection string storage, OpenAI endpoint, API klíč, název deploymentu, SAS URL pro appku. Všechny citlivé výstupy jsou `sensitive`.
- State je lokální (`terraform.tfstate` v `.gitignore`). Jde o jednorázový setup pro jednu domácnost.
- Zápis `entries.json` s optimistickým zámkem přes ETag (`if_match`), aby se dva běhy navzájem nepřepsaly. Při konfliktu skript skončí chybou.

**Formát `entries.json`**

```json
{
  "version": 1,
  "initialBalance": 420000,
  "initialBalanceCurrency": "CZK",
  "updatedAt": "2026-11-09T10:00:00Z",
  "entries": [
    {
      "id": "sha256-hex",
      "date": "2024-01-04",
      "amount": -1535.00,
      "currency": "CZK",
      "ownAccount": "1234567890/2010",
      "counterAccount": "107-2000145399",
      "counterBankCode": "0100",
      "message": "",
      "note": "Elektřina doplatek 01. 12. 2023 - 31. 12. 2023",
      "type": "Okamžitá odchozí platba",
      "variableSymbol": null,
      "constantSymbol": null,
      "specificSymbol": null,
      "bankTransactionId": null,
      "source": { "format": "fio-csv", "file": "pohyby.csv", "importedAt": "…" },
      "category": null
    }
  ]
}
```

- `category` po kategorizaci:
  - výdaj: `{ "kind": "expense", "type": "energie", "need": "nezbytné", "model": "…", "categorizedAt": "…" }`
  - příjem: `{ "kind": "income", "incomeType": "pravidelný" | "nepravidelný", … }`
- Importer `initialBalance` nikdy nepřepisuje. Pokud soubor ještě neexistuje, vytvoří ho s `initialBalance: 0` a vypíše upozornění, ať ho uživatel doplní ručně (stáhnout, upravit, nahrát).
- Částky se ukládají jako čísla se dvěma desetinnými místy, výdaje záporně. Interně se počítá v haléřích (int), aby nevznikly chyby zaokrouhlení.
- Měna: počítá se jen s CZK. Záznamy v jiné měně se importují, ale appka je ignoruje a zobrazí jejich počet.

**Deduplikace**
- `id` = SHA-256 z normalizovaných polí `date|amount|currency|ownAccount|counterAccount|counterBankCode|message|note|type` + `|n`, kde `n` je pořadí výskytu záznamu s identickými poli v rámci **jednoho** souboru (0, 1, 2…).
- Při mergi se nové záznamy s existujícím `id` přeskočí. Existující záznamy (včetně kategorie) se nemění.
- Vlastní účet u CSV: CSV ho neobsahuje. Protože se importuje jen jeden účet, bere se z volitelné konfigurace `RUNWAY_OWN_ACCOUNT`, jinak zůstane `null`. U GPC se bere z hlavičky `074`. Pozor: aby šly CSV a GPC ze stejného účtu porovnat, musí být `ownAccount` v hashi normalizovaný stejně; pokud není nastaven, hash ho vynechá.
- Známé omezení: stejné období nahrané jednou jako CSV a podruhé jako GPC se jako duplicita **nepozná** (GPC zkracuje text na 20 znaků). Předpoklad: uživatel používá pro dané období jen jeden formát.

**Parsery**
- Rozhraní `parse(bytes, filename) -> list[Entry]` a registr podle přípony / detekce obsahu. Nový formát = nový parser.
- GPC: kód účtování 1 a 5 → záporná částka, 2 a 4 → kladná (storna obrací znaménko; ověřit proti ukázce). ID transakce jde do `bankTransactionId`. Do hashe se nezahrnuje, aby byl klíč stejný pro všechny formáty.

**Kategorizace**
- Seznam kategorií je v `config/categories.json` v repu. Startovní seznam typů výdajů: `bydlení`, `energie`, `živobytí` (jídlo, drogerie), `doprava`, `zdraví`, `děti`, `pojištění`, `poplatky a předplatné`, `komunikace` (telefon, internet), `oblečení`, `volný čas`, `dovolená`, `dary`, `spoření a investice`, `ostatní`. Každý typ má krátký popis pro LLM.
- Typ `spoření a investice` (převody na spořicí účet, investice, penzijní spoření) není spotřeba. Appka ho do výdajů nepočítá v žádném scénáři. Typy vyloučené z modelu jsou v konfiguraci označené příznakem `excludeFromModel`.
- Kategorizují se jen záznamy s `category == null`. Přepínač `--all` překategorizuje vše (pro případ změny seznamu).
- Dávky po ~30 záznamech na jedno volání, structured output (JSON schema s enumy z konfigurace). Odpověď se validuje. Neplatný záznam se zopakuje jednou, pak zůstane `null` a skript ho vypíše.
- LLM dostane datum, částku, protiúčet, zprávu, poznámku a typ transakce. Znaménko částky určuje `kind` (expense/income) deterministicky, LLM ho neurčuje.
- Model určuje deployment z konfigurace (viz Provisioning). Kód na konkrétní model nespoléhá.

**Bezpečnost appky**
- Appka používá SAS token s oprávněním **jen ke čtení** na kontejner `app` (z Terraformu) s dlouhou platností. Token se při buildu předá přes `--dart-define`, není v repu.
- Statické heslo: v appce je uložen jen jeho hash (SHA-256 + sůl). Po správném zadání si ho appka pamatuje (`shared_preferences`), dokud se neodhlásí.
- Je potřeba počítat s tím, že z APK jde token vytáhnout. Únik umožní data číst, ale ne měnit.

**Appka – chování**
- Při startu (a pull-to-refresh) stáhne `entries.json` a uloží ho do lokální cache. Offline ukáže poslední stažená data s datem aktualizace.
- Vstupy:
  - **nový příjem** – posuvník 0–100 000 Kč, krok 1 000, a pole pro přesnou hodnotu
  - **úspory** – výchozí hodnota `initialBalance`, editovatelné
  - **období průměru** – volby 3 / 6 / 12 / 24 měsíců, výchozí 12
  - **přepínač „započítat nečekané výdaje“** – výchozí vypnuto
- Období průměru = posledních N kalendářních měsíců. Okno končí měsícem posledního záznamu, pokud je jeho datum 25. nebo později (měsíc bereme jako kompletní). Jinak končí měsícem předtím.
- Dělí se počtem měsíců v okně, které obsahují aspoň jeden záznam, takže díra ve výpisech nesníží průměr. Když je takových měsíců méně než N, appka na to upozorní.
- Měsíční výdaj scénáře = součet výdajů s danou potřebou za období ÷ počet měsíců.
  - jako dosud: nezbytné + vhodné + zbytné (+ nečekané, pokud je přepínač zapnutý)
  - bez zbytných: nezbytné + vhodné (+ nečekané)
  - jen nezbytné: nezbytné (+ nečekané)
  - nekategorizované výdaje se počítají do všech scénářů jako nezbytné (konzervativně) a appka zobrazí jejich počet
- Runway = úspory ÷ (měsíční výdaj − nový příjem). Pokud je jmenovatel ≤ 0, karta ukáže „∞ – vystačí“. Datum vyčerpání = dnešek + runway měsíců.
- Pravidelný příjem (průměr za období) se zobrazí pro kontext („dosud: 62 000 Kč/měs.“). Nepravidelné příjmy se do výpočtu nezahrnují.
- Klepnutí na kartu rozbalí rozpad měsíčního výdaje scénáře podle typu.
- Nastavené vstupy si appka pamatuje lokálně.

## Nechávám na implementaci

- Přesné rozdělení Python kódu do modulů, testy (pytest, s ukázkovými soubory jako fixtures).
- Flutter state management (stačí jednoduché řešení, např. `ChangeNotifier`), vizuální styl v duchu mockupu A.
- Jak přesně ověřit význam kódů účtování v GPC a pozice polí (podle specifikace ABO formátu a ukázky).
