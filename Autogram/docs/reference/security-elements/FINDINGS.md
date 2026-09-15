# Official security element form findings

Retrieved 2026-09-15. Read-only research. All downloads are official Slovensko.sk dataset archives. Source URLs and SHA-256 values are in provenance.json. The complete research downloads remain in /tmp/autogram-security-form-research. This repository directory keeps only compact evidence: provenance.json, select-options.json, the two parser-serialized security excerpts and a standalone test schema. Source hashes describe the original research files, even when those files are not copied here. The repository_artifacts_sha256 map identifies the exact compact copies committed here; the record excerpt has normalized trailing whitespace. The standalone test schema promotes the official record detail to a global root and includes its two referenced simple types; it does not validate a whole record.

## Record 1.0 (the namespace used by the current legacy generator)

Namespace: https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0

Path: /ConversionRecord/OriginalDocumentInfo/DocumentSecurityElementsDetails

The detail repeats 0..unbounded. Its children, in this exact sequence, all occur exactly once:

| Child | XSD type | Meaning |
| --- | --- | --- |
| OriginalDocumentSecurityElementsDescription | MandatoryStringType | Factual description of identified original security element |
| OriginalDocumentSecurityElementsPage | IntMax5ReqType | Original document non-empty page ordinal |
| OriginalDocumentSecurityElementsSheet | IntMax5ReqType | Original document sheet number |
| OriginalDocumentSecurityElementsLocation | MandatoryStringType | Descriptive place on the original page |
| NewDocumentSecurityElementsPage | IntMax5ReqType | Page ordinal in converted document |

MandatoryStringType is xs:string with minLength 1, no maximum, no enumeration, no whitespace collapse. It accepts narrative text. No Codelist wrapper belongs in either description or location for record 1.0. Code list 15 has no role in this record security subsection. The XSD documentation gives examples of descriptions and places. Official record HTML XSLT renders description as 'Slovný opis' and location as 'Miesto umiestnenia na strane dokumentu', each by xsl:value-of select='.'. The archive has display XSLT, not an editable HTML form.

IntMax5ReqType is xs:int restricted by pattern \d{1,5}. It has no explicit minInclusive 1. Do not infer that a semantically nonexistent scan page should be exported as zero: the documentation says page/sheet number and there is no documented missing-value sentinel.

There is no SecurityElementVerbalDescription, DescriptionOther, LocationOther, region, bounding box, nil/missing page alternative, or explicit physical-original-only flag in this detail. A scan bounding box is not required by the schema. A real original-page textual location can be used without a scan box. All three page/sheet fields remain mandatory. Neither this XSD nor these display files settle how an element absent from the scan should receive NewDocumentSecurityElementsPage. Do not invent a page index from a bounding box or claim that a zero value means 'not captured'.

## Clause 1.3 (separate official form)

Namespace: http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3
Path: /ConversionCertificateOfPaperToElectronicDocument/OriginalDocumentInfo/DocumentSecurityElementsDetails

The detail repeats 0..999. Child sequence:

1. OriginalDocumentSecurityElementsDescription, required CodelistDataElementCType.
2. OriginalDocumentSecurityElementsDescriptionOther, optional StringMax255OptType (xs:string, maxLength 255, no minimum).
3. OriginalDocumentSecurityElementsPage, required IntMax5ReqType.
4. OriginalDocumentSecurityElementsSheet, required IntMax5ReqType.
5. OriginalDocumentSecurityElementsLocation, required CodelistDataElementCType.
6. NewDocumentSecurityElementsPage, required IntMax5ReqType.

The page meanings and numeric type match record 1.0. No nil/page omission, scan region, or physical-only special marker is defined here either.

The XSD uses a generic codelist structure, not enumerated security values. The official HTML is the verified source of concrete options. Its export XPath sets CodelistCode='15' for description and '11' for location, and writes each option value to CodelistItem/ItemCode and visible name to ItemName[@Language='sk']. Generic XSD ItemCode is length 1..255; ItemName is 1..2047. Passing generic XSD validation alone does not prove membership in these HTML options.

### Description options (code list 15)

| Exact ItemCode | Exact ItemName |
| --- | --- |
| `okrúhla pečiatka` | Okrúhla pečiatka |
| `okrúhla pečiatka so štátnym znakom` | Okrúhla pečiatka so štátnym znakom |
| `reliéfna pečiatka` | Reliéfna pečiatka |
| `vodotlač` | Vodotlač |
| `vlastnoručný podpis` | Vlastnoručný podpis |
| `úradne osvedčený podpis` | Úradne osvedčený podpis |
| `spinka` | Spinka |
| `lepiaci štítok` | Lepiaci štítok |
| `nit – kovový` | Nit – kovový |
| `trikolóra šnúrka` | Trikolóra šnúrka |
| `trvale spojenie dokumentu - iné` | Trvalé spojenie dokumentu - iné |
| `pečiatka` | Pečiatka |
| `iný manuálny vstup` | Iný manuálny vstup |

The rivet code contains U+2013 EN DASH. The other-binding code is exactly 'trvale spojenie dokumentu - iné', with unaccented 'trvale'; its displayed name starts 'Trvalé'. Preserve this difference.

The HTML reveals the custom field (SlovnyPopisIne) and activates its required validator only when description is 'iný manuálny vstup'. It maps to OriginalDocumentSecurityElementsDescriptionOther, maxLength 255. XSD alone makes it optional irrespective of code. There is no field named SecurityElementVerbalDescription. The HTML does not expose custom description for the other-binding choice.

### Location options (code list 11)

| Exact ItemCode | Exact ItemName |
| --- | --- |
| `Down` | Dole |
| `Up` | Hore |
| `Down edge` | Dolný okraj |
| `Up edge` | Horný okraj |
| `Left edge` | Ľavý okraj |
| `Right edge` | Pravý okraj |
| `Mid` | Uprostred |
| `Left` | Vľavo |
| `Left down` | Vľavo dole |
| `Left up` | Vľavo hore |
| `Right` | Vpravo |
| `Right down` | Vpravo dole |
| `Right up` | Vpravo hore |

## Implementation implications and limits

- At research time the legacy generator mixed a record 1.0 root with clause-like codelists and an undocumented SecurityElementVerbalDescription element. The security-section patch corrects this subsection only. These findings concern this security subsection only and do not certify or exhaustively audit the whole generator.
- Record 1.0 can represent cord/tricolor, tape, wax seals, initials, watermarks and other observed features through a factual nonempty narrative description and a nonempty textual location without creating codes.
- For clause 1.3, use the exact specific option when its meaning fits. 'parafa', 'iný prvok', 'hologram' and 'vosková pečať' are not verified official ItemCodes. Such specific observations can be described through the verified manual-entry option and DescriptionOther. Mapping an actual object to a category still requires the observed evidence.
- No legislative or entity research was repeated. No slov_lex, judikaty or ORSR tools were used in this bounded form-artifact research. web.run search returned no matches and direct open was blocked; direct read-only HTTPS downloads with curl succeeded and were inspected locally using Python/XML and HTML parsers. These tools establish published schema/HTML content, not CEZZK acceptance or complete legal conformance.
