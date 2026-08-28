# Autogram macOS - Implementačná dokumentácia fáz 1–4

> Stav: august 2026 · 107 vykonaných testov · 3 skipped · 0 failures · Swift 6 strict concurrency · 0 Swift package dependencies

Tento dokument popisuje, čo presne implementujú jednotlivé fázy modulu Zaručená konverzia
(ZaKo) a štandardného podpisovania, aké rozhodnutia boli prijaté a kde sú limity.

---

## Fáza 1 - Výstupná pipeline podľa špecifikácie

### XML doložka (ConversionRecord 1.0)
- Namespace: `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`
  (stará schéma `ConversionCertificate…/1.2` zo vzorových ASiC-E súborov je podľa § 4.1 špecu neplatná)
- Poradie elementov presne podľa skeletonu v `AUTOGRAM_ZAKO_MODULE_SPEC.md` § 4.2:
  `OriginalDocumentInfo → NewDocumentInfo → PersonPerformingConversion → UsedDevice → ConversionExecutionDateTime → ConversionRecordEvidenceNumber`
- **Codelisty** cez mechanizmus `codelistCode + codelistItem[itemCode, itemName@Language=sk]`:

| Codelist | Význam | Hodnoty v appke |
|---|---|---|
| 12 | formát papiera | A4 / A3 / Letter |
| 11 | umiestnenie prvku | Down, Down edge, Left down, Right down, Left up, Right up, Up, Center, Left, Right |
| 14 | metóda otlačku | SHA-256 |
| 15 | druh prvku | vlastnoručný podpis, okrúhla pečiatka so štátnym znakom, reliéfna pečiatka, parafa, iný prvok |
| 53 | formát nového dokumentu | PDFA2 |
| 4001 (item 7) | typ identifikátora | IČO |

- Identifikátor osoby ako IDCType: `ico://sk/{IČO}`
- Evidenčné číslo vo forme URI: `https://data.gov.sk/id/egov/conversion-record/{číslo}`
- Otlačok: **base64(SHA-256)** intermediárneho PDF/A pred vložením EmbeddedFile + metóda codelist 14
- Každý bezpečnostný prvok: slovný opis + strana + list (duplex počítadlo `(strana+1)/2`) +
  lokalita codelist 11 + nová strana
- `ConversionExecutionDateTime` s lokálnym UTC offsetom (`+02:00`), nie Z-formou

### Poradie pipeline (kľúčová oprava)
```
PDF/A konverzia → SHA-256 (fingerprint) → XML doložka →
EmbeddedFile do PDF → finálna normalizácia a validácia → ASiC-E balenie →
podpis → lokálna evidencia → CEZZK fronta
```
Fingerprint sa počíta nad čistým konvertovaným dokumentom (doložka je „spojená“ cez
EmbeddedFile + samostatný `.xml.xdcf`, nemení teda obsah otlačku).

Tlačiteľná strana doložky sa do konvertovaného PDF nevkladá (vizuálna reprezentácia je
samostatné tlačivo, § 5.5 špecu). `ClausePDFRenderer` zostáva v kit-e pre budúci preview/tlač.

### ASiC-E kontajner
```
mimetype                       application/vnd.etsi.asic-e+zip (prvý, stored)
{dokument}.pdf                 PDF/A-2b s EmbeddedFile doložkou
{evidenčné číslo}.xml.xdcf     samostatná doložka
META-INF/manifest.xml          OASIS manifest 1.2 ("/" + dáta)
META-INF/signatures001.xml     XAdES-B/T nad všetkými dátovými objektmi
```

### Evidenčné čísla
Mock EZZK generuje reálny formát `{registry}-{YYMMDD}-{seq}` (default registry `1563`).
Produkčné čísla prichádzajú z IS EZZK ešte pred vytvorením záznamu (§ 38 zákona).

---

## Fáza 2 - Časové pečiatky a PDF/A v štandardnom režime

