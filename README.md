<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS: podpisovanie a zaručená konverzia" width="100%">
</p>

# Autogram macOS

<p align="center">
  <a href="https://github.com/originalmagneto/autogram-macOS/releases/latest"><img src="https://img.shields.io/github/v/release/originalmagneto/autogram-macOS?display_name=tag&style=flat-square&color=eb6c36" alt="Aktuálne vydanie"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-2d3142?style=flat-square" alt="macOS 27 alebo novší">
  <img src="https://img.shields.io/badge/Swift-6-f05138?style=flat-square" alt="Swift 6">
</p>

<p align="center">
  <strong>Natívny pracovný stôl pre dôveryhodné právne dokumenty.</strong><br>
  Podpis. Konverzia. Evidencia. V jednom lokálnom workflow.
</p>

Natívna macOS aplikácia v SwiftUI pre kvalifikované elektronické podpisovanie, zaručenú konverziu a lokálnu evidenciu právnych dokumentov.

`macOS 27` · `Swift 6` · `SwiftUI` · `PDFKit` · `0 Swift package dependencies`

## Prehľad

| Modul | Čo rieši | Výstup |
|---|---|---|
| **Podpisovanie** | KEP, PAdES, ASiC-E, QTS, vizuálny podpis a dávky | podpísané PDF alebo ASiC-E |
| **Zaručená konverzia** | import, analýza, AI Vision, doložka a autorizácia | PDF/A-2b, XML, evidencia |
| **Register** | lokálne záznamy, stavy, vyhľadávanie a CSV | `register.json` + export |
| **Integrácie** | eID, PKCS#11, Keychain, Finder Quick Action, EZZK | natívny pracovný tok |

## Funkcie

- **Dávkové podpisovanie:** jedna plná DSS validácia pre celú dávku, výsledky podľa dokumentu, bezpečné cancellation guards a collision-safe výstupy.
- **Dôveryhodnosť vstupu:** neplatný podpis blokuje konkrétny dokument; indeterminate stav alebo nedostupná trust služba zostáva informatívna.
- **ZaKo workflow:** päť krokov od importu po dokončenie, vrátane potvrdenia pôvodu, bezpečnostných prvkov, osvedčovacej doložky a mandátneho certifikátu.
- **AI Vision:** lokálny Apple Vision baseline, oMLX, Ollama a voliteľné OpenAI-compatible endpointy.
- **PDF/A:** vektorový a rasterizovaný režim, lokálna kontrola štruktúry, XMP, OutputIntent, EmbeddedFile a asociácie `/AF`.
- **Finder Quick Action:** podpis PDF súborov bez otvárania hlavného okna aplikácie.
- **Bezpečné dáta:** security-scoped bookmarks, Keychain pre tajomstvá a lokálna evidencia bez ukladania obsahu dokumentov.

<details>
<summary><strong>Čo získate v každom module</strong></summary>

<table>
<tr>
<td width="50%" valign="top">
<h3>Podpisovanie</h3>
<ul>
<li>Výber eID, I.CA SecureStore, PKCS#11 a Keychain tokenov.</li>
<li>Detekcia certifikátov na karte vrátane čítačiek s viacerými slotmi.</li>
<li>PAdES a ASiC-E výstupy s kvalifikovanou časovou pečiatkou.</li>
<li>Vizuálny podpis, dávkové spracovanie a bezpečné zrušenie operácie.</li>
</ul>
</td>
<td width="50%" valign="top">
<h3>Zaručená konverzia</h3>
<ul>
<li>Kontrolovaný import a potvrdenie pôvodu dokumentu.</li>
<li>AI Vision s manuálnou kontrolou podpisov, pečatí a paraf.</li>
<li>PDF/A-2b, osvedčovacia doložka, XML a lokálna evidencia.</li>
<li>Mandátny certifikát a fail-closed produkčné odoslanie do CEZZK.</li>
</ul>
</td>
</tr>
</table>
</details>

<details>
<summary><strong>Stavy podpisu a dôveryhodnosti</strong></summary>

`INSPECT` rýchlo číta existujúce podpisy vrátane podpisov v ASiC-E. `VALIDATE` vykonáva úplnú dôveryhodnostnú kontrolu s trust listami. Ak trust service nie je dostupná, výsledok môže byť `indeterminate`; to nie je to isté ako platný alebo neplatný podpis.
</details>

