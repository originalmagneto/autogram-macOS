# Tréningový plán: Core ML detector bezpečnostných prvkov

Status: návrh (P2E pilot) · Dátum: 2026-09-01
Partnerský dokument: `docs/AUTOGRAM_COREML_SECURITY_ELEMENTS_SPEC.md`, nástroje v `tools/ml-dataset/`

## 0. Cieľ a hardvér

Cieľ: natrénovať object detection model (Create ML), ktorý na rendri PDF strany označí a
klasifikuje bezpečnostné prvky podľa spec dokumentu. Tréning beží lokálne.

Hardvér: Mac Studio M1 Max, 32 GB unified memory. Create ML object detection tréning na
Apple Silicon beží cez MLCompute (GPU/ANE) a pre dataset v stovkách obrázkov na triedu je
pohodlne schopný. Vrstevnica náročnosti:

| Úloha | Náročnosť na 32 GB M1 Max |
|---|---|
| Rasterizácia PDF + anotácia | zanedbateľná |
| Create ML object detector (stovky obrázkov) | hodiny tréningu, beží na pozadí |
| Fine-tuning VLM cez Unsloth/MLX | možné pre 4 až 8 B modely s QLoRA, ale nie je to cesta v1 |

## 1. Etapa 0: nástroje a anotácie (týždeň 1)

### Nástroj na bounding boxes

Hostovaný IBM Cloud Annotations (cloud.annotations.ai) **skončil**, oficiálne repo uvádza
"the hosted version is no longer available". Aktualizované odporúčanie:

| Nástroj | Platforma | Create ML export | Odporúčanie |
|---|---|---|---|
| **RectLabel** (Pro) | macOS natívna appka, offline | priamy export Create ML | **Prvá voľba pre Mac** |
| **VGG Image Annotator (VIA)** | jeden HTML súbor, offline v prehliadači | vlastný JSON (konverzia v toolch) | Zadarmo, nulová inštalácia |
| **CVAT** (self-hosted docker) | web, docker | COCO/VOC/YOLO (konverzia) | Pre väčšie dávkové anotácie |
| **Label Studio** | pip, web | JSON/VOC (konverzia) | Ak už niečo takého beží |
| Cloud Annotations | hostovaná služba | - | **nepoužívateľné, služba skončila** |

Praktický postup na Macu: nainštalovať RectLabel z Mac App Store, importovať rendere strán,
kresliť boxy, export Create ML (priamo kompatibilný). Ak chceš 100 % free cestu: VIA
(`via.html` od Oxford VGG) plus konverzný skript v `tools/ml-dataset/`.

### Príprava dát pred anotáciou

1. Export strán z PDF do PNG: `python3 tools/ml-dataset/prepare_dataset.py pdf2png --src ... --dst ... --width 1240`
2. Priemer 1240 px na šírku A4 (150 dpi): dostatočné pre malé paras a rýchly tréning.
3. Voliteľné augmentačné rendere: odtiene sivej, mierna rotácia ±2°, JPEG kompresia q75
   (simulácia skenu), nižšia dpi 100. Robia sa až po anotácii cez skript `augment.py` v druhej fáze
   (augmentácia obrázkov bez zmeny anotácií: rotácia/šum/kompresia mení pixely, boxy zostávajú).

### Pravidlá anotácie

- Box tesne okolo prvku, bez okolia textu.
- Každá inštancia v každom obrázku (aj prekrývajúce sa).
- Prekrývajúce sa pečiatka a podpis: dva boxy.
- Nejasný prvok: označiť ako `other_security_element`, klasifikáciu rieši človek v review.
- Označovať aj "sub-prvky": parafa na podpisovom riadku má vlastný box.
- Vždy si z každej 10-tky strán nechať 1 stranu na eval sadu, rozdeľovať na úrovni dokumentu.

## 2. Etapa 1: prototypový dataset (týždeň 1 až 2)

Cieľ: overiť celý pipeline na malých číslach. Žiadne klientske dáta.

| Trieda | Min. obrázkov | Zdroj |
|---|---:|---|
| official_stamp | 50 | vlastné pečiatky, vzorky na bežných dokumentoch, syntetické rendere |
| handwritten_signature | 60 | vlastné podpisy v rôznych nástrojoch a hrúbke |
| initial | 40 | parafa ručne, syntetické rendere |
| other_security_element | 30 | QR/čiary/notárske pripojky, čiary |
| negative (bez boxov) | 80 | prázdne strany, text, tabuľky, logá |