### RFC 3161 klient (`RFC3161TimestampClient`)
- Vlastná DER enkódkia TimeStampReq (SHA-256 messageImprint, nonce, certReq) -
  golden vektor testovaný bajt-po-bajte
- Parser odpovede: PKIStatusInfo (granted/grantedWithMods), extrakcia ContentInfo tokenu
  a `genTime` z TSTInfo (GeneralizedTime aj UTCTime)
- Injektovateľný transport (`LLMTransport`) → testy bežia offline

### TSA servery
Built-in zoznam zrkadlí originálnu aplikáciu Autogram + slovenskú realitu:
1. **CA Disig (SK)** - `http://tsa.disig.sk/qts` *(default)*
2. **Sectigo Qualified** - `http://timestamp.sectigo.com/qualified`
3. **Belgian Federal Government TSA** - `http://tsa.belgium.be/connect`

Vlastné servery je možné pridávať v Nastaveniach; tlačidlo *Otestovať spojenie* pošle
skutočnú RFC 3161 žiadosť. Migrácia starej jedinej `tsaURL` prebieha automaticky pri načítaní.

### PDF/A pred podpisom
Toggle *Konvertovať do PDF/A pred podpisom* v štandardnom režime; režim konverzie
(vektorový / raster 200 dpi) sa berie z Nastavenia › Konverzia PDF/A.

---

## Fáza 3 - SAK karta end-to-end

### Reálne KEP podpisy
Dva natívne podpisové enginy nad `SecIdentity` (Keychain / CryptoTokenKit karty):

| Engine | Výstup | Použitie |
|---|---|---|
| `KeychainXAdESSigningProvider` → XAdES-B/T | ASiC-E kontajner | ZaKo (default), štandardný režim |
| ten istý provider → PAdES-B/T (`PAdESSigner`) | podpísané PDF (inkrementálna revízia) | voliteľný formát v štandardnom režime |

**XAdES**: exc-c14n-kompatibilná serializácia (namespaces deklarované lokálne na
podpisovaných fragmentoch), SHA-256 digesty dát + SignedProperties, SigningCertificate
(SHA-512 cert digest + IssuerSerial), SigningTime, voliteľný SignatureTimeStamp
(RFC 3161 token ako EncapsulatedTimeStamp).

**PAdES**: CMS SignedData (detached) so signed attrs (contentType, messageDigest,
signingTime, signingCertificateV2) + unsigned attr time-stamp token; ByteRange pokrýva
celý súbor okrem rezervovaného `/Contents`; inkrementálna revízia s AcroForm/SigField.
Test overuje, že `messageDigest` v CMS == SHA-256 nad rozsahmi ByteRange.

**X.509 parser** (`X509Inspector`): sériové číslo (ľubovoľná dĺžka → desiatkové),
issuer/subject → RFC 2253 (vrátane hex-formy pre neznáme typy a escapingu).

### Mandátna brána (ZaKo)
- Checklist riadok *Mandátny certifikát SAK* - vyžaduje `isMandateCertificate &&
  isQualified && hasPrivateKey`
- Autorizácia bez mandátu je zablokovaná; pokračovanie len výslovným override toggle-om
  (varovanie, že CEZZK zápis môže byť zamietnutý) - edge case podľa špecu § 9
- Auto-výber identity preferuje mandátny certifikát

### Live detekcia karty
`CardPresenceMonitor` (TKTokenWatcher + KVO na `tokenIDs`) - vloženie/vytiahnutie karty
okamžite refreshuje zoznam certifikátov v autorizačnom kroku.

### eID / CryptoTokenKit
Slovenská eID (Cosmo 9.2, `eID_klient` 5.4) neexportuje `kSecClassIdentity` spoľahlivo
a hromadný `SecItemCopyMatching` s `kSecReturnRef` na všetky certifikáty **visí**.
Scanner preto:
1. zoberie `TKTokenWatcher.tokenIDs` (mimo Apple tokenov),
2. na každom tokene načíta certifikáty cez `kSecReturnData` a privátny kľúč cez
   `kSecReturnRef` filtrovaný `kSecAttrTokenID`,
