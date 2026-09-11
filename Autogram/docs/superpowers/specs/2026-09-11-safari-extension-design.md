# Safari Extension and Web Signing Design

Autogram macOS signs documents for Slovak state portals (slovensko.sk, financnasprava.sk, socpoist, ORSR, justice) from the browser, through our own lean Safari web extension that talks to the app over native messaging. No HTTP port is opened to the browser.

## Verified and unverified

**Verified by running it.** eForm and XDC signing is reachable from Swift over the machine protocol: a hermetic test builds a full `xdc:XMLDataContainer` with embedded schemas from a self-contained eForm (476 engine tests green, 0 failures). The extension reaches the app: `webbridge-probe` goes through the launchd agent to the running app and gets its status back, with no Safari involved.

**Verified in Safari on 2026-09-11.** The whole chain answers from a state portal: `await window.autogramMacOS.status()` on slovensko.sk returned `{ok: true, ready: false, version: "0.3.1"}`. So Safari does load a hand-assembled adhoc `.appex`, and `com.apple.security.temporary-exception.mach-lookup.global-name` does hold without a Team ID. One catch cost a round of debugging: pluginkit registers the extension without `CFBundleSupportedPlatforms`, `LSMinimumSystemVersion` and `CFBundleInfoDictionaryVersion`, but Safari will not list it. Xcode adds those; a hand-assembled bundle must set them itself.

**Measured on 2026-09-11.** No native-message size ceiling up to 16 MB, at better than 100 MB/s: 256 KB took 7 ms, 4 MB 36 ms, 16 MB 151 ms, measured from the page through the extension, the appex, the agent and into the app. The 80 ms on the first call is the launchd agent starting. Documents therefore travel inline and the file-handover design was dropped.

**Not built yet.** The D.Signer adapters, so slovensko.sk cannot drive signing through `window.ditec` yet; and the sign handler on the app side, so the bridge answers `ready: false` by design.

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
    -> launchd rendezvous agent, then straight to the app
    -> Autogram macOS (unsandboxed): cert pick, PIN, signing job
    -> engine helper over the machine protocol      (XDC built here)
    -> signed container back up the same chain
