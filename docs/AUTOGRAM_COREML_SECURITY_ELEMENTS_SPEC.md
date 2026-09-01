# Feature Spec: Core ML Detector bezpečnostných prvkov

Status: návrh (P2E pilot, fáza návrhu) · Dátum: 2026-09-01 · Autor návrhu: Hermes (agent) pre Majo
Partnerský dokument: `docs/AUTOGRAM_COREML_TRAINING_PLAN.md`, nástroje v `tools/ml-dataset/`

## 1. Zhrnutie

Pridať do ZaKo workflow voliteľný **trénovaný on-device object detector** (Create ML → Core ML),
ktorý navrhne a klasifikuje bezpečnostné prvky pôvodného dokumentu (podpis, pečiatka, reliéfna
slepotlač, parafa, iný prvok) priamo v Analysis Canvas. Model zostáva čisto návrhovým nástrojom:
**AI navrhuje, človek potvrdzuje** (zachované a posilnené existujúce pravidlá z
`ZAKO_EXTERNAL_REQUIREMENTS_SPEC_2026-08-28.md` a production-readiness plánu).

## 2. Motivácia

Dnešný `BuiltInVisionProvider` je heuristika (farba/tma pixelové masky, connected components,
OCR a barcode exclusion). Funguje, ale:

- nemá learned klasifikáciu (parafa vs. malý podpis, typ pečiatky),
- je citlivý na prahy a kvalitu skenu,
- reliéfnu slepotlač vidí len konzervatívne cez tmavú masku.

Learned detector doplní presnosť a klasifikáciu; heuristika zostáva ako vždy-on bezpečná sieť
a fallback pri chybe načítania modelu.

## 3. Architektúra

```text
PDF strana
  -> rasterizácia na CGImage (existujúci renderTargetWidth, orientácia zachovaná)
  -> Vision VNCoreMLRequest
  -> vlastný Core ML object detector (.mlmodelc)
  -> VNRecognizedObjectObservation (label, confidence, boundingBox)
  -> mapping na SecurityElement (kind, confidence, NormalizedRect, reviewState: .pending)
  -> DetectionPipeline merge s BuiltInVisionProvider + voliteľným LLM
  -> Analysis Canvas (manuálne potvrdenie/zamietnutie)
```

Nový typ v `AutogramKit/VisionAI/`:

```swift
public struct CoreMLSecurityElementsProvider: SecurityElementsProviding {
    public var providerName: String { "Core ML Security Elements" }
    // init načíta .mlmodelc z bundle alebo ~/Library/Application Support/Autogram/Models/
    // detect() vykreslí strany, spustí VNCoreMLRequest, premapuje na SecurityElement
}
```

### 3.1 Kľúčové integračné body

| Integračný bod | Detail |
|---|---|
| `SecurityElementsProviding` | Nový provider implementuje existujúci protokol |
| `DetectionPipeline` | Merge cez `SecurityElementMerger` (IoU dedup 0.4) |
| `SecurityElement` | Mapovanie label → `Kind`, `detectedByAI: true`, `reviewState: .pending` |
| `SecurityReviewStamp.detectorIdentifier` | Nová hodnota `CoreMLSecurityElementsProvider v1` |
| `NormalizedRect` | Vision bottom-left origin = konvencia komponentov, skontrolovať `visionBox()` |
| Orientácia | Použiť existujúci render pipeline (`BuiltInVisionProvider.render`), rotácie ošetrené |
| Fallback | Chyba načítania modelu → log + bežná heuristika, nikdy nespadnúť |
| Settings | Nová AI Vision provider karta (Interný / Core ML / oMLX / Ollama / Custom API) |

### 3.2 Vytvorené súbory (návrh)

- `Autogram/Sources/AutogramKit/VisionAI/CoreMLSecurityElementsProvider.swift`
- `Autogram/Sources/AutogramKit/Resources/SecurityElementsDetector.mlmodel` (alebo `.mlmodelc`)
- `Autogram/Tests/AutogramKitTests/CoreMLDetectorTests.swift`
- `tools/ml-dataset/` (príprava datasetu, už existuje, pozri README)

## 4. Triedy modelu v1

V1 zatiaľ bez reliéfnej slepotlače ako samostatnej learned triedy (najťažšia trieda, často
takmer neviditeľná na skene: závisí od svetla, kontrastu, kompresie, papiera). Prvky typu
reliéf sa nechajú na heuristiku `detectEmbossedSeals`, kým model v2 nepreukáže recall.

