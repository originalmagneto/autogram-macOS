# Autogram macOS
- [🌎 English version](README.md)

Autogram je desktopová aplikácia na podpisovanie a overovanie elektronických dokumentov v súlade s nariadením eIDAS. Tento repozitár je macOS-špecializovaný fork upstream projektu [Slovensko.Digital Autogram](https://github.com/slovensko-digital/autogram): zachováva podpisovacie jadro, HTTP API, CLI workflow aj podporu eFormov, ale prepracúva desktopové UI tak, aby bolo na macOS čitateľnejšie, prirodzenejšie a dôveryhodnejšie pri reálnom podpisovaní dokumentov.

## Predmet Projektu
- Podpisovanie a overovanie elektronických dokumentov v desktopovej aplikácii.
- Podpora právnych, firemných a verejnosprávnych workflow, kde treba dokument skontrolovať ešte pred podpisom.
- Integrácia do interných systémov cez HTTP API, CLI a `autogram://` protokol.
- Zachovanie kompatibility so slovenskými eGovernment formulármi a PKCS#11 zariadeniami.

## Predmet a Dôvod Redizajnu
Redizajn tejto vetvy nie je o zmene podpisovacej logiky. Je o tom, aby kritické kroky pri práci s dokumentom pôsobili istejšie a zrozumiteľnejšie.

### Čo je predmetom redizajnu
- úvodná obrazovka a vstup do workflow,
- podpisovacia a overovacia obrazovka,
- sidebar s metadátami dokumentu,
- overlay dialógy, najmä aktualizácie a varovania,
- dark mode čitateľnosť a konzistentný macOS vizuálny systém.

### Prečo sa appka redizajnuje
- Podpisovanie dokumentov je vysoko dôsledkový úkon a UI musí používateľa viesť, nie rozptyľovať.
- Predchádzajúce obrazovky boli funkčne správne, ale miestami príliš husté a vizuálne ploché.
- Stav podpisov, existujúce upozornenia a výber certifikátu potrebovali lepšiu informačnú hierarchiu.
- Dark mode a overlay dialógy potrebovali stabilnejšie kontrasty, rozmery a mikrocopy.
- Nový používateľ potrebuje pochopiť workflow ešte predtým, než rieši certifikát, PIN alebo typ podpisu.

Detailnejší plán rollout-u je v [PLAN.md](PLAN.md). Postup synchronizácie s upstream projektom je v [PORTING.md](PORTING.md).

## Screenshoty
### Úvodná obrazovka
![Úvodná obrazovka Autogram macOS](assets/readme/autogram-macos-home.png)

Úvodná obrazovka po redizajne:
- vysvetľuje základný workflow ešte pred otvorením súboru,
- ponúka jasný vstup cez drag and drop alebo výber súboru,
- ukazuje podporované typy dokumentov a hromadné podpisovanie,
- zobrazuje aktualizačný dialóg vo väčšom a zrozumiteľnejšom overlayi.

### Kontrola dokumentu a podpisovanie
![Podpisovacia obrazovka Autogram macOS](assets/readme/autogram-macos-signing.png)

Podpisovacia obrazovka po redizajne:
- drží náhľad dokumentu ako dominantný prvok,
- zobrazuje stav podpisovania a zvolený certifikát priamo nad náhľadom,
- dáva jasne najavo, či je dokument pripravený na podpis,
- sústreďuje formát podpisu, časovú pečiatku a podpisové CTA do jedného čitateľného bloku.

## Hlavné Funkcionality
- Desktopové podpisovanie a overovanie dokumentov v single-window workflow.
- Podpora podpisových profilov a dokumentových flow ako PAdES, XAdES, CAdES a slovenské eFormy.
- Kontrola existujúcich podpisov pred ďalším podpisom.
- Hromadné podpisovanie z príkazového riadku.
- Integrácia do webových a interných systémov cez HTTP API.
- Spúšťanie cez vlastný protokol `autogram://`.
- Podpora bežných PKCS#11 kariet, natívnych eID integrácií a dostupných PKCS#12 workflow.

## Štátne Elektronické Formuláre
Autogram pracuje aj s bežnými slovenskými verejnosprávnymi workflow:

- `slovensko.sk` formuláre, vrátane automatického načítania schém a metadát,
- ORSR formuláre, vrátane práce s embedovanými schémami pri podpise,
- formuláre Finančnej správy v `.asice` kontajneroch aj XML workflow, ak je známy identifikátor formulára.

### slovensko.sk
Autogram dokáže v stand-alone režime otvárať a podpisovať formuláre zverejnené v [statickom úložisku](https://www.slovensko.sk/static/eForm/dataset/) na slovensko.sk. Pri integrácii cez API je možné nastaviť v body `parameters.autoLoadEform: true`. Potrebné XSD, XSLT a ďalšie metadáta sa potom stiahnu automaticky podľa typu podpisovaného formulára.

### Obchodný register SR
ORSR formuláre fungujú navonok rovnako ako formuláre zo slovensko.sk. Autogram typ formulára deteguje automaticky a pri API je potrebné nastaviť spomínaný parameter `autoLoadEform`. Technicky sa ORSR formuláre odlišujú tým, že používajú embedované schémy v datacontainer-i namiesto referencovaných schém.

Ak je pri podpise cez API zapnutý parameter `autoLoadEform` a formulár je z ORSR, automaticky sa nastaví vytváranie podpisu s embedovanou schémou. Pri poskytnutí XSD a XSLT v parametroch bez `autoLoadEform` je potrebné nastaviť aj `parameters.embedUsedSchemas: true`.

### Finančná správa SR
Podpísané formuláre v `.asice` kontajneroch vie Autogram automaticky detegovať v stand-alone režime aj cez API pri použití `autoLoadEform`.

Pri podpisovaní však treba explicitne určiť typ formulára:
- v stand-alone režime musí názov súboru obsahovať `_fs<identifikator>` a mať príponu `.xml`,
- pri podpise cez API je potrebné nastaviť `parameters.fsFormId: "<identifikator>"`.

Príklady názvov:

```text
moj-dokument_fs792_772.xml
dalsi-dokument_fs792_772_test.xml
nazov-firmy_fs2682_712_nieco-dalsie.xml
```

Identifikátory formulárov Finančnej správy je možné získať z [tohto zoznamu](https://forms-slovensko-digital.s3.eu-central-1.amazonaws.com/fs/forms.xml) ako atribút `sdIdentifier`.

## Spustenie na macOS
Oficiálne cross-platform release balíčky sú dostupné v upstream [Releases](https://github.com/slovensko-digital/autogram/releases). Táto vetva je zameraná najmä na macOS aplikáciu a vývoj UI/UX.

### Možnosť A: Spustenie zo zdrojových kódov
```sh
./mvnw -q -Psystem-jdk -DskipTests package
open target/app-image/Autogram.app
```

### Možnosť B: Spustenie zo stiahnutého DMG bez notarizácie
```sh
# 1) Odstránenie quarantine atribútu z DMG
xattr -dr com.apple.quarantine "$HOME/Downloads/Autogram-<verzia>.dmg"

# 2) Pripojenie DMG a skopírovanie appky do Applications
hdiutil attach "$HOME/Downloads/Autogram-<verzia>.dmg"
ditto "/Volumes/Autogram/Autogram.app" "/Applications/Autogram.app"
hdiutil detach "/Volumes/Autogram"

# 3) Odstránenie quarantine z nainštalovanej appky
xattr -dr com.apple.quarantine "/Applications/Autogram.app"

# 4) Lokálny ad-hoc self-sign
codesign --remove-signature "/Applications/Autogram.app" || true
codesign --force --deep --sign - --timestamp=none "/Applications/Autogram.app"
codesign --verify --deep --strict --verbose=2 "/Applications/Autogram.app"

# 5) Spustenie
open -a "/Applications/Autogram.app"
```

Poznámky:
- Ide o lokálny ad-hoc podpis, nie Apple notarizáciu.
- Na verejnú distribúciu bez varovaní treba Apple Developer signing a notarizáciu.

## Integrácia
Swagger dokumentácia pre HTTP API je dostupná na [GitHube](https://generator3.swagger.io/index.html?url=https://raw.githubusercontent.com/slovensko-digital/autogram/main/src/main/resources/digital/slovensko/autogram/server/server.yml) alebo po spustení aplikácie na [http://localhost:37200/docs](http://localhost:37200/docs).

Aplikáciu je možné vyvolať aj priamo z prehliadača alebo inej aplikácie otvorením URL so špeciálnym protokolom `autogram://`, napríklad `autogram://go`.

## Konzolový Mód
Autogram je možné používať aj z príkazového riadku pre skriptované a hromadné workflow.

```sh
autogram --help
```

Na Windows:

```sh
autogram-cli --help
```

## Podporované Karty a Ovládače
- Akákoľvek PKCS#11-kompatibilná karta, ak je známa cesta k ovládaču.
- Natívna podpora pre slovenský občiansky preukaz.
- Natívna podpora pre I.CA SecureStore, MONET+ ProID+Q a Gemalto IDPrime 940.

Doplnenie ďalších kariet je zvyčajne jednoduché, pokiaľ používajú PKCS#11.

## Vývoj
### Predpoklady
- JDK 24 s JavaFX
- Maven
- Voliteľne Visual Studio Code alebo IntelliJ IDEA Community Edition

Na macOS odporúčame Liberica JDK s JavaFX.

### Test a Build
```sh
./mvnw -q -Psystem-jdk test
./mvnw -q -Psystem-jdk -DskipTests package
```

Package build vytvorí aplikáciu v `target/app-image/Autogram.app`.

### Linux packaging
Súbor `docker-compose.yml` obsahuje služby pre packaging na Ubuntu, Debiane a Fedore:

```sh
docker compose up --build
```

Výsledné balíčky sa objavia v `packaging/output/`.

### Ďalšia technická dokumentácia
- [DEVELOPER.md](DEVELOPER.md)
- [PORTING.md](PORTING.md)
- [PLAN.md](PLAN.md)
- [UPSTREAM_SYNC_PR_CHECKLIST.md](UPSTREAM_SYNC_PR_CHECKLIST.md)

## Autori a Sponzori
Jakub Ďuraš, Slovensko.Digital, CRYSTAL CONSULTING, s.r.o., Solver IT s.r.o. a ďalší spoluautori.

## Licencia
Tento softvér je licencovaný pod licenciou EUPL v1.2. Pôvodne vychádza z projektu Octosign White Label od Jakuba Ďuraša, ktorý je licencovaný pod MIT, a so súhlasom autora je táto verzia distribuovaná pod licenciou EUPL v1.2.

V skratke to znamená, že softvér je možné používať komerčne aj nekomerčne a vytvárať z neho vlastné verzie, pokiaľ budú vlastné úpravy a rozšírenia publikované pod rovnakou licenciou a zostane zachovaný pôvodný copyright.
