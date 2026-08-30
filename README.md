<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS: podpisovanie a zaručená konverzia" width="100%">
</p>

# Autogram macOS

Autogram je natívna macOS aplikácia v SwiftUI pre elektronické podpisovanie dokumentov a zaručenú konverziu listinných dokumentov do elektronickej podoby.

`macOS 27 only` · `Swift 6` · `SwiftUI + @Observable` · `0 Swift package dependencies` · `233 tests` · `3 skipped` · `0 failures`

## Čo aplikácia rieši

- **Podpisovanie:** KEP, PAdES, kvalifikovaná časová pečiatka, ASiC-E, vizuálny podpis a dávkové podpisovanie.
- **Zaručená konverzia (ZaKo):** import, analýza, AI Vision, manuálne označenie bezpečnostných prvkov, osvedčovacia doložka, PDF/A-2b, autorizácia mandátnym certifikátom a lokálna evidencia.
- **Register:** lokálne záznamy konverzií, stav odoslania do CEZZK, vyhľadávanie, filtrovanie a CSV export.
- **Nastavenia:** AI Vision providery, PDF/A režim, TSA servery, EZZK prostredia a profily advokáta.
- **Integrácie macOS:** drag and drop, file picker, Finder Quick Action, security-scoped bookmarks a natívne Settings okno.

> **Compliance note:** Aktuálny build je implementačný P2E pilot. Generuje PDF/A-2b, kým externé požiadavky na PDF/A-1a alebo PNG, aktívne verzie formulárov a produkčný EZZK kontrakt nebudú autoritatívne potvrdené a nezávisle overené. P2E cieľová doložka je oficiálna verzia v1.3, zatiaľ čo aktuálny konverzný záznam je verzia 1.0. Porovnanie a plán sú v [`Autogram/docs/P2E-EZZK-FINDINGS.md`](Autogram/docs/P2E-EZZK-FINDINGS.md) a [`Autogram/docs/superpowers/plans/2026-08-29-ezzk-oauth-rest-ui.md`](Autogram/docs/superpowers/plans/2026-08-29-ezzk-oauth-rest-ui.md).

## Rýchly prehľad

| Oblasť | Stav v aktuálnom builde |
|---|---|
| Natívne UI | SwiftUI, `NavigationSplitView`, `@Observable`, macOS 27 |
| Podpisovanie | Jednotlivé dokumenty, Finder dávka, manuálna kontrola preflightu |
| Formáty | KEP, PAdES, ASiC-E, QTS, vizuálny podpis |
| ZaKo | Päť krokov od importu po dokončenie |
| AI Vision | On-device baseline, oMLX, Ollama, vlastné OpenAI-compatible API |
| PDF/A | Vektorový a rasterizovaný režim, PDF/A-2b pilotný profil |
| Register | `register.json` v Application Support, CSV export |
| EZZK | Demo mock, typed OAuth2 klient a guarded transport |
| Verifikácia | 233 testov, 3 voliteľné live engine testy skipped, 0 failures |

Implementačná dokumentácia: [`docs/PHASES.md`](docs/PHASES.md)

Aktuálny UX a workflow plán: [`Autogram/docs/superpowers/plans/2026-08-30-sidebar-vision-batch-plan.md`](Autogram/docs/superpowers/plans/2026-08-30-sidebar-vision-batch-plan.md)

Diagramová galéria: [`docs/gallery.html`](docs/gallery.html)

## Požiadavky

- macOS 27 alebo novší
- Apple Silicon alebo Intel Mac podporovaný použitým Xcode toolchainom
- Xcode 26.5 a Swift 6 pre zostavenie zo zdrojov
- pre reálny podpis: kompatibilná eID karta, advokátsky preukaz alebo iný PKCS#11, CryptoTokenKit alebo Keychain token
- pre produkčné CEZZK odoslanie: EZZK účet, potvrdený native OAuth callback, sandboxové overenie a sieťové pripojenie k príslušnej službe
- pre PDFBox normalizáciu: nainštalovaný Autogram macOS 2 engine s Java runtime; bez neho sa použije lokálny fallback iba vtedy, ak výsledok prejde lokálnou kontrolou

