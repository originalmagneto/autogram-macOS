<p align="center">
  <img src="Autogram/docs/diagrams/hero.svg" alt="Autogram macOS: podpisovanie a zaručená konverzia" width="100%">
</p>

# Autogram macOS

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

## Vizuálny guide

Interaktívne HTML grafiky sú samostatné, bez JavaScriptu a pripravené na otvorenie v prehliadači:

- [Architektúra a batch preflight](Autogram/docs/diagrams/autogram-visual-guide.html)
- [Diagramová galéria](Autogram/docs/gallery.html)
- [Architektúra aplikácie](Autogram/docs/diagrams/architecture.svg)
- [Proces zaručenej konverzie](Autogram/docs/diagrams/process-zako.svg)
- [AI Vision pipeline](Autogram/docs/diagrams/ai-vision.svg)
- [PDF/A pipeline](Autogram/docs/diagrams/pdfa-pipeline.svg)
- [Finder Quick Action](Autogram/docs/diagrams/finder-quick-action.svg)
- [Stavový automat evidencie](Autogram/docs/diagrams/state-machine.svg)

## Rýchly štart

### Požiadavky

- macOS 27 alebo novší
- Xcode 26.5 a Swift 6 pre build zo zdrojov
- Apple Silicon alebo Intel podľa použitého toolchainu
- pre reálny podpis kompatibilná eID karta, advokátsky preukaz alebo PKCS#11, CryptoTokenKit či Keychain token
- pre EZZK produkčný režim účet, callback `autogram://ezzk/callback`, sandboxové overenie a sieťové pripojenie

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

Kompletná implementačná dokumentácia je v [`Autogram/docs/PHASES.md`](Autogram/docs/PHASES.md).

## Právne a bezpečnostné upozornenie

Autogram je technický nástroj. Nenahrádza právne posúdenie konkrétneho dokumentu ani povinnosť advokáta skontrolovať originál, bezpečnostné prvky, certifikát a výsledný artefakt.
