# Trademark Mini-Hub – Implementation Plan

This plan operationalizes the PRDs into actionable delivery slices, each ending in a demonstrable increment. The plan
assumes a small cross-functional team (1 full-stack, 1 front-end, 1 product/QA, part-time designer) working in
2-week iterations.

## Guiding principles
- Release usable value after each slice while keeping the PWA installable and data under user control.
- Keep AI-assisted features optional and always behind a human confirmation step.
- Build observability, testing, and auditability into the first slice to avoid rework.

## Slice A – Core registry (CRUD, deadlines, reminders, ICS)
**Goal:** Attorneys can store trademarks, compute deadlines per jurisdiction, and export renewal reminders.

### Scope
- React PWA shell with authentication bootstrap (single-user passphrase).
- Dexie schemas + Zod validation for `trademarks`, `clients`, `reminders`, `rule_packs`, `audit_log`.
- Rule Pack engine with presets (EUTM, SK, WIPO IR) and unit tests covering AC-MVP-01.
- Reminder generator producing default −180/−90/−30 entries with ICS export (`ical.js`).
- Dashboard + Trademark list + Add/Edit forms + Reminder view.
- Audit drawer logging create/update/delete operations.
- Basic analytics counters (time to add mark, ICS exports) stored locally.

### Acceptance checks
- Demo AC-MVP-01 and AC-MVP-03 end-to-end.
- Offline read for last 50 marks works (manual toggle via Chrome dev tools).
- Unit tests for `computeDeadlines`, ICS generator, Dexie schema migrations.

### Deliverables
- Deployed static build (Netlify dev or local static server) + README instructions.
- Initial QA checklist & Cypress happy-path test (Add mark → export ICS).

## Slice B – Import wizard & document linking
**Goal:** Speed up intake with AI-assisted extraction while keeping evidence traceable.

### Scope
- File ingestion UI (drag&drop, share-sheet stub) with 5-step wizard.
- Edge AI worker bundle (PaddleOCR WASM, heuristics, TinyBERT micro-NER).
- Evidence viewer with PDF.js overlay + text highlight.
- Document linking (path/URL + hash) with "Resolve path" flow.
- Audit entries capturing AI proposals, confidence, and evidence references.
- Local storage of OCR text (opt-in toggle) and hashed references by default.

### Acceptance checks
- AC-MVP-02 satisfied with provided EUIPO sample PDF.
- OCR failure fallback to manual entry retains document link.
- Extraction results stored with model version + evidence and visible in timeline.
- Performance budget: import 1-page PDF < 3s on reference laptop (8 GB RAM).

### Deliverables
- Worker unit tests (regex heuristics, JSON contracts) + integration test with fixture PDF.
- Updated analytics capturing `import_start`, `ai_field_accept`, `ai_field_edit`.

## Slice C – PWA offline sync & queue transparency
**Goal:** Make the PWA resilient offline and provide user-facing sync management.

### Scope
- Workbox `injectManifest` service worker with precache + runtime caching strategies.
- Sync queue module (Dexie table + UI view) supporting retry/clear actions.
- Background Sync integration (when available) and manual "Sync now" command.
- Conflict handling UI (toast + audit diff) implementing last-writer-wins while surfacing overrides.
- Offline indicators in top bar, queued operation counter, devtools to simulate offline.

### Acceptance checks
- AC-MVP-04: offline list/detail accessible; queued edits sync automatically upon reconnect.
- QA scenario: disable network, edit mark, re-enable, verify audit + success toast.

### Deliverables
- Playwright/Cypress test covering offline edit queue flow.
- Documentation for operations queue format and troubleshooting.

## Slice D – EUIPO polling & manual watchlists (V1.1)
**Goal:** Provide automated status monitoring and manual evidence logging.

### Scope
- Control Plane service (Fastify + PostgreSQL) with background worker (BullMQ) and Prisma migrations.
- REST endpoints for trademarks, reminders, watchlists, sync queue ingestion.
- EUIPO polling job (24h cadence, backoff, rate-limit guard) storing diffs + `api_request_id` in timeline.
- Manual/Assisted Watchlist UI with evidence upload (URL, screenshot, hash) and "Check now" trigger.
- Secure OAuth storage for single calendar provider + push job with ICS fallback.

### Acceptance checks
- AC-V1.1-01: simulated EUIPO change recorded with diff + request id.
- Watchlist evidence requires at least one artifact before marking complete.
- Calendar push creates external event id, avoids duplicates via `external_event_id` constraint.

### Deliverables
- Docker Compose stack (Fastify, PostgreSQL, MinIO) + seed data.
- Contract tests between PWA sync client and API (using Pact or MSW).
- Monitoring dashboards (Grafana/Prometheus) for polling success, job queue depth.

## Slice E – Templates & communication tooling (V1.1)
**Goal:** Allow quick generation of legal templates and email drafts integrated with trademark data.

### Scope
- Templates section with CRUD for template metadata and rich-text editor (TipTap) supporting placeholders.
- Merge engine generating DOCX (docx.js) and email drafts (EML/HTML) referencing trademark/client data.
- Export dialog with GDPR purpose confirmation and audit log entry.
- Optional server hook to send drafts via configured SMTP relay (if Control Plane present).

### Acceptance checks
- Template merge produces correct placeholders for `expiry_date`, `client.name`, `trademark.ref_no`.
- Audit log records export purpose and template version.
- Email draft preview accessible before download/send.

### Deliverables
- Jest unit tests for merge engine + snapshot tests for sample templates (SK/EN).
- User help doc describing placeholder syntax and template versioning.

## Cross-cutting workstreams

### QA & automation
- Unit test coverage targets: ≥70% for business logic (rule packs, extractor heuristics, merge engine).
- Visual regression snapshots for key screens (Dashboard, Trademark detail, Import wizard step 4).
- Security testing: dependency scanning (Dependabot), OWASP ZAP baseline scan for Control Plane.

### Privacy & compliance
- Data map maintained as Markdown doc describing stored fields, retention, and encryption.
- Export/erase scripts validated with anonymized fixtures.
- DPIA template prepared before production usage.

### Documentation & support
- Living README with setup instructions, including offline testing tips.
- User guides for Import Wizard, Sync Queue, Watchlists, Template editor.
- Release checklist covering audit log review, regression tests, accessibility spot-check.

## Risks & mitigations (tracked each iteration)
| Risk | Mitigation |
| --- | --- |
| OCR accuracy insufficient on poor scans | Maintain multi-engine fallback, collect anonymized failure cases for tuning, surface manual entry quickly. |
| EUIPO API instability | Implement exponential backoff + circuit breaker, keep manual watchlists as fallback, allow user to disable polling per mark. |
| PWA background sync limitations (Safari/iOS) | Provide explicit "Sync now" action and remind users when queue > X items, support manual ICS downloads as fallback. |
| On-device storage encryption complexity | Use well-maintained libraries (IndexedDB encryption wrappers), provide recovery instructions, and allow optional non-encrypted mode for air-gapped machines. |

## Definition of done (slice-level)
- Functional acceptance criteria met, including PRD ACs relevant to slice.
- Automated tests updated and passing; manual QA notes captured.
- Accessibility checklist (WCAG 2.1 AA spot-check) updated for new screens.
- Audit log events confirmed (via local inspection) for new workflows.
- Documentation updated (developer + user-facing).

