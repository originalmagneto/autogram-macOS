# Trademark Mini-Hub – Architecture Blueprint

## 1. Purpose & scope
The Trademark Mini-Hub is a privacy-first, offline-capable PWA that helps solo and small-firm attorneys manage
trademark portfolios, deadlines, and supporting evidence. The architecture must:

- Minimize operational overhead while keeping data under the firm's control.
- Provide instant, trustworthy reminders and audit trails for renewals.
- Support local OCR + light NER on commodity hardware, defaulting to on-device processing.
- Allow gradual rollout of server-side capabilities such as EUIPO polling and calendar push while keeping
the MVP functional offline.

## 2. High-level solution overview
The system is split into three deployable layers so that firms can choose the footprint they need:

1. **Client Application (PWA)** – React/TypeScript front-end delivered via Vite with Workbox-powered service worker.
   Runs fully offline, keeps an IndexedDB data store (Dexie) with encrypted blobs for sensitive fields, and
   exposes key UX (Dashboard, Marks, Import Wizard, Templates, Settings). Browser-accessible on desktop and mobile;
   optional Capacitor wrapper can reuse the same bundle.
2. **Edge AI Worker** – Web Worker pool managed from the PWA. OCR is handled by PaddleOCR (WASM) with Tesseract
   fallback; field extraction uses heuristic extractors and quantized ONNX TinyBERT micro-NER running via
   `onnxruntime-web`. Workers communicate through Comlink and produce JSON proposals with evidence offsets.
3. **Control Plane Service (optional)** – Self-hostable Node.js (Fastify) service with PostgreSQL (or SQLite for
   single-device deployments) that provides background jobs. V1.0 can run without it; once EUIPO polling or calendar
   push is enabled, the service becomes required. Responsibilities:
   - Background schedulers (BullMQ) for EUIPO polling, watchlist reminders, and ICS push retries.
   - OAuth token storage for Google/Outlook integrations (encrypted using libsodium sealed boxes per user).
   - Webhook endpoint for calendar providers and mail intake (forwarded `.eml`).
   - REST/GraphQL API consumed by the PWA when online. When offline, the client queues mutations and syncs through
     the service when reachable.

All components are containerized; the server can be deployed on-prem (Docker Compose) or on a privacy-conscious
cloud (Hetzner/OVH) that the firm controls.

### Component interaction snapshot
```
Browser PWA (React + Dexie) ←→ Service Worker cache
           ↓ (Comlink)
    Edge AI Worker Pool (OCR, NER, heuristics)
           ↓
 Local Audit Store (IndexedDB tables: trademarks, documents, reminders, audit_log, sync_queue)
           ↕ (when online)
Control Plane API (Fastify) ↔ PostgreSQL ↔ EUIPO API / Calendar provider / Mail bridge
```

## 3. Client application architecture

- **State management:** TanStack Query for server-backed resources, Zustand for UI/local state, Dexie for persistent
  collections. Data models are defined through Zod schemas to reuse validation on the client and server.
- **Routing & navigation:** React Router with nested layouts. Keyboard shortcut layer uses `cmdk` and `@radix-ui`
  primitives for Command Palette and accessibility.
- **UI toolkit:** Headless UI + custom design token system (CSS variables) to satisfy theming requirements. Table
  virtualization delivered by `@tanstack/react-virtual`. Evidence viewer leverages PDF.js and canvas overlays.
- **Offline support:** Workbox injectManifest strategy caches shell + last 50 marks, while Dexie persists structured
  data. A sync queue table records pending mutations; each entry stores the REST operation, payload, optimistic state
  snapshot, and audit metadata.
- **PWA enhancements:** Background sync (where supported) flushes the queue. App manifest and custom install prompts
  satisfy Add-to-Home flows. For desktop file linking, the File System Access API stores permission handles.

## 4. Data model snapshot

Each record is versioned locally and, when connected, mirrored to the Control Plane. Core tables:

- `trademarks`: fields defined in the PRD (mark_name, jurisdiction, classes, ref_no, filing_date, reg_date,
  expiry_date, status, tags, client_id, timestamps, rule_pack_version, manual_override_reason?).
- `documents`: link to `trademark_id`, `path_or_url`, `sha256`, `type`, `added_at`, optional `ocr_text`, optional
  `file_handle_id` for FS access API.
- `reminders`: `trademark_id`, `type`, `due_at`, `channel`, `status`, `external_event_id`, `sent_at`, `notes`.
- `clients`: `name`, `emails`, `phones`, `address`, `retention_flags`.
- `watch_items`: `source_url`, `last_checked_at`, `next_check_at`, `evidence` array (each evidence stores
  `type`, `reference`, `hash`, `added_by`, `added_at`).
- `audit_log`: append-only table storing actor, action, entity reference, diff, timestamp, source metadata (user,
  AI worker id, EUIPO job id) and model/rule versions.
- `rule_packs`: `jurisdiction`, `validity_years`, `renewal_window_months_before`, `grace_months_after`, `fee_note`,
  `version`, `applied_at`.
- `sync_queue`: pending operations with exponential backoff metadata.

All JSON blobs are validated through shared schemas. Sensitive fields (emails, phone numbers) are encrypted at rest in
Dexie using WebCrypto AES-GCM with a key derived from the user's passphrase.

## 5. Rule Pack engine

The rule pack service is implemented as a deterministic pure-function module (TypeScript + Zod). It exposes:

```ts
computeDeadlines({ filingDate, registrationDate, jurisdiction, overrides? }) => {
  expiryDate,
  renewalWindowStart,
  graceEnd,
  status
}
```