Aplikácia je cielene zostavená pre macOS 27. `Package.swift` preto deklaruje platformu `.macOS("27.0")` a build script zapisuje `LSMinimumSystemVersion=27.0`.

## Pracovné režimy

### Podpisovanie

1. Otvorte PDF cez `⌘O`, vložte ho drag and drop alebo použite Finder Quick Action.
2. Pri viacerých súboroch vyberte **Pripraviť dávku podpisov** a prejdite preflight kontrolou.
3. Zvoľte formát podpisu: KEP, PAdES alebo ASiC-E, podľa dostupných možností aj QTS.
4. Voliteľne zapnite vizuálny podpis a upravte jeho vzhľad a umiestnenie.
5. Vyberte podpisovú identitu a spustite **Podpísať KEP** (`⌘⏎`) alebo dávku potvrďte v sticky action bare.
6. Aplikácia použije CryptoTokenKit, Keychain identitu alebo EngineBridge s PKCS#11 fallbackom.
7. Výsledok zobrazí podpísaný dokument, stav podpisu a dostupné PDF, XML a ASiC-E artefakty.

Dávkové podpisovanie má oddelené fázy preflight, ready, signing a summary. Počas spracovania je možné dávku zastaviť alebo zrušiť. Chyba jedného dokumentu ponúkne opakovanie alebo pokračovanie. Výstupy používajú collision-safe názvy a nikdy ticho neprepíšu existujúci súbor.

Ak nie je dostupný reálny token, aplikácia použije jasne označený DEMO podpisovač. DEMO podpis nie je právne záväzný.

### Zaručená konverzia

ZaKo používa päť krokov:

1. **Import:** vstupný PDF alebo obrazový sken a potvrdenie originálu alebo úradne osvedčenej kópie.
2. **Analýza:** formát strán, neprázdne strany, listy a návrh názvu dokumentu.
3. **Označenie:** AI Vision a manuálne označenie podpisov, pečiatok, reliéfnych pečatí, paraf a iných prvkov.
4. **Osvedčovacia doložka:** údaje osoby, počítadlá, lokalizácia prvkov, XML náhľad a právny preflight.
5. **Autorizácia a dokončenie:** evidenčné číslo cez explicitnú EZZK akciu, dôveryhodný serverový čas, PDF/A, podpis, lokálna evidencia a odoslanie do CEZZK až po validácii podpísaných ASiC artefaktov a potvrdeného receipt.

Odoslanie do CEZZK je oddelené od vytvorenia súborov. Aktuálna OAuth integrácia má typed transport a guarded UI, ale produkčné odoslanie zostáva fail-closed, kým workflow nevytvorí a nevaliduje samostatný podpísaný record ASiC a kým nebude potvrdený sandboxový receipt kontrakt.

### Procesný diagram

<img src="docs/diagrams/process-zako.svg" alt="Procesný tok zaručenej konverzie" width="100%">

| Krok | Činnosť | Vykonáva |
|---|---|---|
| 01 | Import skenu alebo dokumentu a potvrdenie pôvodu | advokát |
| 02 | Analýza strán, listov a formátu | Autogram |
| 03 | AI Vision a manuálne označenie bezpečnostných prvkov | Autogram + advokát |
| 04 | Osvedčovacia doložka a právny preflight | Autogram + advokát |
| 05 | Evidenčné číslo a dôveryhodný serverový čas | IS EZZK |
| 06 | PDF/A-2b, XML príloha a finálna validácia | Autogram |
| 07 | KEP s mandátnym certifikátom a QTS | advokát |
| 08 | Lokálna evidencia a odoslanie do 24 hodín | CEZZK |

## AI Vision

