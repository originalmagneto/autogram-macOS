# Implementačný plán: ZaKo externé požiadavky a produkčný P -> E pilot

> Dátum: 28. 8. 2026 · Cieľ: uzavrieť rozdiel medzi aktuálnym lokálnym workflow a overiteľným P -> E produktom
>
> Plán nadväzuje na `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/docs/ZAKO_EXTERNAL_REQUIREMENTS_SPEC_2026-08-28.md`. Kód sa nemá meniť podľa pracovných podkladov, kým nie sú uzavreté rozhodnutia D1 až D5.

## Zásady realizácie

1. P -> E je jediný produkčný pilotný smer.
2. Pracovné podklady sú vstup na analýzu, nie automaticky autoritatívna schéma.
3. PDF/A-1a versus PDF/A-2b sa rieši dôkazom z formátovej matice a nezávislým validatorom, nie textovou náhradou.
4. Formuláre a EZZK sa integrujú cez versioned pack a protocol adapter.
5. AI iba navrhuje. Obsluha explicitne potvrdzuje úplnosť a každý bezpečnostný prvok.
6. Demo, mock a pilotný režim musia byť technicky aj vizuálne oddelené od produkcie.
7. Existujúce user changes sa počas realizácie neresetujú.

## Fáza 0: Autorita a interoperability discovery

### Cieľ

Uzavrieť D1 až D3 pred zmenou produkčného formátu, XML a EZZK transportu.

### Úlohy

- Vyžiadať od MIRRI aktuálnu maticu formátov pre P -> E, vrátane PDF/A-1a, PDF/A-2b a PNG.
- Získať aktuálny `recordVersion` a `clauseVersion`, namespace, XSD, XSLT, codelisty, effective date a acceptance pravidlá.
- Vyžiadať EZZK/OpenAPI alebo WSDL, sandbox endpoint, autentizáciu, request signature, error codes, idempotency a number lifecycle.
- Potvrdiť, či je 24-hodinová lehota viazaná na vytvorenie záznamu, pridelenie čísla alebo inú udalosť.
- Potvrdiť požiadavky na cudzie podpisy, certifikačný reťazec a časové pečiatky na vstupe.
- Spísať counsel-approved wording pre právne účinky, zodpovednosť obsluhy a status demo/pilotu.

### Výstupy

- schválený authority register s dôveryhodnosťou každého tvrdenia,
- format matrix,
- form-version matrix,
- EZZK protocol contract,
- rozhodnutie, či pilot môže pokračovať na PDF/A-2b alebo musí prejsť na PDF/A-1a/PNG.

### Exit gate

Bez týchto výstupov sa nemení `PDFAValidator`, codelist 53 ani produkčný EZZK provider.

## Fáza 1: Doménový model a versioned form packs

**Stav: implementované ako pilotná provenance vrstva; autoritatívne artefakty čakajú.**

### Cieľ

Odstrániť hardcoded predpoklady z generátora doložky a pipeline.

### Dotknuté súbory

- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Attestation/AttestationClauseGenerator.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Attestation/AttestationXMLValidator.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Attestation/ZakoCodelists.swift`
- nové `Autogram/Sources/AutogramKit/Attestation/FormPack.swift`
- nové `Autogram/Sources/AutogramKit/Attestation/FormPackRepository.swift`

### Úlohy

- Modelovať `ConversionFormPack` s oddelenou verziou záznamu a doložky.
- Uložiť namespace, XSD, XSLT, codelisty, effective interval, hash a acceptance flag.
- Vyberať pack podľa smeru, dátumu a potvrdenej kompatibility EZZK.
- Zachovať schopnosť overovať historické záznamy bez ich spätnej migrácie.
- Pridať fixture-based XML/XSD testy a test neplatného alebo expirovaného packu.

### Exit gate

Generátor nevie vyprodukovať XML bez explicitného form packu a validator vráti verziu packu v reportingu.

## Fáza 2: Výstupný formát a OCR pipeline

**Prerekvizita splnená čiastočne:** output-profile kontrakt je pripravený, skutočný PDF/A-1a
alebo PNG renderer čaká na autoritatívnu format matrix.

### Cieľ

Vyrobiť dôveryhodný výstup v profile schválenom vo fáze 0.

### Dotknuté súbory

- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/PDFA/PDFAConverter.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/PDFA/PDFAValidator.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/PDFA/ImageToPDFConverter.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/PDFA/EmbeddedFileService.swift`

### Úlohy

- Zaviesť explicitný `ConversionOutputProfile`, nie skrytý default PDF/A-2b.
- Ak je schválené PDF/A-1a, implementovať tagy, Unicode mapovanie, output intent, metadata a OCR/textovú vrstvu.
- Ak je povolený PNG, obmedziť ho na presne definovaný scenár a zapísať ho do doložky aj evidencie.
- Zachovať 200 až 300 DPI iba ako konfigurovateľný technický parameter, nie ako dôkaz konformity.
- Nahradiť heuristický validator nezávislým validatorom alebo ho označiť iba ako preflight pomocníka.
- Validovať finálny PDF po vložení XML a po podpise, nie iba intermediárne bytes.

### Testy

- vektorový PDF s textom a grafikou,
- rasterizovaný sken s OCR,
- zmiešané veľkosti strán,
- embedded XML s `/AF` a MIME contractom,
- negatívne testy šifrovania, JavaScriptu, chýbajúceho ICC, tagov a Unicode mapovania,
- nezávislý report pre každý podporovaný profil.

### Exit gate

Každý deklarovaný output profile prejde nezávislou kontrolou na reprezentatívnych fixture súboroch.

## Fáza 3: Input verification a bezpečnostné prvky

### Cieľ

Zmeniť AI návrhy na auditovateľný ľudský review proces.

### Dotknuté súbory

- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramApp/Views/AnalysisCanvasView.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/VisionAI/BuiltInVisionProvider.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Models/DomainModels.swift`
- nové `Autogram/Sources/AutogramKit/Signing/InputSignatureVerificationService.swift`

### Úlohy

- Zachovať a dokončiť detector regression work bez resetu aktuálnej zmeny v `BuiltInVisionProvider.swift`.
- Pridať stav návrhu, potvrdenia, zamietnutia a ručnej úpravy prvku.
- Vyžadovať potvrdenie každej neprázdnej strany vrátane explicitného "nič ďalšie nenájdené".
- Uložiť detector version, model/provider, reviewer identity, čas a override dôvod.
- Overiť cudzie PAdES/XAdES/CAdES podpisy a najstaršiu relevantnú časovú pečiatku pred konverziou.
- Pridať fixture testy pre podpis, pečiatku, reliéf, OCR text, QR, tabuľku a false positives.

### Exit gate

Autorizácia je zablokovaná, ak nie je dokončený ľudský review alebo ak input signature verification skončí v neznámom/neplatnom stave.

## Fáza 4: Mandátny podpis, QTS a artefaktový contract

### Cieľ

Preukázať, že podpisuje správna osoba správnym certifikátom a že časová pečiatka pokrýva správny objekt.

### Dotknuté súbory

- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Signing/SigningProvider.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Signing/XAdESSigner.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Signing/RFC3161TimestampClient.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Evidence/ASiCEVerifier.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramApp/ZakoSessionStore.swift`

### Úlohy

- Nahradiť heuristiku mandátu overeným certifikátovým profilom a OID, keď bude dodaný.
- Skontrolovať platnosť certifikátu, chain, revocation status a zhodu identity s doložkou.
- Overiť RFC 3161 response, TSA kvalifikáciu, `genTime` a vzťah ku konverznému času.
- Definovať, či podpisuje PDF, XML, ASiC-E alebo kombináciu, a rovnaký contract použiť v signerovi aj verifieri.
- Zakázať XAdES_ZEP a ponechať iba schválené baseline profily.

### Exit gate

Reálny test s podporovaným kartovým certifikátom vytvorí artefakt, ktorý prejde nezávislou kontrolou podpisu, certifikátu, QTS a ASiC-E.

## Fáza 5: EZZK gateway, čísla a deadline

### Cieľ

Nahradiť best-effort HTTP kostru produkčne overiteľným, idempotentným transportom.

### Dotknuté súbory

- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/EZZK/EZZKService.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramKit/Evidence/LocalEvidenceStore.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramApp/ZakoSessionStore.swift`
- `/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram/Sources/AutogramApp/Views/EvidenceDashboardView.swift`

### Úlohy

- Zaviesť `EZZKGateway` a oddeliť ho od JSON/SOAP transportu.
- Persistovať number request id, `issuedAt`, reservation/used/rejected state a server response.
- Persistovať zdroj serverového času a čas vytvorenia záznamu oddelene.
- Implementovať idempotentné submission a retry s rozlíšením transient/permanent rejection.
- Pridať warning pred expiráciou, presný countdown a explicitný overdue stav.
- Zakázať produkčné čísla v demo režime a zabrániť duplicite v race conditions.

### Exit gate

Sandbox test pokrýva pridelenie čísla, úspešné odoslanie, duplicitné odoslanie, timeout, odmietnutie a odoslanie tesne pred lehotou.

## Fáza 6: Evidencia, audit a release readiness

### Cieľ

Zachovať všetky dôkazy o rozhodnutiach a vytvoriť opakovateľný release report.

### Úlohy

- Rozšíriť `EvidenceRecord` o form pack, output profile, verification report refs, number lifecycle a review audit.
- Rozhodnúť, či JSON register zostane MVP storage alebo sa migruje na SQLite/Core Data.
- Vytvoriť export overovacieho balíka: PDF, XML/XDCF, ASiC-E, hash report, signature report, EZZK response a audit.
- Pridať release checklist a automatický compliance report bez tvrdenia o právnej záväznosti.
- Spustiť manuálny macOS 27 pass s VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency a rôznymi oknami.

### Exit gate

Každá konverzia je spätne vysledovateľná od vstupu po CEZZK response a pilot je označený správnym statusom.

## Fáza 7: V2 capability modules

Po samostatnom requirements review možno pridať:

- E -> P,
- E -> E,
- batch konverziu,
- scanner/ImageCapture bridge,
- CEZZK query/verification client,
- fakturačný export,
- LTA archiváciu,
- certifikované alebo externe posúdené AI automation.

Tieto schopnosti nemajú rozširovať MVP release gate bez vlastných formátových, právnych a integračných testov.

## Odporúčané testovacie ciele

```text
Autogram/Tests/AutogramKitTests/FormPackTests.swift
Autogram/Tests/AutogramKitTests/PDFAProfileTests.swift
Autogram/Tests/AutogramKitTests/InputSignatureVerificationTests.swift
Autogram/Tests/AutogramKitTests/ConversionPipelineIntegrationTests.swift
Autogram/Tests/AutogramKitTests/EZZKGatewayTests.swift
Autogram/Tests/AutogramKitTests/EvidenceAuditTests.swift
```

Každý test musí rozlišovať:

- deterministickú unit logiku,
- offline integration test s fake providerom,
- sandbox test,
- manuálne alebo externé conformance overenie.

## Verifikácia po implementácii

```bash
cd "/Users/Magneto/PROJECTS/AUTOGRAM macOS UI/Autogram"
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer ./build_app.sh
```

Okrem testov musí byť priložený externý PDF/A report, XML/XSD report, signature/QTS report a EZZK sandbox response. Zelený lokálny test sám osebe neznamená produkčnú konformitu.