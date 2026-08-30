# ZaKo Production Readiness Plan Review

## Verdict

APPROVE WITH CHANGES

## Executive Finding

Pôvodný verdikt pred opravou plánu bol REJECT. Pôvodný plán obsahoval kritické chyby v authority gate, poradí podpisovania a package validácie, produkčnej izolácii transportov, modelovaní dvoch 24-hodinových pravidiel, kryptografických reportoch a oddelení pipeline stages.

Primárny plán bol opravený. Finálny verdikt je APPROVE WITH CHANGES, pretože plán je po oprave implementačne konzistentný, ale produkčná implementácia zostáva zablokovaná, kým nebudú dodané a overené autoritatívne P2E artefakty, schválené nezávislé validátory a reálny EZZK sandbox a produkčný kontrakt. Tento verdikt nie je potvrdením právnej, technickej ani EZZK konformity produktu.

Použité boli iba lokálne súbory uvedené v zadaní a lokálna implementácia. Internet nebol použitý. Dodané pracovné špecifikácie zostávajú pracovnými požiadavkami, nie autoritatívnym dôkazom.

## Requirement Coverage Matrix

| Requirement | Source | Plan task | Evidence or acceptance gate | Status |
|---|---|---|---|---|
| P2E je jediný produkčný smer | Manuál, súhrn 1 až 5; externá špecifikácia 2 | Global Constraints; Phase 0 exit gate; Separate Post-Production Scope | Counsel a product owner schvália P2E scope; E2P a E2E majú samostatné gates | covered |
| PDF/A-1a je bezpečný produkčný default | PDF/A podklad 1, riadky 1 až 10; PDF/A podklad 2, riadky 1 až 22; Manuál, riadky 24 až 32 | Task 0.1; Task 2.1; Task 2.2; Phase 7 | Authority matrix, exact codelist, independent report viazaný na finálny hash | blocked by external authority |
| Aplikácia musí vytvoriť požadovaný profil aj zo skenera, ktorý ho priamo nevytvára | PDF/A podklad 1, riadok 6 | Task 2.1; Task 2.2 | Vektorové, rastrové, OCR a mixed-content fixtures; independent conformance | partially covered |
| Tagged PDF pre PDF/A-1a | PDF/A podklad 2, riadky 5 až 8 | Task 2.1; Task 2.2 | Negatívny fixture bez požadovanej štruktúry musí zlyhať v schválenom nezávislom validátore | blocked by external authority |
| Unicode mapping pre PDF/A-1a | PDF/A podklad 2, riadky 5 až 8 | Task 2.1; Task 2.2 | Negatívny Unicode fixture a report viazaný na exact output hash | blocked by external authority |
| OCR a kombinácia textovej a grafickej vrstvy | PDF/A podklad 2, riadky 10 až 13; Manuál, riadok 32 | Task 0.1; Task 2.1; Task 2.2 | OCR pravidlo je authority-controlled; raster, vector a mixed fixtures | blocked by external authority |
| Skenovanie 200 až 300 DPI | Manuál, riadok 32 | Task 0.1; Task 2.1 | DPI sa eviduje ako authority-controlled raster policy, nie conformance proof | blocked by external authority |
| Bezstratová kompresia | Manuál, riadok 32 | Task 0.1; Task 2.1 | Presné compression pravidlo a fixture podľa authority matrix | blocked by external authority |
| PNG iba v presne povolenom obmedzenom prípade | PDF/A podklad 2, riadky 1 až 2 a 17 až 20; Manuál, riadok 29 | Task 0.1; Task 2.1; Task 2.2 | Page-count, graphic-only, MIME, packaging, signing a warning gates | blocked by external authority |
| Iný formát vyžaduje predchádzajúce výslovné upozornenie | PDF/A podklad 1, riadky 8 až 10; PDF/A podklad 2, riadky 17 až 22 | Global Constraints; Task 0.1; Task 2.1; Task 4.3; Task 6.1; Task 6.2 | Counsel-approved text ID a hash, applicant acknowledgement, operator a čas pred konverziou | blocked by external authority |
| Exact output format code v doložke a evidencii | PDF/A podklad 1, riadok 5; PDF/A podklad 2, riadok 13 | Task 0.1; Task 1.3 | Code aj codelist artifact hash musia byť zhodné v outpute, record XML, clause XML a audite | blocked by external authority |
| Formuláre sa generujú ako presné XML | Manuál, riadky 3 až 7 | Task 1.1; Task 1.2; Task 1.3 | Official record a clause XSD validation; wrong namespace a wrong version tests | blocked by external authority |
| Formuláre sa vizualizujú štátnou šablónou | Manuál, riadok 5 | Task 1.1; Task 1.2 | Samostatný record a clause XSLT role; source, stylesheet a render hashes | blocked by external authority |
| Aktuálne a budúce record verzie sa nesmú zlúčiť do jednej verzie | Manuál, riadky 8 až 17 | Task 0.1; Task 1.1 | Oddelené recordVersion, effective interval a EZZK acceptance interval | blocked by external authority |
| Aktuálne a historické clause verzie musia zostať overiteľné | Manuál, riadky 19 až 22 | Task 0.1; Task 1.1; Task 7.1 | Historical pack iba cez validationPack(id:), nikdy pre novú produkčnú generáciu | blocked by external authority |
| Oficiálne XSD | Manuál, riadky 3 až 22; existujúci kontext | Task 0.1; Task 1.1; Task 1.2 | Exact bytes, hash, role, effective interval a approved validator | blocked by external authority |
| Oficiálne XSLT | Manuál, riadok 5; existujúci kontext | Task 0.1; Task 1.1; Task 1.2 | Exact bytes, hash, role a rendered output hash | blocked by external authority |
| Oficiálne codelisty | Manuál, formulárové požiadavky; existujúci kontext | Task 0.1; Task 1.1; Task 1.3 | Codelist artifact hash a exact effective value, bez hardcoded náhrady | blocked by external authority |
| Namespace, eForm identifier a účinnosť verzií | Manuál, riadky 3 až 22 | Task 0.1; Task 1.1; Task 1.2 | Verified authority rows, effective intervals, historical fixtures | blocked by external authority |
| XMLDataContainer zostáva E2P požiadavkou, nie P2E implementáciou | Manuál, riadok 30 | Task 0.1; Separate Post-Production Scope: E2P | Samostatný budúci E2P authority, format, signature, EZZK a conformance gate | covered |
| Output dokument, doložka a EZZK record musia mať potvrdený autorizačný contract | Manuál, riadky 34 až 40 a 47 až 48 | Task 0.1; Task 3.3; Task 3.4; Task 5.1; Task 6.1 | Exact signed objects a ich resolved digests v signature, package a EZZK evidence | blocked by external authority |
| Mandátny certifikát advokáta | Manuál, riadok 38 | Task 0.1; Task 3.2 | Authority policy ID, mandate OIDs, exact used certificate fingerprint | blocked by external authority |
| Kvalifikovaný status certifikátu | Manuál, riadok 38 | Task 3.2 | Qualified status conclusion, chain, revocation a private-key proof | blocked by external authority |
| Certifikačný reťazec | Manuál, podpisová časť; existujúci kontext | Task 3.1; Task 3.2; Task 3.4 | Independent chain conclusion pre input aj output | blocked by external authority |
| Revokácia | Manuál, podpisová časť; existujúci kontext | Task 3.1; Task 3.2; Task 3.3; Task 3.4 | good, revoked, indeterminate a notChecked sú oddelené stavy | blocked by external authority |
| PAdES input validation | Zadanie review; existujúci kontext | Task 0.1; Task 3.1; Task 7.1 | Valid, invalid, revoked, indeterminate, wrong-object a malformed fixtures | blocked by external authority |
| XAdES input validation | Manuál, riadky 39 až 40; zadanie review | Task 0.1; Task 3.1; Task 7.1 | Exact signature value, objects, chain, revocation, qualification a timestamp | blocked by external authority |
| CAdES input validation | Zadanie review; existujúci kontext | Task 0.1; Task 3.1; Task 7.1 | Rovnaký independent validation contract ako PAdES a XAdES | blocked by external authority |
| ASiC alebo ASiC-E package nesmie byť predpokladaný bez exact profilu | Manuál, riadok 39; aktuálna implementácia ASiC-E | Task 0.1; Task 3.4 | Authority-backed package profile, MIME, signed objects a independent package report | blocked by external authority |
| XAdES output authorization nesmie byť zamieňaná s input validation | Manuál, riadok 39 | Global Constraints; Task 0.1; Task 3.1; Task 3.4 | Oddelený input report a output package report | blocked by external authority |
| QTS je povinná pre produkčnú autorizáciu | Manuál, riadky 36 až 40 | Task 0.1; Task 3.3; Task 6.1 | Missing, malformed, unqualified, revoked, indeterminate a unavailable token blokuje flow | blocked by external authority |
| Timestamp token sa validuje kryptograficky | Manuál, riadok 40 | Task 3.1; Task 3.3; Task 3.4 | CMS, imprint, policy, chain, revocation, qualification, genTime a token hash | blocked by external authority |
| Timestamp musí pokrývať exact signed object | Manuál, riadky 36 až 40 | Task 0.1; Task 3.1; Task 3.3; Task 3.4 | SignedObjectReference a coveredObject musia zodpovedať exact artifact hash | blocked by external authority |
| Vstupné cudzie podpisy sa overia pred konverziou | Manuál, riadok 40 a súhrn bod 5 | Task 3.1; Task 4.2; Task 6.1 | Inspection completed je oddelené od unavailable; fail-closed gate | blocked by external authority |
| Najstaršia relevantná kvalifikovaná časová pečiatka v doložke a audite | Manuál, riadok 40 | Task 3.1; Task 4.2; Task 4.1 | Najstarší valid qualified token nad relevantným objectom, nikdy signingTime | partially covered |
| Unsigned input je odlíšený od zlyhaného inspectora | Impl. InputSignatureVerificationService; zadanie review | Global Constraints; Task 3.1 | inspectionCompleted plus noSignaturesPresent; policy-driven outcome | covered |
| Evidenčné číslo sa získa v exact contract point pred konverziou | Manuál, riadok 47 | Task 0.1; Task 5.1; Task 5.2; Task 6.1 | Real sandbox allocation response a atomic session binding | blocked by external authority |
| Platnosť evidenčného čísla 24 hodín | Manuál, riadok 47 | Task 0.1; Task 5.2 | Samostatný number-validity anchor, expiresAt, warning a terminal state | blocked by external authority |
| Submission lehota 24 hodín od vytvorenia recordu | Manuál, riadok 48 | Task 0.1; Task 5.2 | Samostatný submission-window anchor, dueAt, warning a overdue state | blocked by external authority |
| Signed XML record sa odosiela do EZZK | Manuál, riadok 48 | Task 0.1; Task 3.4; Task 5.1; Task 6.1 | Exact signedRecord bytes, SHA-256, SignedObjectReference a sandbox receipt | blocked by external authority |
| EZZK odmietnutie zlej schémy alebo QTS | Manuál, riadok 48 | Task 5.1; Task 5.3; Task 7.1 | Contract-defined permanent, retryable alebo indeterminate disposition | blocked by external authority |
| EZZK autentifikácia | Manuál, riadky 49 až 55 | Task 0.1; Task 5.1; Task 7.3 | Verified auth contract, provider capability, config hash a redacted sandbox evidence | blocked by external authority |
| EZZK transport request signature | Zadanie review; existujúci kontext | Task 0.1; Task 5.1 | Exact request bytes, signature report a sandbox verification | blocked by external authority |
| EZZK signed business object je oddelený od transport signature | Zadanie review; existujúci kontext | Task 0.1; Task 5.1; Task 6.1 | Separate transport signing, object signing a exact-object hashes | blocked by external authority |
| EZZK sandbox | Manuál, riadok 51 | Task 0.1; Task 5.1; Task 5.3; Task 7.1; Task 7.2 | Real allocation a submission captures, nie iba offline fixture | blocked by external authority |
| EZZK production endpoint a registrácia | Manuál, riadky 50 až 55 | Task 0.1; Task 5.1; Task 7.3 | Registration contract, endpoint authority ID, credentials a production capability | blocked by external authority |
| EZZK idempotency a duplicate reconciliation | Zadanie review; existujúci kontext | Task 0.1; Task 5.3; Task 7.1 | Contract-defined key alebo reconciliation a real sandbox duplicate proof | blocked by external authority |
| Retry iba pri contract-confirmed bezpečnosti | Zadanie review; existujúci kontext | Task 0.1; Task 5.3 | Bounded retry len po proof, že nevznikne duplicitný record | blocked by external authority |
| Permanent rejection a indeterminate outcome sú oddelené | Zadanie review | Task 5.1; Task 5.3; Task 6.2 | Typed disposition, terminal state, next action a no local promotion | covered |
| Demo, pilot, sandbox a production sú odlišné | Zadanie review; externá špecifikácia D5 | Task 0.2; Task 6.2; Task 7.2 | Typed mode aj provider capability; oddelené endpoints, credentials, UI a evidence | covered |
| Mock a pilot service sa nedostanú do produkcie | Zadanie review; externá špecifikácia D5 | Task 0.2; Task 5.1; Task 7.2 | Produkcia odmietne mock, demo, pilot, sandbox a non-submitting capability | covered |
| Originál alebo úradne osvedčená kópia sa audituje | Externá špecifikácia 2 a normatívna matica | Task 4.3; Task 6.1 | Counsel text, operator identity a timestamp | covered |
| Počet strán, neprázdnych strán, listov a sheet method | Externá špecifikácia, normatívna matica | Task 4.3; Task 6.1 | Oddelené values a invalidation po zmene | covered |
| Paper size per page a mixed sizes | Externá špecifikácia, normatívna matica | Task 4.3; Task 7.1 | Unknown blocks, mixed-size fixture | covered |
| Každá neprázdna strana a každý security element majú human decision | Externá špecifikácia D4 | Task 4.3; Task 6.1 | Stale, incomplete a AI-only review blokuje flow | covered |
| Lokálny marker validator je iba preflight | Zadanie review; externá špecifikácia | Global Constraints; Task 1.2; Task 2.2; Task 3.4; Task 7.2 | Evidence kind localPreflight sa nesmie použiť ako independentConformance | covered |
| Audit je immutable a hash-linked | Zadanie review; externá špecifikácia | Task 0.3; Task 4.1 | Stage inputs, outputs, reports a times v append-only events | covered |
| Evidence export je oddelený od validácie a právneho approval | Zadanie review | Task 6.3 | Export integrity test a výslovný zákaz conformance claim | covered |
| Generovanie, validácia, podpis, timestamp, EZZK, audit a export sú oddelené | Zadanie review | Task 4.1; Task 6.1; Phase 6 exit gate | Typed stages, immutable hash handoffs, skip/reorder/stale negative tests | covered |
| E2P a E2E zostávajú samostatné budúce projekty | Zadanie review | Separate Post-Production Scope | Samostatné authority, form, signature, EZZK, audit a conformance gates | covered |

