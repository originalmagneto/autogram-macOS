<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS: podpisovanie a zaručená konverzia" width="100%">
</p>

# Autogram macOS

Autogram je natívna macOS aplikácia v SwiftUI na elektronické podpisovanie dokumentov a zaručenú konverziu listinných dokumentov do elektronickej podoby.

- **Podpisovanie:** KEP alebo PAdES podpis, kvalifikovaná časová pečiatka a ASiC-E kontajner.
- **Zaručená konverzia (ZaKo):** analýza dokumentu, označenie bezpečnostných prvkov, osvedčovacia doložka, PDF/A-2b pilotný profil, autorizácia mandátnym certifikátom a lokálna evidencia CEZZK.
- **Register:** lokálne uložené záznamy konverzií, fronta odoslania do CEZZK, vyhľadávanie, filtrovanie a CSV export.

> **Compliance note:** Aktuálny build je implementačný P -> E pilot. Generuje PDF/A-2b, kým externé požiadavky na PDF/A-1a alebo PNG, aktívne verzie formulárov a produkčný EZZK kontrakt nebudú autoritatívne potvrdené a nezávisle overené. P2E cieľová doložka je oficiálna verzia v1.3, zatiaľ čo aktuálny CEZZK záznam je verzia 1.0. Porovnanie a plán sú v [`Autogram/docs/P2E-EZZK-FINDINGS.md`](Autogram/docs/P2E-EZZK-FINDINGS.md) a [`Autogram/docs/superpowers/plans/2026-08-29-ezzk-oauth-rest-ui.md`](Autogram/docs/superpowers/plans/2026-08-29-ezzk-oauth-rest-ui.md).

`macOS 27 only` · `Swift 6` · `SwiftUI + @Observable` · `0 Swift package dependencies` · `187 tests executed` · `3 skipped` · `0 failures`

> Implementačná dokumentácia: [`docs/PHASES.md`](docs/PHASES.md)
>
> Posledný odovzdávací záznam: [`docs/SESSION_HANDOFF_2026-08-28.md`](docs/SESSION_HANDOFF_2026-08-28.md)
>
> Posledná revízia externých ZaKo požiadaviek: [`docs/SESSION_HANDOFF_2026-08-28-ZAKO-SPEC.md`](docs/SESSION_HANDOFF_2026-08-28-ZAKO-SPEC.md)

---

## Požiadavky

- macOS 27 alebo novší
- Apple Silicon alebo Intel Mac podporovaný použitým Xcode toolchainom
- Xcode 26.5 a Swift 6 pre zostavenie zo zdrojov
- pre reálny podpis: kompatibilná eID karta, advokátsky preukaz alebo iný PKCS#11/CryptoTokenKit token
- pre produkčné CEZZK odoslanie: EZZK účet, potvrdený native OAuth callback, sandboxové overenie a sieťové pripojenie k príslušnej službe
- pre PDFBox normalizáciu: nainštalovaný Autogram macOS 2 engine s Java runtime; bez neho sa použije lokálny fallback iba vtedy, ak výsledok prejde lokálnou kontrolou

Aplikácia je cielene zostavená pre macOS 27. `Package.swift` preto deklaruje platformu `.macOS("27.0")` a build script zapisuje `LSMinimumSystemVersion=27.0`.

---

## Dva hlavné pracovné režimy

### 1. Podpisovanie

1. Otvorte PDF cez `⌘O`, vložte ho drag and drop alebo použite Finder Quick Action.
2. Voliteľne zapnite vizuálny podpis a upravte jeho vzhľad a umiestnenie.
3. Vyberte podpisovú identitu a spustite **Podpísať KEP** (`⌘⏎`).
4. Aplikácia použije CryptoTokenKit alebo EngineBridge s PKCS#11 fallbackom a podľa voľby pridá QTS.
5. Výsledok zobrazí podpísaný dokument, stav podpisu a dostupné ASiC-E artefakty.

Ak nie je dostupný reálny token, aplikácia použije jasne označený DEMO podpisovač. DEMO podpis nie je právne záväzný.

### 2. Zaručená konverzia

ZaKo používa päť krokov:

