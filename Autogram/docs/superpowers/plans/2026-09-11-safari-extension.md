# Safari Extension Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-11-safari-extension-design.md`

**Goal:** Sign documents on Slovak state portals from the browser, through our own Safari web extension and native messaging, with the eForm and XDC pipeline reachable from Swift.

**Branch:** `feature/safari-extension`

Written compactly rather than through the full writing-plans ceremony: the user asked for working code by morning and is asleep, so plan depth was traded for implementation time. Tasks are ordered so that the highest-value, fully verifiable work lands first.

## Global constraints

- Toolchain Xcode 27 beta; every build and test needs `DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"`.
- Code, comments and docs in English; end-user strings in Slovak.
- No em dashes anywhere.
- Keep `AGENTS.md` and `CLAUDE.md` in sync.
- Commit after each green task with the `Co-Authored-By: Claude Opus 5` trailer. Never commit to `main`.
- Machine protocol v1 and v2 must stay accepted; the card flow, Quick Action and CLI keep working.

## Task order and rationale

Task 1 is the only work that is both fully verifiable tonight and the actual blocker for eForms, so it goes first. The Safari half cannot be verified without the user enabling "Allow Unsigned Extensions", which is a per-launch, in-memory Safari setting with no preference key, so it is scaffolded and handed over with a spike script.

- [ ] **Task 1: Machine protocol v3 eForm attributes (Java)**
  `engine/protocol/v3/schema/request.schema.json` plus `MachineRequest`, `MachineRequestValidator`, `MachineProtocolCodec` and `MachineSigningService`. Fields copied verbatim from `ServerSigningParameters`; `schema` and `transformation` base64; `signatureLevel` opened to the `_B` variants. `MachineSigningService` must reach the same `SigningParameters.buildParameters(...)` the HTTP `SignEndpoint` uses so `XDCBuilder` is reused, not reimplemented.

- [ ] **Task 2: Machine protocol v3 in Swift**
  `MachineProtocolV3Models.swift` mirroring the Java payload, wired through `AutogramCLIEngine` and `ProcessConfiguration`. v2 call sites keep working unchanged.

- [ ] **Task 3: Hermetic end-to-end eForm test**
  A self-contained (non-government) namespace fixture so no UPVS registry lookup happens. Feed it through Swift to the engine and assert a well-formed `xdc:XMLDataContainer` with embedded schemas comes back. This is the proof that eForm signing is reachable from Swift.

- [ ] **Task 4: XPC bridge in the app**
  `NSXPCListener(machServiceName: "sk.autogram.Autogram.xpc")` plus the request and response types, routing browser-originated jobs into the existing `SigningSessionStore` certificate and PIN flow. No new signing window.

- [ ] **Task 5: Appex scaffold and build wiring**
  A hand-assembled `.appex` in `Contents/PlugIns` with `NSExtensionPointIdentifier` `com.apple.Safari.web-extension`, an entitlements plist carrying `com.apple.security.temporary-exception.mach-lookup.global-name`, and the `build_app.sh` steps to assemble and adhoc-sign it.

- [ ] **Task 6: Lean extension fork**
  Scope per spec section 1. Manifest v3, `nativeMessaging` permission, background worker as the only native caller.

- [ ] **Task 7: Safari spike script**
  `scripts/safari-spike.sh`: build and install, then print exactly what to check. Answers the three unknowns (does Safari load the adhoc appex, does the mach-lookup exception hold, what is the message size ceiling) in one run once the user enables "Allow Unsigned Extensions".

## Out of scope

iPhone and AVM pairing; Developer ID and notarization; visible signatures over the web; `_B` to `_T` upgrade policy; batch signing; compatibility with the official published extension; persistent engine process; the `autogram://` collision.
