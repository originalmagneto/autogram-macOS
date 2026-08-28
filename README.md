<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS: Podpisovanie a Zaručená konverzia" width="100%">
</p>

# Autogram macOS

**Natívna SwiftUI aplikácia na elektronické podpisovanie dokumentov** so štandardným režimom podpisovania (KEP + kvalifikovaná časová pečiatka) a **advanced režimom Zaručená konverzia** podľa § 35-39 zákona č. 305/2013 Z. z. o e-Governmente a vyhlášky MIRRI č. 70/2021 Z. z.

`macOS 27 only` (native Liquid Glass) · `SwiftUI + @Observable` · `0 Swift package dependencies` · `Swift 6 strict concurrency` · `102 tests passed, 3 live skipped`

> Implementačná dokumentácia fáz 1 až 4: [`docs/PHASES.md`](docs/PHASES.md)
>
> Aktuálny handoff pre ďalšieho AI agenta: [`docs/SESSION_HANDOFF_2026-08-28.md`](docs/SESSION_HANDOFF_2026-08-28.md)

---

## Prehľad: jeden nástroj, dva režimy

### Štandardný režim: Podpisovanie
Vložte PDF alebo obrazový sken, skontrolujte náhľad, voliteľne umiestnite vizuálnu pečiatku a podpíšte dokument kvalifikovaným elektronickým podpisom a časovou pečiatkou. Primárne akcie používajú natívnu macOS 27 toolbar a inspector hierarchiu.

### Rozšírený režim: Zaručená konverzia
Papierový dokument sa prevedie do elektronickej podoby s účinkami osvedčenej kópie. Aplikácia pripraví analýzu, osvedčovaciu doložku a právny preflight. Autorizácia vyžaduje mandátny certifikát a kvalifikovanú časovú pečiatku.

Flow oddeľuje vytvorenie a podpísanie súborov od zápisu do centrálnej evidencie CEZZK. Ak sa odoslanie do CEZZK zaradí do fronty, completion obrazovka to zobrazí ako samostatný stav s lehotou a možnosťou opakovania.

---

## Architektúra

<img src="docs/diagrams/architecture.svg" alt="Architektúra Autogram macOS" width="100%">

Tri vrstvy tvoria natívna SwiftUI prezentácia (`AutogramApp`) so zdieľaným `AutogramAppModel`, dva reaktívne session store (`SigningSessionStore` pre štandardné podpisovanie a `ZakoSessionStore` pre zaručenú konverziu) a testovateľná knižnica `AutogramKit` s enginmi, dokumentovými službami a infraštruktúrou. Bez externých balíčkových závislostí; PDF/A zápis, XML generátor aj ZIP/ASiC-E packager sú vlastná implementácia. Reálne tokenové podpisovanie používa natívny CryptoTokenKit alebo EngineBridge s Java/DSS engine pre PKCS#11 tokeny.

---

## Proces P→E krok za krokom

<img src="docs/diagrams/process-zako.svg" alt="Procesný tok zaručenej konverzie" width="100%">

| # | Krok | Kto |
|---|---|---|
| 01 | Sken papierového originálu alebo osvedčenej kópie | advokát |
| 02 | Analýza strán, listov a formátu listiny | Autogram |
| 03 | AI Vision detekcia pečiatok a podpisov | Autogram |
| 04 | Právny preflight a potvrdenie údajov | advokát |
| 05 | Evidenčné číslo a dôveryhodný serverový čas | IS EZZK |
| 06 | PDF/A-2b konverzia a XML EmbeddedFile | Autogram |
| 07 | Autorizácia KEP mandátnym certifikátom a QTS | advokát |
| 08 | Zápis záznamu do centrálnej evidencie do 24 h | CEZZK |

---

## Životný cyklus záznamu

<img src="docs/diagrams/state-machine.svg" alt="Stavový automat evidencie konverzií" width="100%">

Každá konverzia prechádza od konceptu k zápisu v centrálnej evidencii. Aplikácia sleduje zákonnú 24-hodinovú lehotu. Výraznejšie varovanie po 20 hodinách a pulzujúci indikátor po lehote zostávajú otvorenou follow-up úlohou.

