# Trademark Mini-Hub – Data Model & API Contracts

This document translates the domain model in the PRDs into concrete storage schemas and API endpoints. It covers both
the local IndexedDB structures (MVP) and the optional Control Plane service (V1.1+) to guarantee future compatibility.

## 1. Core entities

### 1.1 Trademark
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` (ULID) | Generated client-side; stable across sync. |
| `mark_name` | `string` | Min length 2. |
| `jurisdiction` | `"EUTM" \| "SK" \| "WIPO-IR" \| ...` | Controls ref_no mask + rule pack lookup. |
| `classes` | `number[]` | Values 1–45; stored sorted; keep translation table for UI labels. |
| `client_id` | `string` | FK to Client. |
| `ref_no` | `string` | Optional but strongly recommended; uniqueness enforced per jurisdiction. |
| `filing_date` | `string (ISO 8601 date)` | Optional. |
| `reg_date` | `string` | Must be ≥ `filing_date` if both exist. |
| `expiry_date` | `string` | Computed via rule pack unless `expiry_override` set. |
| `expiry_override` | `{ value: string, reason: string } \| null` | Requires justification and audit entry. |
| `status` | `"draft" \| "active" \| "pending_renewal" \| "expired" \| "archived"` | Derived automatically; manual overrides logged. |
| `tags` | `string[]` | Max 8. |
| `rule_pack_version` | `string` | Last applied version. |
| `created_at` / `updated_at` | `string` | ISO timestamps. |

### 1.2 Client
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` (ULID) | |
| `name` | `string` | Required. |
| `emails` | `{ value: string, masked?: boolean }[]` | Masked field for list view; stored encrypted at rest. |
| `phones` | `string[]` | Optional. |
| `address` | `string` | Optional multi-line. |
| `retention_flags` | `{ type: "archive" \| "erase-by", value: string }[]` | Supports GDPR workflows. |
| `notes` | `string` | Optional; stored encrypted. |

### 1.3 Document
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` | |
| `trademark_id` | `string` | Required. |
| `path_or_url` | `string` | Displayed as-is; absolute path or HTTPS URL. |
| `fs_handle_id` | `string \| null` | Reference to File System Access handle (desktop). |
| `sha256` | `string` | Hex digest of file; recomputed when relinking. |
| `type` | `"filing" \| "registration" \| "renewal" \| "evidence" \| "other"` | Enum; extendable. |
| `ocr_text` | `string \| null` | Only stored if OCR retention enabled. |
| `added_at` | `string` | Timestamp. |
| `added_by` | `string` | Actor id. |
| `status` | `"ok" \| "unresolved"` | `unresolved` when path invalid. |

### 1.4 Reminder
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` | |
| `trademark_id` | `string` | |
| `type` | `"renewal" \| "custom"` | |
| `offset_days` | `number` | Negative for pre-expiry reminders. |
| `due_at` | `string` | |
| `channel` | `"ics" \| "calendar" \| "email"` | Email reserved for V1.1+. |
| `status` | `"planned" \| "exported_ics" \| "pushed_calendar" \| "sent_email"` | |
| `external_event_id` | `string \| null` | Calendar provider reference. |
| `sent_at` | `string \| null` | Timestamp of last successful delivery. |
| `notes` | `string` | Optional. |

