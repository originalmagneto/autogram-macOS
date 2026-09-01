# ml-dataset: príprava datasetu pre Core ML detector bezpečnostných prvkov

Nástroje pre feature popísaný v `docs/AUTOGRAM_COREML_SECURITY_ELEMENTS_SPEC.md`
a tréningový plán `docs/AUTOGRAM_COREML_TRAINING_PLAN.md`.

Všetko je štandardná knižnica Pythonu 3 (žiadne pip závislosti). Rasterizácia PDF
potrebuje `pdftoppm` z poppler (`brew install poppler`).

## Prehľad pipeline

```text
PDF sady (syntetické/anonymné, žiadne klientske listiny)
  -> prepare_dataset.py pdf2png          (PDF -> PNG rendere, 1240 px)
  -> anotácia v RectLabel / VIA / CVAT   (bounding boxes + triedy)
  -> coco_to_createml.py                 (COCO/VIA -> Create ML annotations.json)
  -> split_dataset.py                    (dokumentový split train/val/test)
  -> Create ML app (Object Detection)    (tréning na Macu, export .mlmodel)
  -> AutogramKit/CoreMLSecurityElementsProvider
```

## Skripty

| Skript | Úloha |
|---|---|
| `prepare_dataset.py pdf2png` | Export všetkých strán zo všetkých PDF v priečinku do PNG (šírka 1240 px default) |
| `make_synth_pages.py` | Syntetický dataset (text + generované pečiatky/podpisy/parafy/čiary) na smoke test pipeline |
| `coco_to_createml.py` | Konverzia COCO JSON (CVAT, Label Studio, Roboflow) alebo VIA project JSON na Create ML formát; Create ML JSON prevaliduje a normalizuje labely |
| `split_dataset.py` | Dokumentový split 70/15/15 na train/val/test (strany jedného dokumentu nikdy nie sú v dvoch sadách) |

## Triedy (v1)

`official_stamp`, `handwritten_signature`, `initial`, `other_security_element`

Konverzia normalizuje bežné aliasy (`stamp`, `podpis`, `parafa`, `qr`, ...) na tieto triedy.
Iné labely prejdu alebo skript upozorní (napr. `embossed_seal` patrí do v2).

## Rýchly smoke test (bez vlastných dát)

```bash
cd tools/ml-dataset
python3 make_synth_pages.py --out /tmp/synth_dataset --pages 24 --seed 7
python3 split_dataset.py --src /tmp/synth_dataset --out /tmp/synth_splits --train 0.7 --val 0.15
# potom v Create ML app otvor /tmp/synth_splits/train ako Training Data
```

Poznámka: `make_synth_pages.py` skladá `annotations.json` v koreňi datasetu a obrázky v
`images/`; pred Create ML importom spoj obsah priečinka tak, aby `annotations.json` ležal
vedľa PNG (Create ML očakáva obrázky + JSON v tom istom priečinku):

```bash
cp /tmp/synth_splits/train/annotations.json /tmp/synth_splits/train_flat.json
mkdir -p /tmp/synth_train_flat
cp /tmp/synth_splits/train/*.png /tmp/synth_train_flat/
cp /tmp/synth_splits/train/annotations.json /tmp/synth_train_flat/annotations.json
```

## Poznámky k formátom

- **Create ML** (cieľový formát): JSON array; `x`,`y` je **stred** boxu v pixeloch od
  ľavého horného rohu; `width`,`height` v pixeloch.
- **COCO**: `bbox` je `[x, y, w, h]` od ľavého horného rohu (konverzia rieši posun na stred).
- **VIA**: rect regióny; label čítame z `region_attributes.label` (alebo `class`/`type`).
- **RectLabel**: exportuje Create ML formát priamo, použi `--format createml` na validáciu.

## Bezpečnosť dát

- Do tréningu nikdy klientske listiny. Syntetické alebo anonymné vzorky.
- Dataset nezdieľať v repozitári; do gitu ide len kód nástrojov.
- Tréning beží lokálne na Macu, dáta neopúšťajú stroj.