| Label | `SecurityElement.Kind` | Poznámka |
|---|---|---|
| `official_stamp` | `.officialStamp` | okrúhla/kolová pečiatka, modro-fialová farba |
| `handwritten_signature` | `.handwrittenSignature` | vlastnoručný podpis |
| `initial` | `.initial` | parafa, malá výška |
| `other_security_element` | `.other` | notárska pripojka, čiary, QR (QR/čiary aj heuristika) |
| (v2) `embossed_seal` | `.embossedSeal` | odložené, kým recall nie je dokázaný |

Negatívna množina (bez anotácií) je povinná: prázdne strany, text, tabuľky, logá, podpisové
riadky, farebné zvýraznenia, tiene, šum, QR, ručné poznámky.

## 5. Právo a hranice (respektuje existujúce zásady repozitára)

- Detektor je **technická pomôcka**. Nie je dôkazom pravosti ani úplnosti prvkov.
- Výsledok je vždy `detectedByAI: true` + `reviewState: .pending`, automatické potvrdenie
  bez ľudskej akcie je zakázané (rovnako ako v `ZakoSessionStore`).
- `AttestationPreflight` ďalej vyžaduje potvrdenie všetkých prvkov a strán.
- Do doložky a XML ide slovný opis potvrdených prvkov; model confidence neputuje do XML
  ako pravostná informácia, len do UI návrhu.
- Dataset: **žiadne klientske listiny**. Syntetické/anonymné vzorky (pozri tréningový plán).
- Model neodošle pixely ani výsledky nikam: beží on-device cez Vision/Core ML.

## 6. UX

- Analysis Canvas: návrhy detektora sa zobrazujú ako `pending` prvky (existujúci UI flow),
  farba/ikona podľa `Kind.sfSymbol`, v inspektore číslo confidence.
- Settings: provider karta "Core ML detektor (lokálny model)" s verziami modelu a dátumu
  buildu. Ak model chýba, karta ukáže stav a flow pokračuje heuristikou.
- Batch: detekcia beží v `Task.detached` ako dnes; progress text "Detegujem bezpečnostné
  prvky…" zostáva; Core ML odporúčame `MLModelConfiguration.computeUnits = .all` (ANE+GPU).

## 7. Akceptačné kritériá (v1)

- `swift test` zelený vrátane nových testov (načítanie modelu, mapping, fallback pri chýbajúcom modelu).
- Na syntetickom eval sade (úloha 1 v tréningovom pláne) model dosiahne aspoň:
  - recall ≥ 0.90 pre stamp/signature, ≥ 0.80 pre initial,
  - precision ≥ 0.85 (všetky triedy),
  - false negatives na stránku ≤ 0.05 (nezávisle na triede).
- DetectionPipeline merge: žiadne duplikáty > IoU 0.4, výsledok sorted (page, y).
- Reálne documenty z pilotnej prevádzky: kvalitu ručne vyhodnotí advokát pri bežnom review,
  false negatives sa logujú do evidence (bez obsahu dokumentu) pre iteráciu v2.

## 8. Riziká

| Riziko | Mítigácia |
|---|---|
| Reliéfna slepotlač: nízký recall | Odložená trieda v1; heuristika zostáva; v2 vlastný mikrodataset so skenmi pod rôznym uhlom |
| Malé paras (10 až 15 mm) | Trénovať na renderoch ≥ 1240 px, v1 recall ≥ 0.80 |
| Falošná istota používateľa | UI text rozlišuje "navrhnuté" vs "potvrdené", review gate nezmenený |
| Model drift pri inej kvalite skenu | Eval per scan quality (300/600 dpi, foto) v tréningovom pláne |
| Veľkosť .mlmodel | Create ML object detection má desiatky MB; merge gate: rast app size < 100 MB |

## 9. Otvorené otázky

1. Balenie modelu: inside app bundle vs. stiahnutie on-demand (odporúčame bundle v1, app size akceptovateľný).
2. A/B vs. nahrádzanie heuristiky: v1 navrhujeme **merge** (heuristika + model), v2 možné nahradiť.
3. Mať v modeli aj triedu "notárska pripojka" ako osobitnú triedu (dnes `.other`)?
4. Dá sa získať vzorka pravých pečiatok/podpisov na mikrodataset bez klientskych dát (vlastné pečiatky SKALLARS, kolegovia, notárski kandidáti)?
