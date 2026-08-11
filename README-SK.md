# Autogram macOS

Natívne elektronické podpisovanie pre Mac s Apple silicon.

[English README](README.md) | [Inštalácia](docs/native-macos-installation.md) | [Používateľský návod](docs/native-macos-user-guide.md) | [Architektúra](docs/native-macos-architecture.md)

Autogram macOS je natívna SwiftUI aplikácia na kontrolu, podpisovanie a validáciu elektronických dokumentov. Spája rýchle macOS rozhranie s overeným podpisovacím jadrom Autogram a European Commission DSS.

> Stav vývoja: aktívne preview. Natívna aplikácia vyžaduje macOS 27 alebo novší a Apple silicon. Verejné balíky ešte vyžadujú Developer ID podpis a notarizáciu.

## Hlavné možnosti

- natívny SwiftUI workspace s AppKit a PDFKit;
- PAdES Baseline T s povinnou kvalifikovanou časovou pečiatkou;
- ASiC-E a XAdES workflow;
- detekcia a kompletná DSS validácia existujúcich podpisov;
- opätovná validácia všetkých podpisov po pridaní ďalšieho podpisu;
- automatická detekcia karty, ovládača a certifikátov;
- predvolený certifikát samostatne pre každú kartu;
- bezpečné zadanie PIN-u bez jeho uloženia;
- knižnica PNG a PDF grafických podpisov;
- umiestnenie, zmena veľkosti, otočenie a výber strany priamo v PDF;
- otvorenie vloženého PDF z ASiC-E kontajnera jedným kliknutím;
- spracovanie viacerých súborov v jednom workspace;
- Finder Quick Action bez Terminálu;
- predvolené aj vlastné služby kvalifikovaných časových pečiatok.

## Ako podpisovanie funguje

1. Otvor jeden alebo viac PDF alebo ASiC-E súborov.
2. Najnovšie pridaný súbor sa po načítaní automaticky zobrazí.
3. Aplikácia zistí existujúce elektronické podpisy.
4. Kompletná DSS validácia sa spustí iba vtedy, keď podpisy existujú.
5. Aplikácia deteguje kompatibilnú kartu a dostupné podpisové certifikáty.
6. Vyber formát, certifikát, časovú pečiatku a prípadný grafický podpis.
7. Zadaj PIN v bezpečnom natívnom dialógu.
8. Výstup sa uloží pod novým názvom vedľa zdroja.
9. Podpísaný výstup sa znovu skontroluje a validuje.

Pôvodný dokument sa nikdy neprepíše.

## Podporované workflow

| Dokument | Funkcionalita |
| --- | --- |
| PDF | Náhľad, kontrola, validácia a podpis PAdES Baseline T |
| Už podpísané PDF | Zobrazenie podpisov, pridanie ďalšieho podpisu a opätovná validácia |
| ASiC-E `.asice` | Zoznam obsahu, náhľad vloženého PDF a zachovanie XAdES alebo CAdES rodiny |
| Nový ASiC-E | Vytvorenie kontajnera s XAdES |
| Viac súborov | Spoločné otvorenie a spracovanie vo workspace |

Upstream JavaFX aplikácia, HTTP API, CLI, eFormy a automatizačné skripty zostávajú súčasťou repozitára.

## Validácia podpisov

- **Platný** znamená, že DSS získal dostatočné dôkazy a nenašiel chybu podpisu.
- **Neplatný** znamená, že DSS našiel kryptografickú alebo validačnú chybu.
- **Validation indeterminate** znamená, že podpis existuje, ale nie sú dostupné dostatočné údaje o dôvere, revokácii, časovej pečiatke alebo certifikačnom reťazci.

Neurčitý výsledok nie je potvrdením platnosti ani neplatnosti. Validáciu možno opakovať po obnovení prístupu k potrebným online službám.

## Grafický podpis

Grafický podpis je voliteľné viditeľné vyobrazenie kryptografického podpisu v PDF. Nie je náhradou elektronického podpisu.

- Import podporuje transparentné PNG a PDF.
- Obrázok si zachováva pôvodný pomer strán.
- Nové umiestnenie sa predvolene vytvorí na poslednej strane, pri jednostranovom PDF na prvej strane.
- Kartu možno myšou presúvať, zväčšovať, zmenšovať a otáčať.
- Umiestnenie sa neprenáša do ďalšieho dokumentu.
- Preview používa zástupný čas. Finálny podpis obsahuje skutočný čas a stav časovej pečiatky.
- Po podpísaní sa editačný overlay odstráni, aby sa neprekrýval s vloženým podpisom.

## Požiadavky

### Používateľ

- Mac s Apple silicon;
- macOS 27 alebo novší;
- kompatibilná podpisová karta alebo token;
- arm64 alebo universal PKCS#11 middleware;
- I.CA SecureStore 8.3.1 alebo novší pre I.CA kartu;
- internet pre časové pečiatky a online validáciu;
- právo zapisovať do priečinka so zdrojovým dokumentom.

Intel-only knižnice a Rosetta nie sú podporované.

### Vývojár

- Xcode s macOS 27 SDK;
- Apple silicon build stroj;
- JDK 25 s JavaFX;
- Maven wrapper z repozitára.

## Lokálny build

```sh
export AUTOGRAM_JAVA_HOME="/path/to/arm64-jdk-with-javafx"
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
scripts/native-macos/build-native-app.sh
scripts/native-macos/sign-native-app.sh
open "build/native/Autogram macOS.app"
```

Lokálny build používa ad-hoc podpis a nie je notarizovaným verejným release balíkom.

## Finder Quick Action

1. V Autogram macOS otvor **Settings**.
2. Vyber **Install Finder Quick Action**.
3. Ak treba, zapni rozšírenie v **System Settings > General > Login Items & Extensions > Finder Extensions**.
4. Vo Finderi označ podporované súbory.
5. Vyber **Quick Actions > Sign with Autogram macOS**.

Quick Action neposiela PIN do skriptu a nepotrebuje Terminal. Starší samostatný CLI workflow je popísaný v [macOS CLI automation](docs/macos-cli-automation.md).

## Bezpečnosť a súkromie

- PIN existuje iba počas aktuálnej operácie.
- Helper dostane PIN cez štandardný vstup, nie cez argumenty alebo premenné prostredia.
- PIN ani prihlasovacie údaje TSA sa neukladajú v otvorenom texte.
- Diagnostika neobsahuje obsah dokumentov ani tajné údaje.
- Zdrojové dokumenty sa neprepisujú.
- Privátne kľúče zostávajú na karte.
- PKCS#11 knižnice sa pred použitím kontrolujú na arm64 kompatibilitu.

## Dokumentácia

- [Inštalácia natívnej aplikácie](docs/native-macos-installation.md)
- [Používateľský návod](docs/native-macos-user-guide.md)
- [Architektúra](docs/native-macos-architecture.md)
- [Release checklist](docs/native-macos-release-checklist.md)
- [Machine CLI protocol](docs/machine-cli-protocol-v1.md)
- [CLI a samostatný Finder Quick Action](docs/macos-cli-automation.md)
- [Portovanie z upstreamu](PORTING.md)

## Upstream a licencia

Fork zachováva Autogram a DSS ako kryptografickú autoritu. Natívna macOS vrstva je oddelená tak, aby sa všeobecne použiteľné zmeny dali ponúknuť upstream projektu [slovensko-digital/autogram](https://github.com/slovensko-digital/autogram).

Projekt je distribuovaný pod licenciou EUPL v1.2. Pôvodne vychádza z Octosign White Label od Jakuba Ďuraša, licencovaného pod MIT a distribuovaného so súhlasom autora.
