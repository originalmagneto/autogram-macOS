# Safari Extension and Web Signing Design

Autogram macOS signs documents for Slovak state portals (slovensko.sk, financnasprava.sk, socpoist, ORSR, justice) from the browser, through our own lean Safari web extension that talks to the app over native messaging. No HTTP port is opened to the browser.

## Verified and unverified

Filled in at the end of the implementation session. See "Status" at the bottom.

## Background

The official `slovensko-digital/autogram-extension` replaces `window.ditec` on state portals with a shim and forwards signing to the Java Autogram over `http://localhost:37200` (`/info`, `/sign`, `/batch`). That server has `Access-Control-Allow-Origin: *` and verifies neither the `key` nor the `nonce` the launch URL carries, so while the signer runs any page can post a document to it.

Our fork already bundles the whole Java engine, including the eForm and XDC pipeline (`XDCBuilder`, `EFormResourcesBuilder`, and the UPVS, ORSR and FS resolvers) and the HTTP server classes. A spike on 2026-09-11 proved `AutogramServer` runs headless out of the shipped bundle and builds a complete `xdc:XMLDataContainer` from an eForm request. What the Swift app cannot do is reach that pipeline: machine protocol v2 carries only `driver, certificateSerial, pin, files, signatureLevel, timestamp`, and `signatureLevel` is limited to the `_T` levels.

## Decisions

Taken with the user on 2026-09-11.

1. Build our own Safari extension rather than serving the published official one.
2. No Apple Developer Program for now. The extension runs unsigned under Safari's "Allow Unsigned Extensions"; Developer ID and notarization are added later without touching the architecture.
3. Native messaging only. No HTTP server is exposed to the browser.
4. The engine stays one process per operation for v1. A persistent engine session is a follow-up, not part of this spec.

Decision 4 supersedes the earlier "persistent engine" answer for v1 scope only: the protocol work below is identical either way, and changing the process lifecycle in the same change would couple two unrelated risks.

## Architecture

```
slovensko.sk page
  window.ditec.dSigXadesJs.sign(...)
    -> content script + injected ditec shim        (our lean fork)
    -> extension background worker                  (only place that calls native)
    -> browser.runtime.sendNativeMessage
    -> SafariWebExtensionHandler (.appex, sandboxed, in our bundle)
    -> NSXPCConnection to a Mach service
    -> Autogram macOS (unsandboxed): cert pick, PIN, signing job
    -> engine helper over machine protocol v3      (XDC built here)
    -> signed container back up the same chain
```

### Section 1: Extension scope

A lean fork of the official extension, EUPL-1.2, marked as a fork.

Kept: the ditec adapters (`dsig-base-adapter`, `dsig-xades-adapter`, `dsig-xades-bp-adapter`), the filetype strategies (xml, xml-bp, pdf, txt, png), `proxy.ts`, `inject-ditec.ts`, `supported-sites.ts`, and the inject/content/background entry points.

Dropped: the whole `injected-ui/` lit layer (PIN and certificate choice are native), Sentry, idb-keyval, the options page, manifest v2, interval injection, and the AVM client (signing with a phone already exists natively in `Signing/AVM/`).

Manifest v3. The only added permission is `nativeMessaging`. The background worker is the sole caller of native messaging; content scripts and injected code never touch it.

### Section 2: Appex to app bridge

Safari delivers `sendNativeMessage` to a sandboxed app extension inside our bundle. That extension cannot spawn the engine or reach PKCS#11, and the sandbox forbids connecting to an arbitrary XPC endpoint.

The app registers `NSXPCListener(machServiceName: "sk.autogram.Autogram.xpc")`. The appex holds `com.apple.security.temporary-exception.mach-lookup.global-name` for that name, which needs neither a Team ID nor an app group, so it should hold under adhoc signing. The appex stays as thin as the Xcode echo template plus one XPC call.

Three unknowns ride on this: whether Safari loads a hand-assembled adhoc appex, whether the exception entitlement holds without a team, and what the native-message size ceiling is. They are settled by one spike before any message format is designed.

Fallback if the spike fails: an internal HTTP server bound to 127.0.0.1 on a random port with a shared token in a header, known only to our extension. That is still not an open door for arbitrary pages.

### Section 3: Document transport

Documents are megabytes and the native-message ceiling is undocumented. Payloads above 256 KB travel as files, not inline: the sender writes to a temporary file and the message carries the path plus a SHA-256 digest. Below that threshold the content stays inline as base64, which keeps the common eForm case a single round trip.

The appex is sandboxed and the app is not, so the file lives in the appex container (`~/Library/Containers/<appex-id>/Data/tmp`), which the appex may write and the unsandboxed app may read. Every file is removed once the response is delivered, and the app rejects any path outside that directory.

### Section 4: Engine and machine protocol v3

Protocol v3 adds the eForm attributes that v2 lacks, copied verbatim from `ServerSigningParameters` so the two entry points cannot drift: `containerXmlns`, `schema`, `transformation`, `identifier`, `autoLoadEform`, `fsFormId`, `embedUsedSchemas`, `packaging`, `transformationMediaDestinationTypeDescription`, `transformationLanguage`, `transformationTargetEnvironment`. `schema` and `transformation` are base64, as on the server. `signatureLevel` opens to the `_B` variants alongside the existing `_T` ones, because pages ask for `XAdES_BASELINE_B`.

`MachineSigningService` builds its `SigningParameters` through the same `SigningParameters.buildParameters(...)` that the HTTP `SignEndpoint` reaches, so `XDCBuilder` and the eForm resolvers are reused unchanged rather than reimplemented.

v1 and v2 stay accepted so the existing card flow, the Quick Action and the CLI keep working.

eForm resolution reaches the network: a namespace under `schemas.gov.sk/form/`, `data.gov.sk/doc/eform/` or `data.gov.sk/id/egov/eform/` is looked up in the live UPVS registry, and ORSR and FS have their own resolvers. An unknown form fails with `UNKNOWN_EFORM`. Only a non-government namespace uses the schema and transformation supplied in the request. Tests therefore use a self-contained namespace and stay hermetic.

### Section 5: Signing UI

Browser-originated jobs reuse the existing `SigningSessionStore` certificate and PIN flow rather than introducing a second signing window. The request arrives, the app raises its existing signing surface, and the result travels back over XPC.

### Section 6: Out of scope for v1

The iPhone extension and AVM pairing (`/integrations`, `/sign-request`); Developer ID signing and notarization; visible signatures over the web, which the ditec surface has no field for and which are meaningless for XML eForms; a `_B` to `_T` upgrade policy; batch signing, which schránka needs but which is its own design; compatibility with the official published extension, which decision 3 rules out; and the `autogram://` scheme collision with the installed Java Autogram, which only mattered for the HTTP launch path.

## Testing

Machine protocol v3 gets a hermetic round-trip test that feeds a self-contained eForm through the Swift engine bridge and asserts a well-formed `xdc:XMLDataContainer` with embedded schemas. The existing v1 and v2 tests must stay green to prove the older paths did not regress. The extension keeps the upstream jest tests for the ditec adapters. The appex bridge is covered by the spike, not by unit tests, because its failure modes are all in the sandbox and in Safari.

## Status

To be completed at the end of the implementation session.
