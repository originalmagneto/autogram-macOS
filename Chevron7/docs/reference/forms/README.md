# Official conversion forms

Verbatim files from the slovensko.sk form packages that Chevron7 references in every
XMLDataContainer it builds: record 1.0 (`ConversionRecordOfPaperToElectronicDocument`) and
clause 1.3 (`ConversionCertificateOfPaperToElectronicDocument`). Sources, hashes and the digest
rule are in `provenance.json`. The presentation file is the package manifest's
`media-destination="sign"` entry (record: TXT; clause: the HTML one).

After changing any file here, run `scripts/embed-official-forms.sh` and commit the regenerated
`Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift`. `OfficialFormTests` fails when
the two drift apart. The record digests must stay equal to those of the record EZZK accepted on
2026-08-24 (spec: `docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md`).