1. **Import:** vstupný PDF alebo obrazový sken a potvrdenie originálu alebo úradne osvedčenej kópie.
2. **Analýza:** formát strán, neprázdne strany, listy a návrh názvu dokumentu.
3. **Označenie:** AI Vision a manuálne označenie podpisov, pečiatok, reliéfnych pečatí, paraf a iných prvkov.
4. **Osvedčovacia doložka:** údaje osoby, počítadlá, lokalizácia prvkov, XML náhľad a právny preflight.
5. **Autorizácia a dokončenie:** evidenčné číslo cez explicitnú EZZK akciu, dôveryhodný serverový čas, PDF/A, podpis, lokálna evidencia a odoslanie do CEZZK až po validácii podpísaných ASiC artefaktov a potvrdeného receipt.

Odoslanie do CEZZK je oddelené od vytvorenia súborov. Aktuálna OAuth integrácia má typed transport a guarded UI, ale odoslanie zostáva zablokované, kým workflow nevytvorí a nevaliduje samostatný podpísaný record ASiC a kým nebude potvrdený sandboxový receipt kontrakt.

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

---

## AI Vision a označovanie prvkov

<img src="docs/diagrams/ai-vision.svg" alt="AI Vision detekcia bezpečnostných prvkov" width="100%">

Vstavaný detector pracuje lokálne na zariadení. Používa Apple Vision na vylúčenie textových riadkov a čiarových kódov, farebné a tmavé masky, connected components a konzervatívne geometrické filtre. Detekcia sa analyzuje na šírke 760 px, farebná maska používa saturáciu `s > 0.18` a rasterizačný režim PDF/A používa 200 dpi.

Výsledkom sú `SecurityElement` záznamy s:

- typom prvku a stranou,
- normalizovaným bounding boxom,
- mierou istoty,
- slovným opisom v slovenčine,
- pôvodom nálezu a možnosťou manuálnej úpravy.

Voliteľné LLM režimy sú **oMLX**, **Ollama** a vlastné OpenAI-compatible API. Vstavané pravidlá bežia vždy, takže aplikácia má použiteľný fallback aj bez LLM. Pri vlastnom cloudovom API môže obraz dokumentu opustiť Mac, preto treba endpoint a režim zvoliť podľa požiadaviek na ochranu údajov.

---

## PDF/A-2b a osvedčovacia doložka

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

---

## Výstupy, názvy a umiestnenie

ZaKo sa pokúsi uložiť výstupy do zapisovateľného priečinka zdrojového dokumentu. Ak zdrojový priečinok nie je zapisovateľný alebo import nemá použiteľný security scope, použije sa:

```text
~/Library/Application Support/Autogram/Output
```

Názov PDF zachováva väzbu na pôvodný dokument. Typické príklady:

```text
diplom.pdf                  -> diplom-konvertovane.pdf
diplom.pdf + nový názov     -> diplom-novy-nazov.pdf
```

Prípony generované pri ZaKo:

- `{dokument}.pdf`: finálny podpísaný PDF/A-2b,
- `{dokument}-{evidenčné-číslo}.xml.xdcf`: samostatná osvedčovacia doložka,
- `{dokument}.asice`: voliteľný ASiC-E výstup podľa podpisového providera.

Pri existujúcom súbore sa použije collision-safe suffix, napríklad `(2)`, aby sa pôvodný artefakt neprepísal. Výber cez file picker aj drag and drop zachováva zdrojový priečinok počas dokumentovej session pomocou security-scoped access.

Štandardné podpisovanie používa zapisovateľný priečinok zdroja a pri nedostupnosti rovnaký Application Support fallback. Výstupný stem má tvar `{pôvodný-názov}_podpisane`.

---

## Nastavenia

Native Settings scene obsahuje všetky konfiguračné oblasti v štyroch tabuľkách:

1. **AI Vision:** on-device, oMLX, Ollama, vlastné OpenAI-compatible API, vypnutie asistenta, endpointy, modely, Keychain API kľúč a vlastný klasifikačný prompt.
2. **Konverzia PDF/A:** vektorový alebo rasterizovaný režim, aktívna RFC 3161 TSA, vlastné TSA servery a test spojenia.
3. **EZZK:** OAuth2 session cez Keycloak, fixné Sandbox a Production identity, stav prihlásenia, explicitná žiadosť o evidenčné číslo, Demo režim a migračné kontaktné údaje.
4. **Profily advokáta:** viac profilov, aktívny profil, meno, funkcia, SAK číslo, IČO, kancelária, adresa a právnická osoba.