Syntetické rendere: skript `tools/ml-dataset/make_synth_pages.py` generuje A4 PNG s náhodným
textom a umiestnenými prvkami (elipsa pečiatka, krivka podpis, malá parafa). Skript nie je
náhrada za reálne skeny, slúži na smoke test a na vyrovnanie tried.

Split: dokumentovo (nie pixelovo). 70 / 15 / 15 (train / val / test).

## 3. Etapa 2: Create ML tréning v1 (týždeň 2 až 3)

Postup:

1. Create ML app → nový projekt → šablóna **Object Detection**.
2. Training Data: priečinok s PNG + `annotations.json` (Create ML formát, konverzia cez
   `coco_to_createml.py` ak anotuješ v inom tooli).
3. Validation: Automatic (alebo vlastný eval priečinok).
4. Advanced: iterations 200 až 400 (štart 200), batch default.
5. Tréning: na M1 Max očakávaj minúty až desiatky minút pre stovky obrázkov; priebeh loss
   v Training tab.
6. Evaluation tab: precision/recall per class, IoU threshold 0.5. Test set nechávať mimo
   tréningu, vyhodnotiť až po finálnej iterácii.
7. Export `.mlmodel`, pridať do AutogramKit, build, testy.

Merenie kvality:

- per class precision / recall,
- mAP @ IoU 0.5,
- false negatives per page (kľúčová metrika pre ZaKo),
- latencia na stranu (cieľ < 300 ms na M1 Max pri 1240 px),
- rýchlostné meranie cez `MLModel` + VNCoreMLRequest, merať na `.all` compute units.

## 4. Etapa 3: integrácia do Autogramu (týždeň 3 až 4)

Podľa spec dokumentu:

1. `CoreMLSecurityElementsProvider.swift` implementuje `SecurityElementsProviding`.
2. `.mlmodel` do `AutogramKit/Resources/`, Xcode ho skompiluje na `.mlmodelc`.
3. Provider do `DetectionPipeline` (merge s BuiltInVisionProvider, dedup IoU 0.4).
4. Výsledky vždy `reviewState: .pending`, `detectedByAI: true`.
5. Settings karta s verziami modelu a dátumu buildu.
6. Fallback: ak sa model nepodárilo načítať, beží len BuiltInVisionProvider (log + UI hláška).
7. Testy: načítanie modelu, mapping tried, fallback, IoU merge, orientácia strán.

## 5. Etapa 4: pilot a iterácia v2 (týždeň 4+)

- Pilot v bežnej advokátskej praxi na vlastných dokumentoch.
- Logovať (bez obsahu dokumentu): trieda, confidence, potvrdený/zamietnutý, či model navrhol,
  či človek doplnil manuálne. To dáva dáta na v2.
- v2: pridať `embossed_seal` triedu, mikrodataset reliéfov nasnímaný pri rôznych svetlách
  a uholoch pohľadu, zvýšiť recall na malé paras, možné nahradenie heuristiky.

## 6. Rozpočet času (orientačný)

| Fáza | Čas | Výstup |
|---|---|---|
| Nástroje + rasterizácia | 2 až 4 h | rendere strán pripravené na anotáciu |
| Anotácia 250 až 300 strán | 6 až 10 h | Create ML dataset |
| Tréning v1 + evaluácie | 2 až 4 h strojového času | .mlmodel |
| Integrácia + testy | 1 až 2 dni pracovné | provider v appke |
| Pilot + v2 dáta | priebežne | logy na iteráciu |

## 7. Poznámka o Unsloth

Unsloth je pre tento use case voliteľný, nie primárny. Prvý detector je Create ML/Core ML,
lebo výstup je presne to, čo Vision a `VNCoreMLRequest` očakávajú a nechceš server ani
Python runtime v appke. Unsloth/MLX fine-tuning VLM má zmysel neskôr, ak chceš lokálny
slovný opis dokumentu alebo druhý názor (druhý stupen), nie bounding boxes ako v1.

## 8. Bezpečnosť dát

- Tréningový dataset: len syntetické/anonymné vzorky, žiadne klientske listiny.
- Tréning beží lokálne, dataset neodchádza z Macu.
- Ak sa dataset niekedy bude zálohovať: šifrované úložisko, žiadne verejné repo.
- Do repozitára dávaš len kód nástrojov a malé syntetické ukážky, nie tréningový dataset.