3. spáruje ich podľa verejného kľúča.

PIN zadáva CryptoTokenKit / eID_klient vo vlastnom dialógu (`SecKeyCreateSignature`).
PKCS#11 (`libPkcs11.dylib`, OpenSC, AWP) ostáva fallback, ak token SecKey nevráti.
Oficiálny PKCS#11 modul eID klienta aktuálne hlási 0 slotov; AWP je iba x86_64.

### Výber providera
`SigningProviderFactory.makeDefault()`: ak existuje identita s privátnym kľúčom →
reálny provider (výstup označený ako právne záväzný), inak DEMO podpisovač
(jasne označený, nikdy `isLegallyBinding = true`).

---

## Fáza 4 - Validácie a EZK dashboard

### Validačné vrstvy (hard gates pred/po autorizácii)

| Validátor | Čo kontroluje |
|---|---|
| `PDFAValidator` | %PDF hlavička, %%EOF, startxref, XMP pdfaid part/conformance, GTS_PDFA OutputIntent + ICC profil, absencia šifrovania a JavaScriptu |
| `AttestationXMLValidator` | štruktúra ConversionRecord 1.0, povinné polia neprázdne, sheets ≥ 1, fingerprint == base64(SHA-256), evidenčné číslo ako URI, ISO8601 čas, počet prvkov == vstup, PhysicalPerson/LegalSubject |
| `ASiCEContainerVerifier` | mimetype prvý + hodnota, manifest "/" + úplnosť, **recompute SHA-256 každého dátového objektu proti ds:Reference DigestValue**, prítomnosť XAdES signed-properties referencie, demo flag |

Všetky tri bežajú automaticky v `ZakoSessionStore.authorizeAndSign()`; zlyhanie =
`ComplianceValidationError` so zoznamom problémov, konverzia sa nedokončí.

### Dashboard evidencie
- Summary karty: celkovo / zapísaných v CEZZK / čakajúcich / **po lehote 24 h**
- Červený indikátor a textový stav pre záznamy po lehote + stĺpec „Lehota CEZZK"
- Filtre podľa stavu + fulltext
- Detail: status timeline (číslo → KEP → CEZZK), kopírovanie URI a SHA-256,
  náhľad XML doložky, zmazanie záznamu
- Hromadné odosielanie čakajúcich záznamov do IS EZZK s aktualizáciou stavov;
  minútový refresh lehôt

---

## Obmedzenia a ďalšie kroky

| Oblasť | Stav | Poznámka |
|---|---|---|
| EZZK API | Mock + HTTP kostra | oficiálna OpenAPI od MIRRI nie je publikovaná (špec § 11.1); endpointy `portal/api/*` sú best-effort |
| Cert chain v XAdES | len podpisový cert | chain/LTA (B-LT archivácia) je V2 |
| veraPDF | nahradené vlastným `PDFAValidator` | štrukturálna validácia; plná schémová validácia ostáva voliteľná via bundled CLI |
| eID PKCS#11 | natívny SecKey funguje | oficiálny `libPkcs11.dylib` má 0 slotov; pri uviaznutom CTK reštartovať eID_klient |
| Mandát atribút | heuristika CN/issuer strings | presný OID mandátu doplniť po analýze reálneho SAK certifikátu |
| Formuláre 1.2 (2027) | verziované konštanty v `ZakoCodelists` | auto-update artefaktov z formulare.slovensko.sk (FormularyRepository) |
| XAdES_ZEP | netvorí sa | zakázaný podľa eIDAS IR 2015/1506 |

## Právna kotva
- Zákon č. 305/2013 Z. z., § 35–39
- Vyhláška MIRRI č. 70/2021 Z. z. (+ formulár 50349287 verzia 1.0 záznamu P→E)
- eIDAS 910/2014 + IR 2015/1506 (PAdES/XAdES/CAdES v ASiC; ZEP zakázaný)