## Critical Findings

### C1: Authority gate umožňoval pokračovať po vytvorení prázdnych dokumentov

- severity: Critical
- presný plán alebo zdroj: Pôvodný Task 0.1 acceptance a pôvodný Phase 0 exit gate; externá špecifikácia, hierarchia dôvery a D1 až D3.
- problém: Pôvodný exit gate vyžadoval, aby authority register a contract dokumenty existovali, ale nevyžadoval, aby všetky spotrebované authority rows boli verified. Task 1.1 potom požadoval authoritative fixtures aj pri chýbajúcich bytes.
- dopad: Implementátor mohol pokračovať s pracovnou špecifikáciou, lokálnym fixture alebo guessed contractom a neskôr ho označiť ako accepted.
- konkrétna oprava plánu: Global Constraints a Task 0.1 teraz používajú explicitný `blocked` stav. Každý consumer task má prerequisites na verified authority rows. Phase 0 a Phase 7 zakazujú pokračovanie pri blocked, unverified, expired alebo missing rows.

### C2: Produkčný dry-run transport porušoval izoláciu produkcie

- severity: Critical
- presný plán alebo zdroj: Pôvodný Task 7.2 krok s production mode a non-submitting dry-run transportom; pôvodný Task 0.2 acceptance.
- problém: Produkčný mode mal byť testovaný s transportom, ktorý podľa vlastných pravidiel nesmel spĺňať production capability.
- dopad: Rovnaký injection point mohol vpustiť mock alebo non-submitting provider do reálneho produkčného flow.
- konkrétna oprava plánu: Task 0.2 zavádza oddelený runtime mode a provider capability. Task 7.2 teraz dokazuje, že produkcia všetky test, mock, pilot, sandbox a non-submitting providers odmietne. Povolený je iba contract-defined non-submitting readiness operation mimo conversion flow.

