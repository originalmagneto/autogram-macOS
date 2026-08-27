<p align="center">
  <img src="docs/diagrams/hero.svg" alt="Autogram macOS: Podpisovanie a Zaručená konverzia" width="100%">
</p>

# Autogram macOS

**Natívna SwiftUI aplikácia na elektronické podpisovanie dokumentov** so štandardným režimom podpisovania (KEP + kvalifikovaná časová pečiatka) a **advanced režimom Zaručená konverzia** podľa § 35-39 zákona č. 305/2013 Z. z. o e-Governmente a vyhlášky MIRRI č. 70/2021 Z. z.

`macOS 26+` (Liquid Glass) · `SwiftUI + @Observable` · `0 Swift package závislostí` · `Swift 6 strict concurrency` · `86 testov (83 prešlo, 3 live skipped) ✅`

> 📋 Implementačná dokumentácia fáz 1-4 vrátane validácií a limitov: [`docs/PHASES.md`](docs/PHASES.md)

---

## Prehľad: jeden nástroj, dva režimy

### ✍️ Štandardný režim: Podpisovanie
Klasická autorizácia dokumentov v štýle moderného macOS štúdia: vlož PDF, pozri náhľad, voliteľne umiestni vizuálnu pečiatku podpisu priamo do stránky a podpíš KEP s kvalifikovanou časovou pečiatkou. Hlavné akčné tlačidlo je trvalo ukotvené v spodnej lište (Sticky Action Bar).

### 🏛️ Advanced režim: Zaručená konverzia
Zaručená konverzia je slovenský ekvivalent osvedčovania listín u notára: papierový dokument sa prevedie do elektronickej podoby tak, že nový dokument má **právne účinky osvedčenej kópie**. Advokát na to potrebuje mandátny certifikát a kvalifikované časové pečiatky: aplikácia sa postará o všetko ostatné. V tomto režime sa nepoužívajú grafické podpisy; autorizáciou je KEP s mandátnym atribútom nad celým balíkom.

Kým existujúce nástroje (Podpisuj.sk, D.Convert) sú Java aplikácie s desiatkami manuálne vypĺňaných polí, Autogram robí z konverzie **2-3 kliky**: automaticky rozpozná strany, listy aj bezpečnostné prvky, stiahne evidenčné číslo z EZZK, vygeneruje živú osvedčovaciu doložku a celé to autorizuje.

---

## Architektúra

<img src="docs/diagrams/architecture.svg" alt="Architektúra Autogram macOS" width="100%">

Tri vrstvy: natívna SwiftUI prezentácia (`AutogramApp`) s dvoma reaktívnymi session store (`@Observable SigningSessionStore` pre štandardný podpis a `ZakoSessionStore` pre advanced režim) a testovateľná knižnica `AutogramKit`: enginy, dokumentové služby a infraštruktúra. Bez externých balíkových závislostí; PDF/A zápis, XML generátor aj ZIP/ASiC-E packager sú vlastná implementácia. Reálne tokenové podpisovanie používa natívny CryptoTokenKit alebo EngineBridge s Java/DSS engine pre PKCS#11 tokeny.

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

Každá konverzia prechádza stavmi od konceptu po potvrdenie v centrálnej evidencii. Aplikácia stráži zákonné lehoty: neodoslané záznamy po 20 hodinách indikuje varovný stav v dashboarde.

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

1. **Podpísať bežný dokument?** → sidebar *Podpisovanie*: pretiahni PDF (`⌘O`), voliteľne umiestni pečiatku, klikni **Podpísať KEP** (`⌘⏎`). Alebo označ súbory priamo vo Finderi → *Rýchle akcie* → **Podpísať s QES + QTS (Autogram)**.
2. **Previesť papierový originál do elektronickej podoby?** → sidebar *Zaručená konverzia*: pretiahni sken originálu, skontroluj AI-detekované prvky cez plávajúci markup panel, over doložku v živom náhľade, klikni **Autorizovať konverziu**.
3. **Spravovať evidenciu a CEZZK?** → sidebar *Register konverzií* → odoslať dávku alebo exportovať CSV.

> Bez nastaveného EZZK beží evidencia v DEMO režime; bez pripojeného kvalifikovaného podpisového modulu podpisuje DEMO podpisovač (jasne označený).

---

## Funkcie