## Vizuálny guide

Interaktívne HTML grafiky sú samostatné, bez JavaScriptu a pripravené na otvorenie v prehliadači:

- [Architektúra a batch preflight](docs/diagrams/autogram-visual-guide.html)
- [Diagramová galéria](docs/gallery.html)
- [Architektúra aplikácie](docs/diagrams/architecture.svg)
- [Proces zaručenej konverzie](docs/diagrams/process-zako.svg)
- [AI Vision pipeline](docs/diagrams/ai-vision.svg)
- [PDF/A pipeline](docs/diagrams/pdfa-pipeline.svg)
- [Finder Quick Action](docs/diagrams/finder-quick-action.svg)
- [Stavový automat evidencie](docs/diagrams/state-machine.svg)


### Architektúra aplikácie

Táto mapa vysvetľuje, ako sa natívny SwiftUI shell opiera o session stores a `AutogramKit`. Dokumentové služby zostávajú lokálne; externé hranice sú jasne oddelené cez Java DSS helper, PKCS#11, PDFKit a EZZK.

<p align="center">
  <img src="docs/diagrams/architecture.svg" alt="Vrstvená architektúra Autogram macOS" width="100%">
</p>

### Proces zaručenej konverzie

Procesný diagram sleduje dokument od skenu originálu cez analýzu, AI Vision a evidenčné číslo až po PDF/A výstup, doložku a zápis do CEZZK. Oranžový krok označuje autorizáciu KEP mandátom a QTS.

<p align="center">
  <img src="docs/diagrams/process-zako.svg" alt="Proces zaručenej konverzie" width="100%">
</p>

### AI Vision pipeline

Pipeline ukazuje oddelenie medzi lokálnou detekciou bezpečnostných prvkov a voliteľným LLM opisom. Nálezy nie sú automaticky považované za potvrdené: advokát ich skontroluje a až potom pokračuje validačný workflow.

<p align="center">
  <img src="docs/diagrams/ai-vision.svg" alt="AI Vision pipeline" width="100%">
</p>

### PDF/A pipeline

Diagram opisuje technickú normalizáciu výsledného dokumentu: vloženie metadát a príloh, vytvorenie XMP profilu, výpočet fingerprintu a kontrolu, že exportovaný artefakt spĺňa požadovaný formát.

<p align="center">
  <img src="docs/diagrams/pdfa-pipeline.svg" alt="PDF/A pipeline" width="100%">
</p>

### Finder Quick Action

Quick Action skracuje cestu pre jednoduché podpísanie PDF priamo vo Finderi. Samostatný runner zobrazí výber ovládača, certifikátu a PIN/BOK, podpíše súbor na pozadí a uloží výsledok bez otvorenia hlavného workflow.

<p align="center">
  <img src="docs/diagrams/finder-quick-action.svg" alt="Finder Quick Action" width="100%">
</p>

### Stavový automat evidencie

Stavový automat ukazuje, kedy je dokument iba pripravený, kedy prešiel kontrolou a kedy už vznikol podpísaný alebo konvertovaný artefakt. Oddelené koncové stavy pomáhajú rozlíšiť úspešné odoslanie, odmietnutie a archiváciu.

<p align="center">
  <img src="docs/diagrams/state-machine.svg" alt="Stavový automat evidencie" width="100%">
</p>

## Rýchly štart

### Požiadavky

- macOS 27 alebo novší
- Xcode 26.5 a Swift 6 pre build zo zdrojov
- Apple Silicon alebo Intel podľa použitého toolchainu
- pre reálny podpis kompatibilná eID karta, advokátsky preukaz alebo PKCS#11, CryptoTokenKit či Keychain token
- pre EZZK produkčný režim účet, callback `autogram://ezzk/callback`, sandboxové overenie a sieťové pripojenie


## Stiahnutie