- Rule packs are versioned and stored both locally and server-side. When a pack updates, affected trademarks are
  recomputed in a background worker; results are surfaced via a notification banner with per-record diffs.
- Overrides require a reason + optional attachment, logged into `audit_log`.
- AC-MVP-01 is covered by unit tests validating jurisdiction presets (EUTM, SK, WIPO IR) and by contract tests shared
  with the Control Plane.

## 6. Import & extraction pipeline

1. File acquisition (upload/drag&drop/share-sheet). Files are stored as object URLs; `.eml` attachments are unpacked
   using the `mailparser` WASM build.
2. Pre-processing: convert to images (PDF.js + canvas), run binarization when needed.
3. OCR stage: PaddleOCR WASM (int8 quantized) with fallback to native APIs where available (Vision/ML Kit via
   Capacitor wrapper). OCR results include bounding boxes and confidences.
4. Extraction: heuristics (regex + dictionary) + micro-NER (TinyBERT) executed in Web Worker. Each field is accompanied
   by evidence offsets, raw text snippet, and confidence score.
5. Conflict resolution: if a trademark with same ref_no exists, the worker proposes a diff. The Review step shows the
   diff and asks for confirmation.
6. Persistence: once confirmed, the document link and extracted metadata are stored. The audit log entry references the
   model version and OCR artifact (sha256 of text fragment).

Errors (OCR failure, low confidence) fall back to manual entry with prompts described in the PRD. Extraction jobs are
interruptible to keep the UI responsive.

## 7. Reminder & calendar engine

- Reminder templates are generated client-side immediately after deadline computation. The queue ensures three default
  reminders (−180/−90/−30 days) are created with `channel = "ics"` until a calendar integration is configured.
- ICS generation is performed in-browser using `ical.js`; exports include `UID` derived from trademark id + reminder
  type to prevent duplicates (AC-MVP-03). When the Control Plane is present, reminders targeting a provider are
  synchronized via REST endpoints; success updates `external_event_id`.
- Calendar push uses provider-specific connectors hosted in the Control Plane. OAuth tokens are stored encrypted; jobs
  are retried with exponential backoff and yield audit entries.

## 8. Offline behaviour & sync

- **Queueing:** create/update/delete operations write to `sync_queue` with operation metadata (endpoint, method, body,
  optimistic diff, dependencies). The UI shows an offline badge with queue length. Users can inspect the Sync Queue
  view to retry or drop operations.
- **Reconciliation:** upon reconnect, the client flushes operations FIFO. Server responses include version counters;
  conflicts trigger `last-writer-wins` on the server but the client stores the rejected version for audit/undo.
- **Data hydration:** the service worker pre-caches shell and last 50 marks via background fetch. Additional data is
  lazily fetched when navigating while online.
- **File linking:** since files stay external, we store either File System Access handles (desktop) or plain paths/URLs
  with status `unresolved`. Users can relink when offline; verification occurs once back online.

## 9. Security, privacy, and compliance

- **GDPR features:** per-client export/erase operations run entirely on-device when possible. When the Control Plane is
  involved, exports stream JSON/CSV plus references to document paths (no file copies). Retention flags mark records
  for review before deletion.
- **Encryption:** Local symmetric key derived via PBKDF2 + WebCrypto. Server tokens encrypted using libsodium sealed
  boxes per user. TLS everywhere; HTTP Strict Transport Security for hosted deployments.
- **Audit trail:** append-only, tamper-evident by storing chained hashes (`prev_hash`). Audit entries identify source
  (`user`, `ai`, `euipo_poll`, `watch_check`) and capture evidence metadata.
- **Access control:** MVP is single-user; once multi-user arrives, the Control Plane enables role-based policies. JWTs
  (short-lived) with refresh tokens stored in IndexedDB under encryption.

## 10. Observability & analytics

- Client-side analytics are privacy-preserving and stored locally until export (no third-party trackers). Events listed
  in the PRD (e.g., `add_mark_save`, `import_success`) are persisted in Dexie and optionally exported to CSV for manual
  review. When the Control Plane is enabled, aggregated metrics are pushed via authenticated API.
- Server observability uses OpenTelemetry instrumentation (traces, metrics). Background jobs expose Prometheus metrics
  for polling success rates and reminder delivery ratios.

## 11. Deployment model

- **Development:** Vite dev server + Fastify API (optional). Docker compose spins up Fastify + PostgreSQL + MinIO for
  storing optional artifacts (screenshots of evidence).
- **Production:** Static hosting (Netlify, Cloudflare Pages, or self-hosted Nginx) for the PWA. Control Plane packaged
  as Docker image with migrations managed by Prisma. Cron jobs run within the same container using worker processes.
- **Mobile wrapper:** Capacitor builds reuse the PWA bundle; native plugins provide camera, file access, and push.

## 12. Roadmap alignment & extensibility

- **Slice A (CRUD, deadlines, reminders, ICS):** Covered by Dexie models, rule pack module, ICS engine. Requires only
  PWA components.
- **Slice B (Import wizard & document linking):** Delivered through Edge AI worker pipeline and Document modules.
- **Slice C (PWA offline + sync):** Already core to architecture via service worker + sync queue.
- **Slice D (EUIPO polling & watchlists):** Needs Control Plane background jobs and watchlist persistence.
- **Slice E (Templates & email drafts):** Template module layered on top of existing data; server optionally handles
  email bridging.
- Later features (multi-user ACL, CalDAV push, optional cloud NER) can be layered by extending Control Plane modules
  without rewiring the client architecture.