### C3: Final package validation bola naplánovaná pred signing a QTS

- severity: Critical
- presný plán alebo zdroj: Pôvodný Task 2.3 pred Phase 3 signing tasks; pôvodný Phase 2 exit gate.
- problém: Task mal kryptograficky validovať final ASiC-E signature, certifikát a timestamp ešte pred implementáciou mandate policy, output signing a QTS.
- dopad: Nesplniteľná dependency alebo marker-only validator vydávaný za final cryptographic proof.
- konkrétna oprava plánu: Package task bol presunutý logicky za input validation, mandate certificate a QTS ako Task 3.4. Má prerequisites na exact package profile, output report, certificate report a QTS report.

### C4: Dve 24-hodinové tvrdenia boli zlúčené do jedného lifecycle

- severity: Critical
- presný plán alebo zdroj: Manuál riadky 47 a 48; pôvodný Task 5.2; pôvodný `EvidenceRecord.submissionDeadline` v `LocalEvidenceStore.swift`.
- problém: Platnosť evidenčného čísla a lehota na submission recordu mali jeden neurčitý anchor.
- dopad: Aplikácia mohla odoslať po lehote, predčasne expirovať číslo alebo chybne retryovať.
- konkrétna oprava plánu: Task 0.1, Task 4.1 a Task 5.2 modelujú number validity a submission deadline ako dve samostatné authority rules, anchors, times, warnings a terminal states. Lokálny `Date()` fallback je zakázaný.