<img src="docs/diagrams/ai-vision.svg" alt="AI Vision detekcia bezpečnostných prvkov" width="100%">

Vstavaný detector pracuje lokálne na zariadení. Používa Apple Vision na vylúčenie textových riadkov a čiarových kódov, farebné a tmavé masky, connected components a konzervatívne geometrické filtre. Detekcia sa analyzuje na šírke 760 px, farebná maska používa saturáciu `s > 0.18` a rasterizačný režim PDF/A používa 200 dpi.

Výsledkom sú `SecurityElement` záznamy s:

- typom prvku a stranou,
- normalizovaným bounding boxom,
- mierou istoty,
- slovným opisom v slovenčine,
- pôvodom nálezu a možnosťou manuálnej úpravy.

Vstavané pravidlá bežia vždy. Voliteľné LLM režimy sú **oMLX**, **Ollama** a vlastné OpenAI-compatible API. Pri vlastnom cloudovom API môže obraz dokumentu opustiť Mac, preto treba endpoint a režim zvoliť podľa požiadaviek na ochranu údajov. K dispozícii sú predvoľby pre právne dokumenty, konzervatívnu kontrolu, podpisy a parafy, pečiatky a reliéfne prvky aj vlastný prompt.

## PDF/A a osvedčovacia doložka

<img src="docs/diagrams/pdfa-pipeline.svg" alt="Dátové toky PDF/A konvertora" width="100%">

ZaKo vytvorí najprv intermediárny PDF/A-2b. Vektorový režim zachováva textovú vrstvu. Rasterizovaný režim vyrenderuje každú stranu pri 200 dpi a vytvorí stabilný obrazový PDF.

Aktívna pipeline je:

```text
PDF/A konverzia
  -> SHA-256 intermediárneho PDF/A
  -> XML ConversionRecord 1.0
  -> EmbeddedFile osvedcovacia-dolozka.xml
  -> finálna normalizácia PDF/A (PDFBox, ak je dostupný)
  -> lokálna kontrola finálneho artefaktu
  -> KEP/QTS, ASiC-E a lokálna evidencia
```

Hash sa počíta z konvertovaných PDF/A bajtov pred vložením XML. Finálny dokument však validujeme až po vložení XML, pretože príloha je súčasťou artefaktu, ktorý používateľ podpisuje a odovzdáva.

PDF obsahuje asociovaný súbor cez `/AF` a `/AFRelationship /Data`. Samostatná doložka sa zapisuje ako `.xml.xdcf`. Ak podpisový provider vráti ASiC-E, vytvorí sa aj `.asice` kontajner s PDF/A a doložkou.

`PDFAValidator` kontroluje štruktúru a stabilné PDF/A kontrakty: hlavičku, EOF, `startxref`, XMP `pdfaid`, OutputIntent, ICC profil, šifrovanie, JavaScript a asociáciu EmbeddedFile. Nie je to úplná náhrada za veraPDF alebo Acrobat Preflight, preto sa pri release validácii odporúča aj externý nástroj.

## Výstupy a bezpečné umiestnenie

ZaKo sa pokúsi uložiť výstupy do zapisovateľného priečinka zdrojového dokumentu. Ak zdrojový priečinok nie je zapisovateľný alebo import nemá použiteľný security scope, použije sa:

```text
~/Library/Application Support/Autogram/Output
```

Typické názvy:

```text
diplom.pdf                  -> diplom-konvertovane.pdf
diplom.pdf + nový názov     -> diplom-novy-nazov.pdf
pôvod.pdf                   -> pôvod_podpisane.pdf
```

Generované artefakty:

- `{dokument}.pdf`: finálny podpísaný PDF/A-2b alebo podpisový formát podľa voľby,
- `{dokument}-{evidenčné-číslo}.xml.xdcf`: samostatná osvedčovacia doložka,
- `{dokument}.asice`: voliteľný ASiC-E výstup podľa podpisového providera.