---

## Finder Quick Action: QES + QTS priamo z Findera

<img src="docs/diagrams/finder-quick-action.svg" alt="Finder Quick Action: podpis označených PDF s QES a QTS" width="100%">

Označte PDF (alebo priečinky s PDF) vo Finderi, kliknite pravým tlačidlom → *Rýchle akcie* → **Podpísať s QES + QTS (Autogram)**. Autogram prevezme výber, automaticky vyberie podpisový certifikát z pripojenej karty, podpíše dávku a uloží výstupy do výstupného priečinka.

- Registrácia cez natívne `NSServices` v hlavnom bundle: macOS appku príp. sám spustí
- BOK/PIN dialóg príde priamo od eID klienta alebo čítačky
- Kvalifikovaná časová pečiatka (QTS) sa pripája z aktívnej TSA (default: Belgium BOSA)
- Ak sa akcia nezobrazuje: pravý klik vo Finderi → *Rýchle akcie* → *Prispôsobiť…* a zapnite ju

> Alternatívne funguje aj klasický drag & drop viacerých súborov do okna appky s dávkovým podpisom zo sidebaru.

---

## PDF/A-2b engine

<img src="docs/diagrams/pdfa-pipeline.svg" alt="Dátove toky PDF/A konvertora" width="100%">

Vlastný konvertor v čistom Swifte: inkrementálna PDF chirurgia doplní XMP metadáta (`pdfaid:part=2`, `conformance=B`), sRGB ICC OutputIntent `/GTS_PDFA1` a hlavičku `%PDF-1.7`. Vektorový režim zachováva textovú vrstvu, raster režim (300 dpi) garantuje vyrovnanie problematických skenov. Doložka sa vloží ako **XML EmbeddedFile** (§ 3 ods. 3 vyhlášky 70/2021) a navyše ako tlačiteľná priložená strana.

---

## AI Vision pipeline

<img src="docs/diagrams/ai-vision.svg" alt="AI Vision detekcia bezpečnostných prvkov" width="100%">

On-device počítačové videnie (farebné/tmavé masky, connected components, radial coverage sampling) rozpozná úradné pečiatky a vlastnoručné podpisy vrátane umiestnenia. Vygeneruje **slovný opis priamo do doložky** (napr. *„Úradná pečiatka na strane 2, v pravej dolnej časti…“*). Voliteľne LLM boost cez Ollama alebo OpenAI-compatible API (kľúč v Keychain).

---

## Ako začať (advokát)

1. **Sign a normal document?** → sidebar *Signing*: choose a PDF (`⌘O`), optionally place a visual signature, and select **Sign KEP** (`⌘⏎`). Or select files in Finder → *Quick Actions* → **Sign with QES + QTS (Autogram)**.
2. **Convert a paper original to electronic form?** → sidebar *Guaranteed conversion*: drop the scan, review AI-detected elements in the native macOS 27 toolbar and inspector, verify the live attestation preview, complete the legal preflight, and select **Authorize conversion**. ZaKo intake uses `⌘⌥O`.
3. **Manage evidence and CEZZK?** → sidebar *Conversion register* → submit the queue or export CSV.

> Bez nastaveného EZZK beží evidencia v DEMO režime; bez pripojeného kvalifikovaného podpisového modulu podpisuje DEMO podpisovač (jasne označený).

---

## Funkcie

### Modul Podpisovanie
- Drag and drop PDF aj obrazové skeny: JPEG, PNG, TIFF a HEIC s automatickou konverziou do PDF
- Voliteľná vizuálna pečiatka s umiestnením na plátne dokumentu
- KEP podpis a QTS cez CryptoTokenKit, Keychain alebo PKCS#11 EngineBridge
- Primárne akcie v natívnej macOS 27 toolbar hierarchii s klávesovou skratkou `⌘⏎`
- Výstupný podpísaný PDF súbor a ASiC-E kontajner
- Finder Quick Action pre podpisovanie označených PDF