### C5: Kryptografické reporty nepreukazovali exact signed object ani trust stav

- severity: Critical
- presný plán alebo zdroj: Pôvodné `SignatureValidationReport`, `ValidatedSignature`, `CertificateValidationReport` a `QualifiedTimestampReport` v Tasks 3.1 až 3.3.
- problém: Formát bol `String`, trust a qualification boli booleans, report nemal resolved signed-object digest, revocation conclusion ani validovaný timestamp token. `genTime` a TSA fingerprint boli non-optional aj pre malformed token.
- dopad: Report mohol označiť podpis alebo timestamp za valid bez dôkazu, že podpisoval exact artifact, bez chain a revocation proof alebo s neparsovateľným tokenom.
- konkrétna oprava plánu: Task 3.1 zavádza `ValidationConclusion`, `SignatureFormat`, `RevocationStatus`, `SignedObjectReference`, `ValidatedTimestamp` a podrobný `SignatureValidationReport`. Tasks 3.2 až 3.4 používajú rovnaké conclusions, exact hashes a independent validator identity.

### C6: Pipeline nemala enforceable stage contract

- severity: Critical
- presný plán alebo zdroj: Pôvodný Task 6.1 a pôvodný `ZaKoProductionPreflight`.
- problém: Jeden preflight miešal pre-generation, post-generation, signing, QTS a EZZK gates. Neexistoval typed transition contract ani ochrana pred reuse stale bytes medzi stages.
- dopad: Podpísaný alebo odoslaný mohol byť iný artifact než ten, ktorý prešiel XML, PDF/A, signature alebo timestamp validáciou.
- konkrétna oprava plánu: Task 4.1 definuje `ZaKoProductionStage` a immutable audit events. Task 6.1 definuje exact order, hash handoffs a negative skip, reorder, repeat a stale-result tests.