```

### Section 1: Extension scope

A lean fork of the official extension, EUPL-1.2, marked as a fork.

Kept: the ditec adapters (`dsig-base-adapter`, `dsig-xades-adapter`, `dsig-xades-bp-adapter`), the filetype strategies (xml, xml-bp, pdf, txt, png), `proxy.ts`, `inject-ditec.ts`, `supported-sites.ts`, and the inject/content/background entry points.

Dropped: the whole `injected-ui/` lit layer (PIN and certificate choice are native), Sentry, idb-keyval, the options page, manifest v2, interval injection, and the AVM client (signing with a phone already exists natively in `Signing/AVM/`).

Manifest v3. The only added permission is `nativeMessaging`. The background worker is the sole caller of native messaging; content scripts and injected code never touch it.

### Section 2: Appex to app bridge

Safari delivers `sendNativeMessage` to a sandboxed app extension inside our bundle. That extension cannot spawn the engine or reach PKCS#11, and the sandbox forbids connecting to an arbitrary XPC endpoint.

The first design here was for the app to publish `NSXPCListener(machServiceName:)` directly. **That does not work, and the spike proved it**: launchd owns Mach service names and hands the receive right only to the process it launches for the name, so the listener never registered and `launchctl print` did not know the service.

A small on-demand launchd agent owns the name instead and acts as a rendezvous. The app publishes an anonymous listener and registers its endpoint with the agent; the extension asks the agent for that endpoint and then connects to the app directly. No document passes through the agent, and connecting to an anonymous endpoint involves no name lookup, so the extension sandbox does not block it. The extension still needs `com.apple.security.temporary-exception.mach-lookup.global-name` to reach the agent, which needs neither a Team ID nor an app group and therefore holds under adhoc signing.

`scripts/install-webbridge-agent.sh` registers the agent; `build_app.sh` puts its binary in `Contents/Helpers`.

Fallback if the spike fails: an internal HTTP server bound to 127.0.0.1 on a random port with a shared token in a header, known only to our extension. That is still not an open door for arbitrary pages.

### Section 3: Document transport

Documents travel inline as base64 inside the message. The design originally routed anything above 256 KB through a file in the appex container, because the native-message ceiling is undocumented and reported to fail opaquely. Measurement removed the need: 16 MB crosses the whole chain in 151 ms with no ceiling reached, so the file path, its SHA-256 check, its path validation and its cleanup were all dropped as unnecessary machinery.

A cap stays worth having so a runaway page cannot wedge the app. Requests above 32 MB are refused with a clear message rather than attempted.

### Section 4: Engine and the machine protocol

Protocol v2 gains the eForm attributes it lacked, copied verbatim from `ServerSigningParameters` so the two entry points cannot drift: `containerXmlns`, `schema`, `transformation`, `identifier`, `autoLoadEform`, `fsFormId`, `embedUsedSchemas`, `packaging`, `transformationMediaDestinationTypeDescription`, `transformationLanguage`, `transformationTargetEnvironment`. `schema` and `transformation` are base64, as on the server. `signatureLevel` opens to the `_B` variants alongside the existing `_T` ones, because pages ask for `XAdES_BASELINE_B`.

`MachineSigningService` builds its `SigningParameters` through the same `SigningParameters.buildParameters(...)` that the HTTP `SignEndpoint` reaches, so `XDCBuilder` and the eForm resolvers are reused unchanged rather than reimplemented.

The fields are optional and the level set only widens, so nothing that worked before stops working. A parallel v3 was considered and rejected: the engine ships inside the app bundle, so there is no version skew to protect against, and a second protocol would have meant duplicating the whole v2 CLI app. Baseline B is accepted only when the request carries eForm attributes, which preserves the existing guarantee that ordinary file signing never emits an untimestamped signature.

eForm resolution reaches the network: a namespace under `schemas.gov.sk/form/`, `data.gov.sk/doc/eform/` or `data.gov.sk/id/egov/eform/` is looked up in the live UPVS registry, and ORSR and FS have their own resolvers. An unknown form fails with `UNKNOWN_EFORM`. Only a non-government namespace uses the schema and transformation supplied in the request. Tests therefore use a self-contained namespace and stay hermetic.

### Section 5: Signing UI

Browser-originated jobs reuse the existing `SigningSessionStore` certificate and PIN flow rather than introducing a second signing window. The request arrives, the app raises its existing signing surface, and the result travels back over XPC.

### Section 6: Out of scope for v1

The iPhone extension and AVM pairing (`/integrations`, `/sign-request`); Developer ID signing and notarization; visible signatures over the web, which the ditec surface has no field for and which are meaningless for XML eForms; a `_B` to `_T` upgrade policy; batch signing, which schránka needs but which is its own design; compatibility with the official published extension, which decision 3 rules out; and the `autogram://` scheme collision with the installed Java Autogram, which only mattered for the HTTP launch path.

## Testing

Machine protocol v3 gets a hermetic round-trip test that feeds a self-contained eForm through the Swift engine bridge and asserts a well-formed `xdc:XMLDataContainer` with embedded schemas. The existing v1 and v2 tests must stay green to prove the older paths did not regress. The extension keeps the upstream jest tests for the ditec adapters. The appex bridge is covered by the spike, not by unit tests, because its failure modes are all in the sandbox and in Safari.

## Status

Branch `feature/safari-extension`.

Done and tested: the eForm and XDC attributes over the machine protocol, with Baseline B accepted only for eForm requests so ordinary file signing still cannot produce an untimestamped signature; the launchd rendezvous, the XPC bridge, the hand-assembled appex, the build wiring, and a dependency-free extension skeleton.

Open: the D.Signer adapters; the sign handler that turns a portal request into a real signature through the existing certificate and PIN flow; and the Safari half of the spike.

Unrelated defect found on the way and fixed: `PDFAConverter.normalizeWithEngine` called `digital.slovensko.autogram.core.PdfaNormalize`, a class that had never existed in this fork, so engine-based PDF/A normalization always silently fell back. The normalizer is now implemented and covered by tests on both sides.