### ✍️ Modul Podpisovanie (štandard)
- Drag & drop **PDF aj obrázkové skeny** (JPEG/PNG/TIFF/HEIC s automatickou konverziou do PDF)
- Voliteľný **vizuálny podpis**: interaktívne umiestnenie na plátne dokumentu
- KEP podpis + QTS, identity z Keychainu / eID karty (CryptoTokenKit) alebo PKCS#11 tokenu cez EngineBridge
- Ukotvené akčné tlačidlá (`StickyActionBar`) s klávesovou skratkou `⌘⏎`
- Výstup: podpísané PDF (+ ASiC-E kontajner), priame akcie pre Finder a otvorenie
- **Finder Quick Action:** označené PDF alebo priečinky vo Finderi sa podpíšu pravým klikom (*Rýchle akcie* → Podpísať s QES + QTS) bez nutnosti otvárať okno appky

### 🏛️ Modul Zaručená konverzia (advanced)
- 5-krokový plynulý workflow stepper (`FlowStepBar`)
- Plávajúci segmentovaný markup toolbar (Výber, Pečiatka, Podpis, Pečať, Parafa)
- Ľavý pás miniatúr stránok (Thumbnail Strip) pre pohodlnú navigáciu vo viacstranových spisoch
- Živý náhľad Osvedčovacej doložky (Live Clause Preview) počas písania
- Automatické počítadlá: strany / neprázdne strany / listy / veľkosť listiny
- AI nálezy sa zlučujú s manuálnymi (manuálne úpravy prežívajú re-analýzu)
- Šablóny doložiek a správa profilu advokáta (SAK reg. č., IČO)

### 🤖 Modul AI Vision (voliteľný boost)
- **On-device detekcia beží vždy** (farebné/tmavé masky, connected components, radial coverage)
- **oMLX (Apple Silicon MLX):** natívna integrácia lokálneho MLX servovania (`http://localhost:8000/v1`) s modelmi Qwen2.5-VL / Llama-3.2-Vision; GPU akcelerácia priamo na Macu
- **Lokálny LLM:** Ollama (`llava`, `llama3.2-vision`, `qwen2-vl`) s offline spracovaním
- **API:** ľubovoľný OpenAI-compatible endpoint s bezpečným kľúčom v Keychain
- **Editovateľný klasifikačný prompt**: pokrýva § 37 typy (pečiatka so znakom, reliéfna pečať, parafa)
- IoU deduplikácia: LLM dopĺňa vstavané nálezy
- Výber providera cez prehľadné karty v Nastaveniach (konfigurácia sa zobrazí pod zvoleným režimom)

### 🔐 Bezpečnosť a autorizácia
- **Reálny KEP podpis**: XAdES-B/T v ASiC-E alebo PAdES-B/T priamo v PDF cez SecKey (CryptoTokenKit) alebo EngineBridge
- **Slovenská eID karta** (Cosmo 9.2 / eID_klient): certifikát a privátny kľúč sa čítajú z tokenu cez CryptoTokenKit; PIN sa zadáva v systémovom dialógu
- **I.CA SecureStore / Starcos**: kvalifikovaný certifikát a podpis cez PKCS#11 EngineBridge
- **Live detekcia smartkarty** v spodnom paneli sidebaru (`SmartcardHUDStatus`)
- **Mandátna brána**: Zaručená konverzia kontroluje mandátny certifikát SAK pred autorizáciou

### 🗂️ Register a evidencia
- Lokálny register konverzií so SQLite/JSON úložiskom a CSV exportom
- Dashboard: sumárne karty, segmentovaný filter podľa stavu, časová os spracovania
- Kontextové menu pre rýchle kopírovanie evidenčného čísla a SHA-256 odtlačku
- Bezpečný potvrdzovací dialóg pred vymazaním záznamu z evidencie
- Hromadné odosielanie čakajúcich záznamov do IS EZZK priamo z dashboardu

---

## Build & spustenie

```bash
cd Autogram

# knižnica + appka (debug)
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift build

# testy (86 testov, 83 prejde, 3 live testy sú voliteľné a bez hardvéru sa preskočia)
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test

# .app bundle (release)
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh --release
open .build/arm64-apple-macosx/release/Autogram.app
```

Aplikácia je tiež nainštalovaná v systéme: `/Applications/Autogram macOS.app`.

---

## Legislatívna kotva

- **§ 35-39** zákona č. 305/2013 Z. z. (oprávnenie advokáta, postup, účinky osvedčenej kópie)
- **Vyhláška MIRRI č. 70/2021 Z. z.** (obsah doložky, forma XML-in-PDF, mandátny certifikát + QTS, evidencia, 24 h lehota)
- **eIDAS 910/2014 + IR 2015/1506** (PAdES/XAdES v ASiC kontajneroch)

---

*Diagramy v štýle [diagram-design](https://github.com/cathrynlavery/diagram-design) - editorial tokens: white-smoke paper, jet-black ink, atomic-tangerine accent, blue-slate muted. Bez tieňov.*