## Important Findings

### I1: Demo bolo v globálnych pravidlách, ale chýbalo v runtime enum

- severity: Important
- presný plán alebo zdroj: Pôvodné Global Constraints a pôvodný Task 0.2 `ZaKoRuntimeMode`.
- problém: Plán požadoval štyri odlišné režimy, enum mal iba pilot, sandbox a production.
- dopad: Demo signer a mock provider nemali jednoznačný policy boundary.
- konkrétna oprava plánu: Task 0.2 teraz definuje demo, pilot, sandbox a production plus samostatný `EZZKProviderCapability`.

### I2: Plánovaný form pack zahadzoval existujúce production-eligibility fields

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 1.1 interface; `FormPack.swift` existujúce `manifestVersion`, `verificationState`, `renderer`, codelist mappings a `isProductionEligible`.
- problém: Nový snippet tieto fields vynechal, hoci globálne pravidlá zakazovali `unverified` a `legacySwift`.
- dopad: Kód nemal typový spôsob vykonať deklarovaný zákaz.
- konkrétna oprava plánu: Task 1.1 zachováva a migruje všetky fields, rozširuje acceptance na unknown, pilotOnly, sandboxAccepted, productionAccepted a rejected a vyžaduje explicitný migration všetkých callers.

### I3: Output profile nemal authority, notice ani external evidence identity

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 2.1 `ConversionOutputProfile`.
- problém: Generic `AcceptanceState` neobsahoval authority record, independent report identity, DPI, compression, page count, graphic-only ani warning policy.
- dopad: Lokálny flag mohol urobiť profil productionAccepted.
- konkrétna oprava plánu: Task 2.1 pridáva authorityRecordID, externalConformanceEvidenceID, exact raster a PNG constraints, `ApplicantNoticePolicy` a clean cutover zo starej `VerificationState`.