### Modul Zaručená konverzia
- Päťfázový workflow stepper vrátane dokončenia
- Natívny macOS 27 toolbar pre výber, markup, AI providera, listy a navigáciu strán
- Zbaliteľný inspector pre pozíciu a veľkosť bezpečnostných prvkov
- Ľavý pás miniatúr stránok s počtom prvkov
- Živý náhľad osvedčovacej doložky
- Automatické počítadlá strán, neprázdnych strán, listov a veľkosti listiny
- AI nálezy sa zlučujú s manuálnymi nálezmi a manuálne úpravy prežívajú re-analýzu
- Šablóny doložiek a profily advokáta

### AI Vision
- On-device detekcia beží vždy
- Voliteľné režimy oMLX, Ollama a OpenAI-compatible API
- API kľúče sa ukladajú do Keychain
- Editovateľný klasifikačný prompt
- Confidence a pôvod nálezu sú viditeľné v inspectore prvku
- Konfigurácia providera sa zobrazuje progresívne

### Bezpečnosť a autorizácia
- KEP podpis cez CryptoTokenKit alebo EngineBridge
- Slovenská eID karta a PKCS#11 tokeny
- Explicitný preflight mandátneho certifikátu
- Potvrdenie pôvodu listiny pred autorizáciou
- SHA-256, QTS, serverový čas a stav CEZZK v konverznom flow

### Register a evidencia
- Lokálny register konverzií
- Vyhľadávanie a filtrovanie podľa stavu
- Kopírovanie evidenčného čísla a SHA-256 odtlačku
- Natívny confirmation dialog pred zmazaním záznamu
- Hromadné odosielanie záznamov do CEZZK s viditeľným úspechom alebo chybou

---

## Build, test and local installation

```bash
cd Autogram

# Debug build
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift build

# Full test suite
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test

# Build the macOS 27 application bundle
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh

# Build the release bundle
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh --release
```

The debug bundle is created at `.build/arm64-apple-macosx/debug/Autogram.app`.

To install the locally built debug app for manual testing:

```bash
ditto --rsrc --extattr --acl \
  .build/arm64-apple-macosx/debug/Autogram.app \
  "/Applications/Autogram macOS.app"
open "/Applications/Autogram macOS.app"
```

The current verification result is 102 tests passed, 3 optional live engine tests skipped, and `LSMinimumSystemVersion=27.0`. The live tests require `AUTOGRAM_ENGINE_LIVE_TEST=1` and the external signing engine.

The current debug bundle is installed at `/Applications/Autogram macOS.app` and was launched successfully for a direct smoke check.

---

## Current macOS 27 UX state

The current branch is macOS 27 only. The main window uses a shared app model, native Settings scene, native menu commands, macOS 27 toolbar groups, collapsible inspectors, and restrained native Liquid Glass.

The ZaKo flow now includes:

- origin or certified-copy confirmation
- live inline validation
- automatic and retryable EZZK evidence-number acquisition
- preflight before server time, PDF/A conversion, and signing
- mandate-certificate enforcement after pending card identity resolution
- explicit signed-file versus queued CEZZK completion state
- accessible element descriptions, confidence, provenance, and keyboard movement controls

Open follow-up work is documented in [`docs/SESSION_HANDOFF_2026-08-28.md`](docs/SESSION_HANDOFF_2026-08-28.md). The most important remaining verification is a real macOS 27 GUI pass with VoiceOver, Full Keyboard Access, Reduce Transparency, Reduce Motion, Increase Contrast, and multiple window sizes.

---

## Legislatívna kotva

- **§ 35-39** zákona č. 305/2013 Z. z. (oprávnenie advokáta, postup, účinky osvedčenej kópie)
- **Vyhláška MIRRI č. 70/2021 Z. z.** (obsah doložky, forma XML-in-PDF, mandátny certifikát + QTS, evidencia, 24 h lehota)
- **eIDAS 910/2014 + IR 2015/1506** (PAdES/XAdES v ASiC kontajneroch)

---

*Diagramy v štýle [diagram-design](https://github.com/cathrynlavery/diagram-design) - editorial tokens: white-smoke paper, jet-black ink, atomic-tangerine accent, blue-slate muted. Bez tieňov.*