### 1.5 WatchItem (V1.1)
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` | |
| `trademark_id` | `string` | |
| `source_url` | `string` | e.g., EUIPO register page. |
| `last_checked_at` | `string \| null` | |
| `next_check_at` | `string \| null` | Scheduled poll. |
| `evidence` | `Evidence[]` | Array described below. |
| `status` | `"idle" \| "change_detected" \| "needs_review"` | |

`Evidence` object:
```
{
  id: string,
  type: "url" | "screenshot" | "note",
  reference: string,        // URL or object storage key
  hash: string | null,      // sha256 for screenshot/hash
  added_by: string,
  added_at: string
}
```

### 1.6 AuditLog
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `string` | |
| `actor_id` | `string` | "user" for manual actions, synthetic IDs for AI/API. |
| `actor_type` | `"user" \| "ai" \| "system"` | |
| `action` | `string` | e.g., `trademark.create`, `import.proposed`. |
| `entity_type` | `string` | `trademark`, `document`, `reminder`, etc. |
| `entity_id` | `string` | |
| `diff` | `JSON` | RFC 6902 patch or before/after snapshot. |
| `source_meta` | `JSON` | Contains `model_version`, `rule_pack_version`, `api_request_id`, etc. |
| `timestamp` | `string` | |
| `prev_hash` / `hash` | `string` | Chain for tamper evidence. |

## 2. IndexedDB schema (Dexie)
```
const db = new Dexie('tmhub');
db.version(1).stores({
  trademarks: 'id, mark_name, jurisdiction, ref_no, expiry_date, status, client_id',
  clients: 'id, name',
  documents: 'id, trademark_id, sha256, status',
  reminders: 'id, trademark_id, due_at, status, channel',
  watch_items: 'id, trademark_id',
  audit_log: '++local_id, timestamp, entity_type, entity_id',
  rule_packs: 'jurisdiction, version',
  sync_queue: '++local_id, status, entity_type',
  analytics: 'event_type, timestamp'
});
```
- Encryption wrapper intercepts `put`/`bulkPut` to encrypt selected fields (emails, notes, ocr_text).
- `sync_queue` entries include `{ op: "POST" | "PATCH" | "DELETE", endpoint, payload, retryCount, lastAttemptAt }`.

## 3. Control Plane data model (PostgreSQL via Prisma)
Key tables mirror IndexedDB but add server-specific metadata (tenant_id for multi-user future).

```
model Trademark {
  id               String   @id
  tenantId         String
  markName         String
  jurisdiction     String
  classes          Int[]
  clientId         String
  refNo            String?
  filingDate       DateTime?
  regDate          DateTime?
  expiryDate       DateTime?
  expiryOverride   Json?
  status           String
  tags             String[]
  rulePackVersion  String
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt
  reminders        Reminder[]
  documents        Document[]
  watchItems       WatchItem[]
  audits           AuditLog[]
}
```

Additional tables include `Reminder`, `Document`, `WatchItem`, `Evidence`, `AuditLog`, `RulePack`, `User`, `AccessToken`,
`JobRun` (for EUIPO polling) and `SyncOperation` (server-side queue for idempotency).

## 4. API surface (REST JSON, versioned under `/api/v1`)

### Authentication
- `POST /auth/session`: create local session using passphrase-derived key (single-user). Returns JWT for Control Plane.
- `POST /auth/refresh`: refresh token. Stored encrypted in IndexedDB.

### Trademarks
- `GET /trademarks?updated_after=ISO`: delta sync for changed marks.
- `POST /trademarks`: create (idempotent via `Idempotency-Key` header = ULID).
- `PATCH /trademarks/:id`: partial update; server recomputes deadlines unless `expiry_override` provided.
- `POST /trademarks/:id/recompute`: trigger recomputation when rule pack changes.
- `GET /trademarks/:id/audit`: paginated audit entries.

### Clients
- `GET /clients`, `POST /clients`, `PATCH /clients/:id`, `DELETE /clients/:id` (soft delete with retention log).

### Documents
- `POST /trademarks/:id/documents`: register metadata + (optional) evidence upload. Binary files remain external; only
  metadata stored. For screenshots, use `PUT /uploads/:key` (signed URL) followed by metadata association.
- `POST /documents/:id/resolve`: update `path_or_url` and recompute `sha256`.

### Reminders
- `GET /trademarks/:id/reminders`: server canonical list.
- `POST /trademarks/:id/reminders`: create custom reminder.
- `POST /reminders/:id/export-ics`: returns ICS payload and logs audit entry.
- `POST /reminders/:id/push`: triggers provider sync; responds with external event id.

### Rule packs
- `GET /rule-packs`: list available packs with versions.
- `POST /rule-packs/apply`: bulk update marks; accepts `{ jurisdiction, version }`.

### Watchlists & polling (V1.1)
- `GET /trademarks/:id/watch-items`
- `POST /trademarks/:id/watch-items`
- `POST /watch-items/:id/check-now`: enqueues immediate poll.
- `POST /watch-items/:id/evidence`: attach evidence metadata; for screenshots use upload endpoint first.

### Sync operations
- `POST /sync/batch`: accepts array of queued mutations from client. Server responds with success/failure per item and
  the authoritative record payload. This reduces HTTP chatter and supports offline catch-up.
- `GET /sync/changes?since=cursor`: returns paginated change log (for two-way sync once multi-user support arrives).

## 5. Eventing & background jobs

### EUIPO polling job
```
cron: every 24h (configurable)
for each trademark with jurisdiction="EUTM" and ref_no:
  call EUIPO API (REST/soap, adapter module)
  compare payload hash with last stored hash
  if changed:
     record diff (JSON patch)
     update trademark fields (status, expiry if provided)
     append audit log with source_meta.api_request_id
     enqueue reminder recalculation if expiry changed