### I4: Alternative-format warning bol iba UI krok

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 6.2; oba PDF/A pracovné podklady.
- problém: Warning nebol domain precondition ani audit evidence a nebolo určené, že musí vzniknúť pred konverziou.
- dopad: Conversion sa mohla vykonať bez právne relevantného upozornenia a neskorší UI checkbox by nedostatok zakryl.
- konkrétna oprava plánu: Global Constraints, Task 2.1, Task 4.3 a Task 6.1 z warningu robia pre-conversion domain gate s exact text hash, acknowledgement, operatorom a časom.

### I5: Official rendering pokrýval iba clause

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 1.2 `OfficialFormRendering`; Manuál riadky 3 až 22.
- problém: Interface mal iba `renderClause`, hoci plán evidoval record aj clause XSLT.
- dopad: Record visualization mohla zostať na lokálnom rendererovi bez exact official stylesheet provenance.
- konkrétna oprava plánu: Task 1.2 má samostatné record a clause schema aj stylesheet roles a `renderRecord` aj `renderClause` s hashmi.

### I6: Source origin, physical sheets, paper sizes a warning audit neboli v production preflight

- severity: Important
- presný plán alebo zdroj: Externá špecifikácia, normatívna matica; pôvodný Task 4.3 a Task 6.1.
- problém: Plán chránil security-element review, ale nie všetky operator facts a document-analysis decisions.
- dopad: Produkčný record mohol obsahovať neoverené počty listov, unknown formát alebo neauditovaný pôvod vstupu.
- konkrétna oprava plánu: Task 4.3 a Task 6.1 pridávajú exact operator confirmations, separate page a sheet values, paper-size decision per non-empty page a stale-review invalidation.

### I7: Unsigned input nebol odlíšený od nedostupného validátora

- severity: Important
- presný plán alebo zdroj: Pôvodný Global Constraint 18; pôvodný Task 3.1 no-signature test bez expected state; `InputSignatureVerificationService.swift`.
- problém: Pôvodný text mohol vyžadovať QTS aj tam, kde completed inspection preukáže, že input nemá signatures.
- dopad: Legitímny P2E paper scan mohol byť blokovaný alebo unavailable inspector mohol byť omylom akceptovaný ako no signatures.
- konkrétna oprava plánu: Task 3.1 má `inspectionCompleted` a `noSignaturesPresent`; exact outcome je policy-driven a unavailable zostáva fail-closed.

### I8: Oldest timestamp mohol byť odvodený zo signingTime

- severity: Important
- presný plán alebo zdroj: `InputSignatureVerificationService.swift` riadky 40 až 43; pôvodný Task 3.1.
- problém: Aktuálny projection filtruje `hasQualifiedTimestamp`, ale minimum počíta zo `signingTime`, nie z validovaného RFC 3161 `genTime`.
- dopad: Doložka a audit mohli obsahovať nesprávny najstarší čas.
- konkrétna oprava plánu: Task 3.1 používa validované timestamp tokens a `oldestRelevantQualifiedTimestamp`; Task 4.2 zakazuje substitúciu claimed signing time.

### I9: Retry a idempotency pravidlá boli vymyslené lokálne

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 5.3.
- problém: Plán predpisoval fingerprint-based key, všetky timeouts a 5xx ako retryable a konkrétne permanent classifications bez potvrdeného EZZK contractu.
- dopad: Duplicitný EZZK record alebo opakovaný submission po nejednoznačnom výsledku.
- konkrétna oprava plánu: Task 5.3 používa iba contract-defined idempotency, classification a reconciliation. Ambiguous result zostáva indeterminate.

### I10: Report structs obsahovali content-addressed reference na vlastné bytes

- severity: Important
- presný plán alebo zdroj: Prvá opravená verzia Tasks 1.2, 2.2 a 3.1 až 3.4 počas review.
- problém: `reportArtifact` vo vnútri serializovaného reportu vytváral self-hash cycle.
- dopad: Deterministický content hash reportu nebolo možné vypočítať bez fixpoint alebo vylúčenia field z hash contractu.
- konkrétna oprava plánu: Report structs už self-reference neobsahujú. `VerificationArtifactReference` vzniká po serializácii a audit event ho viaže k stage outputu.