Settings okno má natívnu predvolenú veľkosť `1080 × 820` a obsah tabuľky sa nezabalí do vnútorného vertikálneho `ScrollView`. Záložky sú preto navrhnuté ako vysoké, roztiahnuté plochy s priamym prístupom k voľbám. Pri viacerých uložených profiloch sa zobrazia všetky profily v poradí uloženia.

Tajomstvá sa neukladajú do JSON nastavení. AI API kľúč, EZZK heslo z legacy migrácie a OAuth tokeny idú do systémovej Kľúčenky. Ostatné nastavenia sa ukladajú do UserDefaults ako verzované JSON.

---

## Finder Quick Action

<img src="docs/diagrams/finder-quick-action.svg" alt="Finder Quick Action na podpis PDF súborov" width="100%">

Vo Finderi označte PDF súbory, prípadne priečinok s PDF súbormi, a zvoľte **Rýchle akcie -> Podpísať s QES + QTS (Autogram)**.

- Služba je registrovaná cez natívne `NSServices` v hlavnom bundle.
- `NSRequiredContext` obmedzuje službu na Finder.
- `FinderSigningRouter` odovzdá výber do `SigningSessionStore.signFromFinder(_:)`.
- Dávka automaticky použije dostupnú kvalifikovanú identitu a aktívnu TSA.
- Alternatívou je drag and drop viacerých súborov do hlavného okna.

Ak sa akcia nezobrazuje, otvorte vo Finderi **Rýchle akcie -> Prispôsobiť…** a službu zapnite.

---

## Architektúra

<img src="docs/diagrams/architecture.svg" alt="Vrstvená architektúra Autogram macOS" width="100%">

Projekt má tri hlavné vrstvy:

1. **AutogramApp:** SwiftUI views, native toolbar, Settings scene, menu commands, drag and drop a lifecycle aplikácie.
2. **Session stores:** `SigningSessionStore` riadi štandardné podpisovanie a `ZakoSessionStore` riadi päťkrokový ZaKo workflow.
3. **AutogramKit:** testovateľná doménová a dokumentová logika, PDF analýza, Vision pipeline, XML doložka, PDF/A, podpisovanie, ASiC-E a evidencia.

Dáta lokálneho registra sa ukladajú do `register.json` v `~/Library/Application Support/Autogram/Evidence`. Nejde o Core Data ani SQLite databázu. CEZZK je abstrahované cez `EZZKServicing`; Demo používa lokálny mock, zatiaľ čo OAuth2 EZZK session používa typed REST klient s fail-closed hranicami.

Java/PDFBox je voliteľná runtime infraštruktúra pre čistú PDF/A normalizáciu. Pri chýbajúcom engine sa použije Swift fallback iba po úspešnej lokálnej validácii.

---

## Životný cyklus evidencie

<img src="docs/diagrams/state-machine.svg" alt="Stavový automat evidencie konverzií" width="100%">

Záznam prechádza stavmi konceptu, čakania na číslo, pripravenosti na autorizáciu, autorizácie, fronty odoslania a zápisu v CEZZK. Demo operácie zostávajú lokálne a záznamy ostávajú pending. Sieťové zlyhanie vedie na manuálne opakovanie až po potvrdení reálneho submission kontraktu. Záznamy majú 24-hodinovú lehotu od času konverzie; 20-hodinové varovanie je ešte otvorený UX follow-up.

---

## Register a bezpečnostné hranice

- Preflight zastaví autorizáciu pri chýbajúcom pôvode, údajoch osoby, počte listov, prvkoch, čísle alebo certifikáte.
- ZaKo preferuje mandátny kvalifikovaný certifikát. Výslovný non-mandate override je auditovateľný stav a nemá sa používať ako tiché obídenie pravidla.
- PDF/A, XML a ASiC-E sa kontrolujú pred zápisom výsledku.
- Lokálny register drží evidenčné číslo, hash, XML doložku, stav odoslania, názvy súborov a základné počítadlá.
- CSV export používa slovenský oddeľovač `;`.

---

## Funkcie podľa modulu

### Podpisovanie

