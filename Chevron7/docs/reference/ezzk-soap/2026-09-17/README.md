# EZZK SOAP contract snapshot, 2026-09-17

WSDL and XSD files of the EZZK SOAP service as published on 2026-09-17, used by
`EZZKSOAPRequestTests` to validate the request bodies Autogram builds. Design:
`Chevron7/docs/superpowers/specs/2026-09-17-ezzk-soap-design.md`.

## Sources

| Folder | Service | Login |
| --- | --- | --- |
| `production/` | `https://ezzk.iomo.sk/EZZK.Svc.Wcf/EZZKService.svc?wsdl` | `https://ezzk.iomo.sk/Iam.Core3.Svc.Wcf/LogInService.svc?wsdl` |
| `test/` | `https://ezzk-test.iomo.sk/EZZK.Svc.Wcf/EZZKService.svc?wsdl` | `https://ezzk-test.iomo.sk/Iam.Core3.Svc.Wcf/LogInService.svc?wsdl` |

Each `?wsdl=wsdlN` part is saved as `EZZKService-wsdlN.wsdl` and each `?xsd=xsdN`
part as `EZZKService-xsdN.xsd` or `LogInService-xsdN.xsd`. The `location` and
`schemaLocation` attributes were rewritten to these local names so `xmllint --nonet`
can resolve the imports. Nothing else was changed.

The written description is MIRRI's "Integračný manuál poskytovaných služieb modulu
EZZK" version 1.4 (2019-11-18), linked from
`https://mirri.gov.sk/sekcie/informatizacia/dokumenty/zakon-o-e-governmente/centralna-evidencia-zaznamov-o-vykonanej-zarucenej-konverzii/`.
Where the manual and these files disagree, these files and the live service win.

## Differences between the environments

- Login schemas are identical.
- The request types Autogram sends (`GetConversionRecordEvidenceNumber`,
  `ConsumeConversionRecordEvidenceNumber`, `ReceiveConversionRecord`,
  `GetConversionRecord`, `GetConversionRecordInformationPurpose`) are identical.
- Test additionally declares `GetConversionRecord2` with `ZiadostVypis2` and
  `OdpovedVypis2`.
- The document name, format, sheet count and `Purpose` elements of `OdpovedVypis`
  sit in the base type (`EZZKService-xsd3.xsd`, namespace `...EZZK.Dol`) in
  production, but in the derived types (`EZZKService-xsd4.xsd` and
  `EZZKService-xsd7.xsd`, operation namespaces) in test. Response parsing matches
  elements by local name and treats those fields as optional.

Request validation in tests uses `production/`.
