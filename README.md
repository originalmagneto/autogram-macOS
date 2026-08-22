<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS — Zaručená konverzia" width="100%">
</p>

# Autogram macOS

**Natívna SwiftUI aplikácia pre zaručenú konverziu dokumentov** — advokátsky nástroj podľa § 35–39 zákona č. 305/2013 Z. z. o e-Governmente a vyhlášky MIRRI č. 70/2021 Z. z.

`macOS 14+` · `SwiftUI + @Observable` · `0 externých závislostí` · `~5 900 LOC Swift` · `24/24 testov ✅`

---

## Prehľad

Zaručená konverzia je slovenský ekvivalent osvedčovania listín u notára: papierový dokument sa prevedie do elektronickej podoby tak, že nový dokument má **právne účinky osvedčenej kópie**. Advokát na to potrebuje mandátny certifikát a kvalifikované časové pečiatky — appka sa postará o všetko ostatné.

Kým existujúce nástroje (Podpisuj.sk, D.Convert) sú Java monštrá s desiatkami manuálne vypĺňaných polí, Autogram robí z konverzie **2–3 kliky**: automaticky rozpozná strany, listy aj bezpečnostné prvky, stiahne evidenčné číslo z EZZK, vygeneruje XML doložku a celé to zapečatí.

---

## Architektúra

<img src="docs/diagrams/architecture.svg" alt="Architektúra Autogram macOS" width="100%">

Tri vrstvy: natívna SwiftUI prezentácia (`AutogramApp`), reaktívny `@Observable ZakoSessionStore` a čisto testovateľná knižnica `AutogramKit` — enginy, dokumentové služby a infraštruktúra. Nula externých závislostí; PDF/A zápis, XML generátor aj ZIP/ASiC-E packager sú vlastná implementácia.

---

## Proces P→E krok za krokom

<img src="docs/diagrams/process-zako.svg" alt="Procesný tok zaručenej konverzie" width="100%">

| # | Krok | Kto |
|---|---|---|
| 01 | Sken papierového originálu (drag & drop) | advokát |
| 02 | Analýza strán, listov, formátu listiny | Autogram |
| 03 | AI Vision detekcia pečiatok a podpisov | Autogram |
| 04 | Potvrdenie údajov (1 klik namiesto 30 polí) | advokát |
| 05 | Jednorazové evidenčné číslo + serverový čas | IS EZZK |
| 06 | PDF/A-2b konverzia + XML EmbeddedFile | Autogram |
| 07 | Autorizácia KEP mandátnym certifikátom + QTS | advokát |
| 08 | Zápis záznamu do centrálnej evidencie ≤ 24 h | CEZZK |

---

## Životný cyklus záznamu

<img src="docs/diagrams/state-machine.svg" alt="Stavový automat evidencie konverzií" width="100%">

Každá konverzia prechádza stavmi od konceptu po potvrdenie v centrálnej evidencii. Appka stráži zákonné lehoty — neodoslané záznamy po 20 hodinách červenajú v dashboarde.

---

## PDF/A-2b engine

<img src="docs/diagrams/pdfa-pipeline.svg" alt="Dátove toky PDF/A konvertora" width="100%">

Vlastný konvertor v čistom Swifte: inkrementálna PDF chirurgia doplní XMP metadáta (`pdfaid:part=2`, `conformance=B`), sRGB ICC OutputIntent `/GTS_PDFA1` a hlavičku `%PDF-1.7`. Vektorový režim zachováva textovú vrstvu, raster režim (300 dpi) garantuje vyrovnanie problematických skenov. Doložka sa vloží ako **XML EmbeddedFile** (§ 3 ods. 3 vyhlášky 70/2021) a navyše ako tlačiteľná príložená strana.

---

## AI Vision pipeline

<img src="docs/diagrams/ai-vision.svg" alt="AI Vision detekcia bezpečnostných prvkov" width="100%">

On-device počítačové videnie (farebné/tmavé masky → connected components → radial coverage sampling) rozpozná úradné pečiatky a vlastnoručné podpisy vrátane umiestnenia. Vygeneruje **slovný opis priamo do doložky** — *„Úradná pečiatka na strane 2, v pravej dolnej časti…"*. Voliteľne LLM boost cez Ollama alebo OpenAI-compatible API (kľúč v Keychain).

---

## Funkcie

### 🏛️ Modul Zaručená konverzia
- 5-krokový workflow stepper s vizuálne oddeleným „advokátskym“ režimom
- Automatické počítadlá: strany / neprázdné strany / listy / veľkosť listiny (A4·A3·Letter × výška·šírka)
- Detekcia prázdnych strán (grayscale ink coverage + absolútne pixely)
- Bounding-box overlay nad PDF canvasom, editovateľné prvky, manuálne doplnenie
- Live-validovaná doložka s predvyplnením ~95 % polí z certifikátu, profilu a analýzy
- Šablóny doložiek, profily advokáta/kancelárie (SAK reg. č., IČO)