Pri existujúcom súbore sa použije collision-safe suffix, napríklad `(2)`, aby sa pôvodný artefakt neprepísal. Výber cez file picker, drag and drop a Finder Quick Action zachováva zdrojový priečinok počas dokumentovej session pomocou security-scoped access.

Nedávno otvorené dokumenty sa ukladajú iba ako bezpečné security-scoped bookmarky. Zoznam je voliteľný, obsahuje najviac osem položiek a neukladá obsah dokumentov.

## Finder Quick Action

<img src="docs/diagrams/finder-quick-action.svg" alt="Finder Quick Action na podpis PDF súborov" width="100%">

Vo Finderi označte PDF súbory, prípadne priečinok s PDF súbormi, a zvoľte **Rýchle akcie -> Podpísať s QES + QTS (Autogram)**.

- Služba je registrovaná cez natívne `NSServices` v hlavnom bundle.
- `NSRequiredContext` obmedzuje službu na Finder.
- `FinderSigningRouter` odovzdá výber do `SigningSessionStore.signFromFinder(_:)`.
- Dávka prejde preflight kontrolou, použije dostupnú kvalifikovanú identitu a aktívnu TSA.
- Výstupy používajú collision-safe naming a zachovajú pôvodný priečinok, ak to security scope dovolí.
- Alternatívou je drag and drop viacerých súborov do hlavného okna.

Ak sa akcia nezobrazuje, otvorte vo Finderi **Rýchle akcie -> Prispôsobiť...** a službu zapnite.

## Architektúra

<img src="docs/diagrams/architecture.svg" alt="Vrstvená architektúra Autogram macOS" width="100%">

Projekt má tri hlavné vrstvy:

1. **AutogramApp:** SwiftUI views, native toolbar, Settings scene, menu commands, drag and drop, Finder routing a lifecycle aplikácie.
2. **Session stores:** `SigningSessionStore` riadi štandardné aj dávkové podpisovanie, `ZakoSessionStore` riadi päťkrokový ZaKo workflow a `RecentDocumentStore` spravuje bezpečné bookmarky.
3. **AutogramKit:** testovateľná doménová a dokumentová logika, PDF analýza, Vision pipeline, XML doložka, PDF/A, podpisovanie, ASiC-E a evidencia.

Dáta lokálneho registra sa ukladajú do `register.json` v `~/Library/Application Support/Autogram/Evidence`. Nejde o Core Data ani SQLite databázu. CEZZK je abstrahované cez `EZZKServicing`; Demo používa lokálny mock, zatiaľ čo OAuth2 EZZK session používa typed REST klient s fail-closed hranicami.

Java/PDFBox je voliteľná runtime infraštruktúra pre čistú PDF/A normalizáciu. Pri chýbajúcom engine sa použije Swift fallback iba po úspešnej lokálnej validácii.

## Životný cyklus evidencie

<img src="docs/diagrams/state-machine.svg" alt="Stavový automat evidencie konverzií" width="100%">

Záznam prechádza stavmi konceptu, čakania na číslo, pripravenosti na autorizáciu, autorizácie, fronty odoslania a zápisu v CEZZK. Sieťové zlyhanie vedie na manuálne opakovanie až po potvrdení reálneho submission kontraktu. Záznamy majú 24-hodinovú lehotu od času konverzie; 20-hodinové varovanie je otvorený UX follow-up.

## Register a bezpečnostné hranice

- Preflight zastaví autorizáciu pri chýbajúcom pôvode, údajoch osoby, počte listov, prvkoch, čísle alebo certifikáte.
- Preflight kontroluje aj existujúce podpisy vstupného PDF konzervatívnym scanom; pri komprimovaných objektových streamoch zostáva výsledok `unavailable`, nie falošné potvrdenie.
- ZaKo preferuje mandátny kvalifikovaný certifikát. Výslovný non-mandate override je auditovateľný stav a nemá sa používať ako tiché obídenie pravidla.
- PDF/A, XML a ASiC-E sa kontrolujú pred zápisom výsledku.
- Lokálny register drží evidenčné číslo, hash, XML doložku, stav odoslania, názvy súborov a základné počítadlá.
- CSV export používa slovenský oddeľovač `;`.
- Tajomstvá a API kľúče sa ukladajú do systémovej Kľúčenky, nie do UserDefaults JSON.