### I11: Input-signature clean cutover nemal všetky callsite files

- severity: Important
- presný plán alebo zdroj: Pôvodný Task 3.1 files a `QualifiedSigningProviding` v `SigningProvider.swift`.
- problém: Task sľuboval odstrániť compatibility projection, ale neuvádzal protocol file, Keychain provider ani `ZakoSessionStore`.
- dopad: Plan implementer by musel ponechať shim alebo by build neprešiel.
- konkrétna oprava plánu: Task 3.1 teraz uvádza `SigningProvider.swift`, `KeychainXAdESSigningProvider.swift` a `ZakoSessionStore.swift` a vyžaduje clean cutover v jednom tasku.

## Minor Findings

### M1: Generic typ `AcceptanceState` kolidoval s viacerými doménami

- severity: Minor
- presný plán alebo zdroj: Pôvodný Task 2.1.
- problém: Názov nerozlišoval form-pack a output-profile acceptance.
- dopad: Vyššie riziko nesprávneho importu alebo switchu.
- konkrétna oprava plánu: Používa sa `FormPackAcceptanceState` a `OutputProfileAcceptanceState`.

### M2: Signature format bol voľný String

- severity: Minor
- presný plán alebo zdroj: Pôvodný `ValidatedSignature.format`.
- problém: Typ umožňoval ľubovoľný label a nekonzistentné case handling.
- dopad: Nespoľahlivé policy a fixture matching.
- konkrétna oprava plánu: Zavedený `SignatureFormat` s pades, xades, cades a unknown.

### M3: Evidence package entry kind bol voľný String

- severity: Minor
- presný plán alebo zdroj: Pôvodný Task 6.3.
- problém: Manifest nemal uzavretý vocabulary.
- dopad: Nejednoznačný export a verifier.
- konkrétna oprava plánu: Zavedený `EvidencePackageEntryKind`.

### M4: Hashable interfaces nemali explicitne Hashable member enums

- severity: Minor
- presný plán alebo zdroj: Pôvodné snippets Tasks 0.2, 1.1, 2.1 a 4.1.
- problém: Viaceré structs deklarovali Hashable, ale plán explicitne neuvádzal Hashable na vlastných enumoch.
- dopad: Nejasný alebo nekompilovateľný implementačný snippet.
- konkrétna oprava plánu: Finálne interfaces majú explicitné Hashable alebo Equatable conformance podľa consumer structu.

## Type and Dependency Consistency

### Pôvodné nekonzistencie

1. `ZaKoRuntimeMode` nemal `demo`, hoci global policy demo odlišovala.
2. `ZaKoRuntimePolicy` používal booleans, ktoré bolo možné skonštruovať v rozpore s mode.
3. Task 1.1 redefinoval `ConversionFormPack` bez `manifestVersion`, `verificationState`, `renderer` a codelist mappings z existujúceho `FormPack.swift`.
4. Pôvodný form-pack acceptance nerozlišoval pilot, sandbox a production.
5. Task 2.1 odstránil existujúci `label` a zaviedol generic `AcceptanceState` bez migration contractu.
6. `ConversionOutputProfile.Container` nebol v plánovanom final interface explicitne definovaný.
7. `SignatureValidationReport` používal string format a report-level state bez exact signed objects.
8. `CertificateValidationReport` používal booleans, ktoré mohli byť navzájom rozporné.
9. `QualifiedTimestampReport` vyžadoval `genTime` a fingerprint aj pri malformed tokene.
10. `EZZKSubmissionResult.accepted: Bool` nevedel vyjadriť retryable, permanent a indeterminate výsledok.
11. Evidence-number lifecycle state a dve deadline rules neboli definované.
12. `ZaKoProductionPreflight` miešal pre-generation a post-signature gates.
13. Report structs pôvodne počas review obsahovali self-referential content-addressed reference.
14. Task 3.1 clean cutover neuvádzal všetky protokoly a callers.
15. Task 2.3 závisel od typov a dôkazov, ktoré vznikali až v neskoršej Phase 3.

### Finálne typy a dependency chain