```
Retries use exponential backoff capped at 24h; failures flagged in dashboard.

### Reminder push job
- Triggered when reminders with `channel="calendar"` and `status="planned"` reach `due_at - lead_time`.
- Uses provider-specific SDK (Google Calendar API, Microsoft Graph). Stores `external_event_id`, handles duplicates by
  performing `GET` before `POST` using stored id.

### Watchlist "Check now" flow
1. User clicks "Check now"; client opens register URL (new tab) and prompts for evidence upload.
2. Optional screenshot captured via browser extension/mobile share and stored using upload endpoint.
3. Client calls `POST /watch-items/:id/evidence` with metadata.
4. Audit entry records actor, attachments, and note.

## 6. ICS format conventions
- `UID`: `trademarkId-reminderType` (e.g., `01HF...-renewal-180`).
- `SUMMARY`: `Renewal – {mark_name} – {client_name}`.
- `DESCRIPTION`: includes `Ref: {ref_no}`, `Link: {case_url}`, `Reminder offset: -180 days`.
- `DTSTART`: `due_at` in local timezone; `DTSTAMP` = generation time.
- `ORGANIZER`: optional email (if configured). For ICS downloads, user sets manually when importing into calendar.

## 7. Validation & error handling
- All POST/PATCH requests validated against shared Zod schemas compiled to JSON Schema for server (via `@anatine/zod-openapi`).
- Error format:
```
{
  error: {
    code: 'validation_error' | 'not_found' | 'conflict' | 'rate_limited' | 'internal',
    message: string,
    details?: Record<string, any>
  },
  correlation_id: string
}
```
- Client logs correlation ids in audit trail for traceability.

## 8. Data retention & deletion flows
- `DELETE /trademarks/:id` → status flips to `archived`; optional `hard=true` parameter allowed only when retention
  checks pass. Hard deletes cascade to documents (metadata only) and reminders.
- GDPR export: client requests `GET /compliance/export?scope=trademark&id=...` and receives zipped JSON manifest
  referencing external file paths (no binary copies). Audit entry logs request + purpose.
- GDPR erase: `POST /compliance/erase` with justification; server schedules job to redact personal data and append audit
  entry with outcome.

## 9. Versioning strategy
- API uses semantic versioning via URL prefix (`/api/v1`). Breaking changes require new version.
- Rule packs maintain monotonic `version` string (`eutm-2024-01`). Clients store last applied version and surface
  mismatch banners when server publishes newer versions.
- AI models identified by `model_version` (e.g., `tmhub-ocr-0.3`, `tmhub-ner-0.2-int8`). Stored in audit log for
  reproducibility.