## Funkcie podľa modulu

### Podpisovanie

- PDF, JPEG, PNG, TIFF a HEIC vstupy s konverziou obrazu do PDF
- vizuálny podpis a viditeľné PAdES umiestnenie
- segmented voľba formátu KEP, PAdES alebo ASiC-E
- KEP, PAdES, QTS a ASiC-E podľa nastaveného formátu
- CryptoTokenKit, Keychain identity scanner a PKCS#11 EngineBridge
- preflight a progress UI pre dávkové podpisovanie
- dávkové podpisovanie z Findera aj drag and drop viacerých súborov

### Zaručená konverzia

- päťkrokový stepper vrátane dokončenia
- AI a manuálne security elements s trvalými manuálnymi úpravami
- bounding boxy s pohybom, zmenou veľkosti, zmenou typu a popisu
- miniatúry strán, počítadlá listov a formátov
- XML doložka ConversionRecord 1.0 podľa codelistov
- PDF/A-2b, finálna validácia a EmbeddedFile asociácia
- lokálny register, OAuth2 EZZK session, guarded REST transport a CSV export

### Nastavenia a súkromie

- päť AI režimov: vstavaný, oMLX, Ollama, vlastný API kľúč a vypnuté
- predvoľby klasifikačného promptu pre externé LLM režimy
- endpointy a modely pre lokálne providery
- API kľúče a heslá iba v Keychain
- voľba pamätania naposledy otvorených dokumentov cez security-scoped bookmarky
- profily advokáta a vlastné TSA servery
- jasné oddelenie on-device, local-network a cloudového spracovania

## Zostavenie, testy a lokálna inštalácia

```bash
cd Autogram

# Debug build Swift targetov
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift build

# Kompletný test suite
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test

# Debug .app bundle
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh

# Release .app bundle
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh --release
```

Výstupný bundle:

```text
Autogram/.build/arm64-apple-macosx/debug/Autogram.app
```

Lokálna inštalácia debug bundle:

```bash
ditto --rsrc --extattr --acl \
  .build/arm64-apple-macosx/debug/Autogram.app \
  "/Applications/Autogram macOS.app"
open "/Applications/Autogram macOS.app"
```

Overený výsledok na aktuálnom zdrojovom strome: 233 testov, 3 voliteľné live engine testy skipped a 0 failures. Debug bundle má verziu `0.2.2`. Build vytvorí `.build/arm64-apple-macosx/debug/Autogram.app` a pri dostupnom Autogram macOS 2 engine vloží PDFBox dependency classpath do `Contents/app/dependency-jars`.

## Diagramy

Zdrojové SVG diagramy sú v [`docs/diagrams`](docs/diagrams) a ich vizuálna galéria je v [`docs/gallery.html`](docs/gallery.html).

| Súbor | Obsah |
|---|---|
| [`hero.svg`](docs/diagrams/hero.svg) | Projektový prehľad |
| [`architecture.svg`](docs/diagrams/architecture.svg) | Vrstvy aplikácie, session stores a AutogramKit |
| [`process-zako.svg`](docs/diagrams/process-zako.svg) | ZaKo proces a aktéri |
| [`ai-vision.svg`](docs/diagrams/ai-vision.svg) | On-device a voliteľný LLM detection flow |
| [`pdfa-pipeline.svg`](docs/diagrams/pdfa-pipeline.svg) | PDF/A, XML, hash, normalizácia a výstup |
| [`finder-quick-action.svg`](docs/diagrams/finder-quick-action.svg) | Finder Quick Action a dávkové podpisovanie |
| [`state-machine.svg`](docs/diagrams/state-machine.svg) | Životný cyklus konverzného záznamu |
| [`roadmap-open-work.svg`](docs/diagrams/roadmap-open-work.svg) | Aktuálne otvorené follow-upy |
| [`roadmap-open-work.excalidraw`](docs/diagrams/roadmap-open-work.excalidraw) | Editovateľný zdroj roadmapy |