### 🔐 Bezpečnosť a autorizácia
- Keychain identity scanner s detekciou **mandátneho atribútu** certifikátu
- Gate „QTS čas ≥ čas konverzie“ — CEZZK by inak zápis zamietla
- Serverový čas EZZK (nie lokálne hodiny), zhoda identity certifikát ↔ doložka
- ASiC-E packager (ETSI EN 319 162), demo podpisovač jasne označený ako nezáväzný

### 🗂️ Evidencia
- Lokálny register konverzií (JSON, Application Support) so stavmi a CSV exportom
- Dashboard s hľadaním, frontou odoslania do CEZZK a alarmom lehoty 24 h
- Fakturovateľný prehľad úkonov pre vyúčtovanie klientovi (sadzobník)

---

## Build & spustenie

```bash
cd Autogram

# knižnica + appka (debug)
swift build

# testy — 24 (unit + full-pipeline integration)
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test

# .app bundle (release)
./build_app.sh --release
open .build/arm64-apple-macosx/release/Autogram.app
```

> SwiftUI makrá potrebujú plný Xcode toolchain. Pri použití iba Command Line Tools nastavte:
> `export DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer`

Interaktívna galéria diagramov: [`docs/gallery.html`](docs/gallery.html) *(otvoriť v prehliadači)*

---

## Testovacia matica

| Sada | Pokrytie |
|---|---|
| `PDFAnalysisEngineTests` | počítadlá strán/listov, blank detekcia, klasifikácia A4/A3/Letter, návrh titulu |
| `SecurityElementsDetectorTests` | pečiatka + podpis na syntetickom skene, prázdna strana = 0 prvkov, IoU merger |
| `AttestationXMLTests` | elementy schémy, escaping, LegalSubject varianta, SHA-256 golden vector, validátory |
| `PDFAConverterTests` | hlavička 1.7, pdfaid markery, zachovanie textu, raster mód, EmbeddedFile round-trip |
| `EvidenceAndPackagingTests` | perzistencia registra, CSV escaping, ZIP/ASiC-E štruktúra, Mock EZZK, demo podpis |
| `ConversionPipelineIntegrationTests` | **celý tok**: sken → analýza → detekcia → PDF/A → doložka → embed → sign → EZZK |

---

## Legislatívna kotva

- **§ 35–39** zákona č. 305/2013 Z. z. — oprávnenie advokáta, postup, účinky osvedčenej kópie
- **Vyhláška MIRRI č. 70/2021 Z. z.** — obsah doložky (prílohy 1/3), forma XML-in-PDF, mandátny certifikát + QTS, evidencia, jednorazové evidenčné čísla, 24 h lehota
- **eIDAS 910/2014 + IR 2015/1506** — PAdES/CAdES/XAdES v ASiC kontajneroch; XAdES_ZEP zakázaný

Detailná právna rešerš a reverse engineering Podpisuj.sk: [`AUTOGRAM_ZAKO_MODULE_SPEC.md`](AUTOGRAM_ZAKO_MODULE_SPEC.md)
Dizajnové špecifikácie: [`AUTOGRAM_MASTER_UI_UX_SPEC.md`](AUTOGRAM_MASTER_UI_UX_SPEC.md) · [`AUTOGRAM_UI_UX_CONCEPTS.md`](AUTOGRAM_UI_UX_CONCEPTS.md) · [`AUTOGRAM_SWIFTUI_DEVELOPER_BLUEPRINT.md`](AUTOGRAM_SWIFTUI_DEVELOPER_BLUEPRINT.md)

---

## Roadmapa

| Oblast | Stav | Ďalší krok |
|---|---|---|
| EZZK API | Mock + HTTP kostra | oficiálna OpenAPI špecifikácia od MIRRI/IOMO |
| KEP podpis | DEMO podpisovač (ASiC-E manifest) | EU DSS helper / PKCS#11 most pre reálny mandátny certifikát + RFC 3161 QTS |
| Smery E→P, E→E | architektúra pripravená | formuláre príloh č. 1 a 5 |
| veraPDF validácia | nie je integrovaná | voliteľné via bundled CLI |
| Formuláre v1.2 (2027) | verziovaný placeholder | auto-update artefaktov z formulare.slovensko.sk |

> ⚠️ **Právna poznámka:** aplikácia je vo vývoji. DEMO režim podpisu negarantuje právne účinky kvalifikovaného elektronického podpisu — pred produkčným nasadením pripojte reálny mandátny certifikát cez kvalifikovaný podpisový modul a overte integráciu s IS EZZK.

---

*Diagramy v štýle [diagram-design](https://github.com/cathrynlavery/diagram-design) — editorial tokens: white-smoke paper, jet-black ink, atomic-tangerine accent, blue-slate muted. Bez tieňov, bez Mermaid slopu.*