Aktuálny macOS build bude dostupný v [GitHub Releases](https://github.com/originalmagneto/autogram-macOS/releases/latest) ako DMG. Aplikácia vyžaduje macOS 27 alebo novší.

<details open>
<summary><strong>v0.2.3 · aktuálne vydanie</strong></summary>

<ul>
<li>I.CA SecureStore správne vyberá slot s kartou aj pri prázdnej čítačke na prvej pozícii.</li>
<li>Existujúce XAdES podpisy v ASiC-E sa načítajú cez ľahkú inšpekciu bez blokovania na nedostupnom trust liste.</li>
<li>Batch preflight, PDF/A výstupy, ZaKo workflow a lokálna evidencia zostávajú súčasťou jedného natívneho buildu.</li>
</ul>
</details>

### Build a inštalácia

```bash
cd Autogram
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh install
```

Aplikácia sa nainštaluje do:

```text
/Applications/Autogram macOS.app
```

### Testy

```bash
cd Autogram
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test
```

Voliteľné live engine testy:

```bash
AUTOGRAM_ENGINE_LIVE_TEST=1 \
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer \
swift test --filter JavaEngineLiveProcessTests
```

## Podpisovanie

1. Otvorte PDF cez `⌘O`, drag and drop alebo Finder Quick Action.
2. Pri viacerých dokumentoch vyberte **Pripraviť dávku podpisov**.
3. Prejdite preflight kontrolou vstupov a nastavení.
4. Vyberte formát, certifikát a voliteľný vizuálny podpis alebo QTS.
5. Spustite podpisovanie cez **Podpísať KEP** alebo sticky action bar.
6. Skontrolujte výsledný PDF, XML alebo ASiC-E artefakt.

Počas batch preflightu aplikácia čaká na plnú validáciu pred povolením podpisovania. Trust service zlyhanie neblokuje dávku, ale `INVALID` vstup ostáva blokovaný.

Ak nie je dostupný reálny token, aplikácia môže použiť jasne označený DEMO podpisovač. DEMO podpis nie je právne záväzný.

## Zaručená konverzia

ZaKo používa tento sled:

1. **Import:** PDF alebo obrazový sken a potvrdenie pôvodu.
2. **Analýza:** formát strán, neprázdne strany, listy a názov.
3. **Označenie:** AI Vision a manuálne označenie podpisov, pečiatok, reliéfnych pečatí a paraf.
4. **Doložka:** údaje osoby, počítadlá, lokalizácia prvkov, XML náhľad a právny preflight.
5. **Autorizácia:** evidenčné číslo, serverový čas, PDF/A, podpis, lokálna evidencia a voliteľné odoslanie do CEZZK.

Produkčné CEZZK odoslanie je fail-closed, kým nie je vytvorený a validovaný samostatný podpísaný record ASiC a potvrdený receipt kontrakt.

## Stav integrácie EZZK

EZZK integrácia je pripravená na úrovni OAuth2/PKCE, OIDC discovery, natívneho callbacku a bezpečného uloženia session v Keychain. Na produkčné zapojenie čakáme na potvrdenie a integračné podklady od **MIRRI SR**. Dovtedy zostáva produkčné odoslanie do CEZZK oddelené a fail-closed.

## Výstupy a hranice

Výstupy sa ukladajú prednostne k zdrojovému dokumentu. Pri nedostupnom alebo nezapisovateľnom priečinku sa použije:

```text
~/Library/Application Support/Autogram/Output
```

Existujúce súbory sa neprepíšu. Aplikácia vytvorí collision-safe názov, napríklad `dokument (2).pdf`.

Aktuálny ZaKo profil je implementačný P2E pilot s PDF/A-2b. Lokálny `PDFAValidator` nie je náhradou za veraPDF alebo Acrobat Preflight. Produkčné EZZK endpointy, aktívne formuláre a externé požiadavky treba overiť samostatne.

## Architektúra

- **AutogramApp:** SwiftUI views, menu commands, Settings, drag and drop, Finder routing a lifecycle.
- **Session stores:** `SigningSessionStore`, `ZakoSessionStore` a `RecentDocumentStore` riadia workflow a stav.
- **AutogramKit:** PDF analýza, Vision pipeline, XML doložka, PDF/A, podpisovanie, ASiC-E a evidencia.
- **EngineBridge:** persistentný machine session helper pre Java/DSS, PDFBox a PKCS#11 integrácie.

Lokálny register je JSON-based:

```text
~/Library/Application Support/Autogram/Evidence/register.json
```

Kompletná implementačná dokumentácia je v [`docs/PHASES.md`](docs/PHASES.md).

## Právne a bezpečnostné upozornenie

Autogram je technický nástroj. Nenahrádza právne posúdenie konkrétneho dokumentu ani povinnosť advokáta skontrolovať originál, bezpečnostné prvky, certifikát a výsledný artefakt.