Diagramy používajú prístupný SVG kontrakt: `role="img"`, prefixed `title` a `desc`, čitateľné textové popisy a žiadnu závislosť od JavaScriptu. Predvolený vizuál používa white-smoke paper, jet-black ink, atomic-tangerine focal accent, blue-slate muted connectors, hairline rámce, 4 px grid a žiadne tiene.

## Aktuálny stav a limity

- Manuálna kontrola bezpečnostných prvkov zostáva potrebná. Slabý kontrast, reliéf a rukopis nemusia byť spoľahlivo rozpoznané vstavaným detectorom.
- Lokálny `PDFAValidator` je štrukturálny a heuristický. Finálny release artefakt treba overiť v Acrobat Preflight alebo veraPDF.
- Produkčné EZZK API má OAuth2 klienta, typed REST transport, fixed-host redirect ochranu a guarded Settings UI. Native callback, sandboxový účet, POST receipt kontrakt a podpísaný ASiC workflow zostávajú externé alebo implementačné blokácie.
- XAdES chain/LTA archivácia je obmedzená na aktuálny signing flow; plná B-LT archivácia je budúce rozšírenie.
- Presný OID mandátneho certifikátu treba doplniť po overení reálneho SAK certifikátu.

## Otvorená roadmapa

<img src="docs/diagrams/roadmap-open-work.svg" alt="Roadmap otvorených follow-up úloh" width="100%">

Dokončené v aktuálnom workflow update:

- opravený focus a chevron v sidebar navigácii,
- Settings gear a natívne odkazy do nastavení,
- AI Vision guidance, readiness a prompt predvoľby,
- segmented voľba podpisového formátu,
- recent documents cez bezpečné bookmarky,
- preflight, progress, cancel, stop, continue a retry pre dávkové podpisovanie,
- Finder Quick Action napojená na rovnaký signing engine.

Otvorené follow-upy:

1. Potvrdiť native OAuth redirect URI alebo callback scheme s prevádzkovateľom EZZK.
2. Získať sandboxový EZZK účet a vykonať neprodukčný smoke test.
3. Potvrdiť kompletné `POST /ec` a `POST /zzk` response, receipt, error a idempotency pravidlá.
4. Vytvoriť a validovať samostatný podpísaný record ASiC v conversion workflow.
5. Získať a spracovať oficiálne v1.3 XSD, XSLT a data artefakty pred produkčným rendererom.
6. GUI pass na macOS 27 s VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency a Reduce Motion.
7. Overenie viacerých veľkostí okna, focus order a toolbar command routing.
8. Posúdiť voliteľný AppKit overlay pre presné umiestnenie viditeľného podpisu.
9. Nahradiť zostávajúce nekritické `try?` miesta actionable error UI.
10. Pridať 20-hodinové varovanie v CEZZK dashboarde.
11. Externe overiť PDF/A-2b a EmbeddedFile finálneho release artefaktu.

---

## Právna kotva

- **§ 35 až 39** zákona č. 305/2013 Z. z. o e-Governmente
- **Vyhláška MIRRI č. 70/2021 Z. z.** vrátane obsahu doložky, XML-in-PDF, mandátneho certifikátu, QTS a evidencie
- **eIDAS 910/2014** a vykonávacie nariadenie **2015/1506** pre PAdES, XAdES a ASiC

Implementácia je technický nástroj a nenahrádza právne posúdenie konkrétneho dokumentu ani povinnosť advokáta skontrolovať originál, bezpečnostné prvky, certifikát a výsledný artefakt.