- Task 0.2 produkuje `ZaKoRuntimeMode`, `EZZKProviderCapability`, `ZaKoFormPackPolicy` a uzavretý `ZaKoRuntimePolicy.policy(for:)`.
- Task 0.3 produkuje `VerificationArtifactReference` pred všetkými report typmi.
- Task 1.1 produkuje explicitné form-pack verification, acceptance a renderer enums, `FormPackArtifact`, final `ConversionFormPack` a `OfficialFormPackProviding`.
- Task 1.2 produkuje oddelené record a clause validation a rendering reports.
- Task 2.1 produkuje `OutputProfileAcceptanceState`, `ApplicantNoticePolicy` a final `ConversionOutputProfile` vrátane nested `Container`.
- Task 2.2 produkuje oddelenie `localPreflight` a `independentConformance`.
- Task 3.1 produkuje spoločné `ValidationConclusion`, `SignatureFormat`, `RevocationStatus`, `SignedObjectReference`, timestamp a signature report types.
- Task 3.2 až 3.4 tieto types iba konzumujú a pridávajú certificate, trusted time, QTS a package reports.
- Task 4.1 produkuje `ZaKoProductionStage` a `EvidenceAuditEvent` pred Task 6.1.
- Task 5.1 konzumuje `EZZKProviderCapability`, `TrustedServerTime`, `SignedObjectReference` a `VerificationArtifactReference` a produkuje EZZK protocol types.
- Task 6.1 konzumuje všetky predchádzajúce reporty a produkuje `ZaKoProductionGate` a exhaustive validation errors.
- Task 6.3 produkuje typed export manifest bez voľného `kind` stringu.

Lokálny extraction check nad všetkými Swift code blocks v opravenom pláne nenašiel nedefinovaný capitalized type po odrátaní Swift standard types a existujúcich repo types `ConversionDirection` a `ZakoCodelistItem`. Produkčný build ani Swift tests neboli spustené, pretože Session 1 zakazuje implementáciu a produkčný Swift kód nebol menený.

## Required Plan Changes

1. [x] Urobiť working requirements explicitne neautoritatívne a zaviesť blocking authority rows.
2. [x] Rozšíriť authority inventory o exact form, codelist, output, package, signature, certificate, TSA, EZZK, registration a dve deadline rules.
3. [x] Oddeliť demo, pilot, sandbox a production mode aj provider capability.
4. [x] Zakázať mock, sandbox a non-submitting provider v production capability.
5. [x] Zachovať a migrovať všetky existujúce form-pack provenance fields a oddeliť historical validation selection.
6. [x] Oddeliť record a clause XSD a XSLT roles a rendering.
7. [x] Urobiť PDF/A-1a safe default bez nepreukázaného productionAccepted statusu.
8. [x] Pridať tagged PDF, Unicode, OCR, DPI, compression a PNG constraints ako authority-controlled policy.
9. [x] Zmeniť alternative-format warning na pre-conversion domain gate a immutable audit evidence.
10. [x] Oddeliť input PAdES, XAdES a CAdES validation od output authorization profile.
11. [x] Pridať exact signed-object, chain, revocation, qualification, mandate, QTS a timestamp-token evidence.
12. [x] Počítať oldest relevant qualified timestamp iba z validovaných tokens, nie zo signingTime.
13. [x] Presunúť final package validation za signing a QTS.
14. [x] Oddeliť evidence-number validity a submission deadline.
15. [x] Nahradiť guessed idempotency a retry pravidlá contract-defined classification a reconciliation.
16. [x] Oddeliť transport request signature od signed business object.
17. [x] Zaviesť typed production stages a immutable hash handoffs.
18. [x] Doplniť source-origin, page, sheet, paper-size a human-review gates.
19. [x] Oddeliť local preflight, independent conformance, sandbox evidence a release approval.
20. [x] Odstrániť production dry-run transport test.
21. [x] Doplniť focused, integration, real sandbox a external conformance evidence.
22. [x] Udržať XMLDataContainer v samostatnom budúcom E2P projekte.
23. [x] Udržať E2E v samostatnom budúcom projekte.
24. [x] Opraviť type names, conformance, callsite files, self-hash cycle a task dependencies.
25. [ ] Pred Session 2 dodať a overiť všetky required authority artifacts. Toto je external blocker, nie plan defect.
26. [ ] Pred production enablement získať independent conformance reports a real EZZK sandbox evidence pre exact release hashes. Toto je release blocker.

Pôvodný verdikt: REJECT.

Finálny verdikt po oprave plánu: APPROVE WITH CHANGES.