- PDF, JPEG, PNG, TIFF a HEIC vstupy s konverziou obrazu do PDF
- vizuálny podpis a viditeľné PAdES umiestnenie
- KEP, PAdES, QTS a ASiC-E podľa nastaveného formátu
- CryptoTokenKit, Keychain identity scanner a PKCS#11 EngineBridge
- dávkové podpisovanie z Findera

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
- endpointy a modely pre lokálne providery
- API kľúče a heslá iba v Keychain
- profily advokáta a vlastné TSA servery
- jasné oddelenie on-device, local-network a cloudového spracovania

---

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

Aktuálny overený výsledok je 187 vykonaných testov, 3 voliteľné live engine testy skipped a 0 failures. EZZK OAuth2, typed REST transport a guarded Settings UI sú implementované, ale produkčná interoperability zostáva zablokovaná externými EZZK kontraktmi. Build script zároveň vloží PDFBox dependency classpath do `Contents/app/dependency-jars` pri inštalácii Autogram macOS 2 engine.

---

## Aktuálny stav a limity

- Manuálna kontrola bezpečnostných prvkov zostáva potrebná. Slabý kontrast, reliéf a rukopis nemusia byť spoľahlivo rozpoznané vstavaným detectorom.
- Lokálny `PDFAValidator` je štrukturálny a heuristický. Finálny release artefakt treba overiť v Acrobat Preflight alebo veraPDF.
- Produkčné EZZK API už má OAuth2 klienta, typed REST transport, fixed-host redirect ochranu a guarded Settings UI. Native callback, sandboxový účet, POST receipt kontrakt a signed ASiC workflow zostávajú externé alebo implementačné blokácie.
- XAdES chain/LTA archivácia je obmedzená na aktuálny signing flow; plná B-LT archivácia je budúce rozšírenie.
- Presný OID mandátneho certifikátu treba doplniť po overení reálneho SAK certifikátu.

---

## Otvorená roadmapa

<img src="docs/diagrams/roadmap-open-work.svg" alt="Roadmap otvorených follow-up úloh" width="100%">

Hotové položky z predchádzajúcej roadmapy, vrátane päťkrokového ZaKo steppera, P2E v1.3 conformance profilu, OAuth2 EZZK session, typed REST transportu a guarded Demo/Sandbox UI, sú označené ako dokončené. Aktívne follow-upy sú:

1. Potvrdiť native OAuth redirect URI alebo callback scheme s prevádzkovateľom EZZK.
2. Získať sandboxový EZZK účet a vykonať neprodukčný smoke test.
3. Potvrdiť kompletné `POST /ec` a `POST /zzk` response, receipt, error a idempotency pravidlá.
4. Vytvoriť a validovať samostatný podpísaný record ASiC v conversion workflow.
5. Získať a spracovať oficiálne v1.3 XSD/XSLT/data artefakty pred produkčným rendererom.
6. GUI pass na macOS 27 s VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency a Reduce Motion.
7. Overenie viacerých veľkostí okna, focus order a toolbar command routing.
8. Posúdenie voliteľného AppKit overlay pre presné umiestnenie viditeľného podpisu.
9. Nahradenie zostávajúcich nekritických `try?` miest actionable error UI.
10. 20-hodinové varovanie v CEZZK dashboarde.
11. Externá PDF/A-2b a EmbeddedFile validácia reálneho finálneho artefaktu.

Editovateľný zdroj roadmap diagramu: [`docs/diagrams/roadmap-open-work.excalidraw`](docs/diagrams/roadmap-open-work.excalidraw).

---

## Právna kotva

- **§ 35 až 39** zákona č. 305/2013 Z. z. o e-Governmente
- **Vyhláška MIRRI č. 70/2021 Z. z.** vrátane obsahu doložky, XML-in-PDF, mandátneho certifikátu, QTS a evidencie
- **eIDAS 910/2014** a vykonávacie nariadenie **2015/1506** pre PAdES/XAdES/ASiC

Implementácia je technický nástroj a nenahrádza právne posúdenie konkrétneho dokumentu ani povinnosť advokáta skontrolovať originál, bezpečnostné prvky, certifikát a výsledný artefakt.

---

*Diagramy používajú jednoduchý editorial štýl s hairline rámcami, bez tieňov a s obmedzenou akcentovou farbou.*