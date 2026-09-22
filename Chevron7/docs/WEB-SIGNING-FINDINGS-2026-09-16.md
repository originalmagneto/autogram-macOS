# Web Signing and Card Signing Findings, 2026-09-16

Status: record of one working session on the Mac Studio, from a first local build of v0.4.0 to signing on nove.slovensko.sk with an I.CA card, an eID card and the phone.
Scope: what broke, the evidence that located each cause, the fix and its commit, what was verified on the real portal, and what is still open.

Commits: `6036eeb5` to `04698bbd` on `main`.

## Verified on the real portal (nove.slovensko.sk, by the user)

- Phone signing (Autogram v mobile, QR and NFC eID): the signed document returns to the portal page.
- I.CA card with the mandate certificate "OPRÁVNENIE": first signature and a second signature added to an already signed document (Asic join).
- eID card in a reader: signing completes, the BOK is typed in the eID client's window.
- Background launch: with Autogram macOS not running, a portal request starts it without a Dock icon or main window and the signing prompt appears over Safari.

Verified by the assistant without the portal: builds, unit tests, `webbridge-probe` (launch from not running, quit and relaunch), background launch and reopen behaviour through LaunchServices, the prompt layout and Quick Look on a 4-page PDF.

## Findings

### 1. Build toolchain: a beta SDK produced an app that crashed at launch

- Symptom: `Autogram macOS.app` 0.4.0 died at launch with dyld "Symbol not found" in FoundationModels (`Attachment.Image.Content(_:orientation:)`, used by `FoundationModelClassifier.swift`).
- Cause: two Xcode installs. `/Applications/Xcode-beta.app` was an older Xcode 27 beta (27A5194q, SDK 26A5353p). The release Xcode 27.0 (27A266a, SDK 26A425, matching macOS 27.0 26A428) sat in a folder still named `Xcode-26.5.app`, because the App Store updated it in place. The documented `DEVELOPER_DIR` pointed at the beta.
- Fix: the beta went to the Trash, the release was renamed to `/Applications/Xcode.app`, and every reference moved there, including the `build_app.sh` default (`6036eeb5`).
- Rule: never build with a beta SDK. On a launch crash with a missing system symbol, compare `xcrun --show-sdk-build-version` with `sw_vers`.

### 2. Card signing failed with SIGNING_UNAVAILABLE

- Symptom: "The machine request could not be completed. [SIGNING_UNAVAILABLE]", with PDF/A, a timestamp and a visible stamp or without them.
- Evidence: the engine hides the exception, so its stderr was captured and then every thrown exception was logged with `-Xlog:exceptions`. The failure was `NoSuchMethodError: MachineSettings.setEform(EFormRequest)` in `DefaultSessionFactory.apply`.
- Cause: `build_app.sh` patched the freshly built `autogram.jar` with `Assets/LegacyEnginePatches/MachineSettings.class`, compiled on 2026-09-01, before `setEform` existed (2026-09-11). The patch also defaulted the I.CA SecureStore slot to index 1, which the engine source lacked; the reader at index 0 is empty.
- Fix: the slot default moved into `MachineSettings.java` with a test, the class patch and its jar step were removed (`56e4c067`).

### 3. Phone signing: HTTP 503

The relay `autogram.slovensko.digital` answered 503 from nginx on every URL, including its root, while other hosts answered normally. An outage of the service, not an app defect. Nothing changed.

### 4. Portal PDFs need a XAdES ASiC-E container

- Symptoms: the phone relay answered 422 "PayloadMimeType, Parameters.Level, Parameters.Container and Parameters.Packaging mismatch"; a card signature came back to the portal as a PAdES PDF and the portal dialog hung.
- Cause: nove.slovensko.sk signs a PDF with `dSigXadesBpJs.addPdfObject` and `getSignatureWithASiCEnvelopeBase64`, which expects XAdES in ASiC-E. Upstream autogram-extension sends `container: "ASiC_E"`; `ditec.js` dropped it.
- Fix: `ditec.js` forwards the container, `WebSignRequest.wantsASiCContainer` drives level, container and returned payload on the card and phone paths (`4653258a`).

### 5. Safari lost the signed result

- Symptom: the app archived a signed `.asice`, but the page reported "Podpisovanie zlyhalo." or hung.
- Cause: Safari ends a web extension's background worker after about 30 seconds and then answers `runtime.sendNativeMessage` with `undefined`. A signature waits for a PIN or a phone far longer.
- Fix: `sign-begin` returns a job ID (`WebSignJobStore`) and the page polls `sign-result` every 1.5 s; a missing reply counts as the worker restarting (`c5708442`).

### 6. Card-signed containers held a nested container

- Symptom: the portal could not detach the PDF (500) or join a second signature (422 "Asic join failed", code 2120001).
- Evidence: containers from the card listed `kontajner.asice` instead of the PDF; phone containers held the PDF.
- Cause: the app packaged the PDF into an unsigned ASiC-E first and the engine wrapped that again.
- Fix: the engine receives the PDF under its real filename and builds the ASiC-E itself (`c0598c11`).
- Open: the main window's ASiC-E output still packages files the same way and probably nests too. Not verified.

### 7. Baseline B, the level portals ask for, was blocked three times over

The portal asks for `XAdES_BASELINE_B` and nove.slovensko.sk rejects a signature carrying a timestamp it did not ask for.

- The validators accepted Baseline B only for eForms (`99c487ce`, later widened to XAdES Baseline B on any source in `c0598c11`; PAdES Baseline B stays refused outside eForms).
- Machine protocol v1, used for card signing without eForm or visible stamp, ignored the requested level and always sent `XAdES_BASELINE_T`. With the timestamp switch off that failed as `TSA_REQUIRED`; with it on, the portal rejected the result (`8fdaa196`).
- The output check after signing demanded Baseline T with a valid timestamp for every signature, so Baseline B always ended as `OUTPUT_VALIDATION_FAILED` (`63249f4f`).
- The timestamp switch was remembered across requests; left on after a phone test it broke every later card signature (`e8895774`). On slovensko.sk the switch is no longer offered at all; the host comes from the content script, which the page cannot overwrite (`0a3a457c`).

Proof that the timestamp was the cause: the official Autogram 2.7.5 was asked to sign the same PDF with the same I.CA certificate through its local API (`POST http://127.0.0.1:37200/sign`, `XAdES_BASELINE_B`, `ASiC_E`). Its container differed from ours only by the `SignatureTimeStamp`.

### 8. The eID was very likely blocked by our change

- What happened: from `5dcb76a4` (about 12:00) to `99a26f14` (about 13:40) the web prompt stopped collecting the BOK for an eID and sent the engine a placeholder instead, on the assumption that eID tokens use the protected authentication path and ignore any PIN. The token flags confirmed that path for both slots (`Sig_ZEP`, `Sig_EP`), read without login.
- Why it still reached the card: `UserSettings.getForceContextSpecificLoginEnabled()` returns the bulk-mode flag, and the machine session always runs in bulk mode. `NativePkcs11SignatureToken` therefore performed a context-specific login with the app's PIN on every eID signature, protected path or not. The placeholder spent a BOK attempt each time, which matches the card being blocked that afternoon; after unblocking, the token reported no low retry count.
- Fixes: `MachineSecretUI` never hands out the placeholder (`99a26f14`, which turned the failure into `PasswordNotProvidedException` without touching the card), and machine mode no longer forces that login, so the eID client asks for the BOK in its own window as in the official Autogram (`74ff6279`).
- Lesson: checking token flags was not enough; the forced login path had to be read too.

### 9. The BOK window did not get the keyboard

- Cause: the eID PKCS#11 module inside the engine starts the eID client's `VirtualKeyboard` process, which is never activated, so keystrokes stayed in the floating prompt.
- Evidence: logging in `WebSigningPrompt` showed `activate(from:)` refused while Autogram was inactive and accepted once it was active.
- Fix: the prompt drops to normal level, activates `VirtualKeyboard` and orders itself just beneath that window so it stays visible above Safari (`74ff6279`, `56ea652c`).

### 10. Fewer BOK entries for the eID

Every certificate read from an eID opens the BOK window. The machine protocol now accepts `*` as the certificate serial, meaning the token's only key or its only non-repudiation key and never a guess between several (`ccbc80cc`). The web prompt no longer reads eID certificates, leaving the two BOK entries the card requires for a signature. I.CA cards still read their certificates with the PIN, and the prompt lists both certificates as rows (`8f89f709`).

### 11. Web signing in the background

Design and plan: `docs/superpowers/specs/2026-09-16-web-signing-background-design.md`, `docs/superpowers/plans/2026-09-16-web-signing-background.md`.

- The agent starts the app with `--web-signing` (`AppLaunchMode`); the app becomes an accessory app (`af92d07d`, `a595497d`).
- Suppressing the main window took three things together: `defaultLaunchBehavior(.suppressed)`, `restorationBehavior(.disabled)` and refusing `applicationShouldOpenUntitledFile`. Reopen from the Dock or Finder turns the app regular and creates the main window through the File > New Window command, because the suppressed scene does not come back on its own.
- The prompt is centered over Safari's front window, found by on-screen window bounds, which need no Screen Recording permission (`1b87fa03`, `80a75cc0`). It shows every PDF page and "Otvoriť náhľad" (Quick Look) (`56ea652c`, `f7f8c9ac`).

### 12. Why the extension needed Autogram open

Four separate causes, found one after another:

1. The agent remembered the endpoint of an app that had quit and launched the app only when no endpoint was known. Registrations are now tied to the app's connection (`WebBridgeEndpointRegistry`, `12505eeb`).
2. `build_app.sh` copied the bundle without registering the Safari extension, so Safari listed it only after the app first ran. The install step now registers it (`a369650f`).
3. Reinstalling while Safari runs injects the content script again into open pages (`Can't create duplicate variable 'CHANNEL_REQUEST'`) and leaves native messaging broken until Safari restarts. The script runs once per frame and the build warns to restart Safari (`63c5d415`).
4. Every launch through the agent makes LaunchServices register the bundle again, and the extension manager (`pkd`) then ends the running appex in the middle of the request: `SFErrorDomain error 3`. The background worker repeats the harmless status request up to four times, and the agent waits for an app that is already starting instead of opening it again, which would count as a reopen (`04698bbd`).

### 13. Official Autogram next to Autogram macOS

- Both apps claim the `autogram://` URL scheme (ours for the EZZK OAuth callback `autogram://ezzk/callback`), so a portal in "Autogram" mode opens Autogram macOS. Open: a separate scheme needs the EZZK administrator to allow a new redirect URI.
- The official Autogram reports "Kartu sa nepodarilo rozpoznať" (`TokenNotRecognizedException`) for I.CA SecureStore until its driver slot is set to 1 in its settings, the same empty reader at index 0 as in finding 2.

## Other changes in the session

- Sidebar: collapsible signed and recent documents with five rows and "Zobraziť všetky", card kind in the reader status, an opaque bottom bar (the list used to run through it), removal of a signed copy to the Trash, retention for browser copies after 7, 30 or 90 days (`fcd04802`).
- Web prompt: PIN field focus and certificate read on Return for PIN cards (`5dcb76a4`).

## Diagnostic techniques that worked

- In zsh `log` is a builtin; use `/usr/bin/log show`.
- A shell script cannot stand in for `AutogramCLI-arm64`: the app checks the helper for an arm64 Mach-O slice before it detects cards. A small compiled C wrapper that redirects stderr or sets `JAVA_TOOL_OPTIONS=-Xlog:exceptions=info:file=...` and then `execv`s the real helper works, and never sees the PIN on stdin.
- PKCS#11 token flags can be read without a session or login through `sun.security.pkcs11.wrapper` (`--add-modules jdk.crypto.cryptoki --add-exports jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED`).
- `webbridge-probe` exercises agent, launch and app without Safari; the Safari side needs the real browser.
- The official Autogram's local API gives a reference container for the same document and certificate.

## Build and test environment notes

- Engine JDK on the Mac Studio: Liberica 25.0.4 FX from sdkman, `AUTOGRAM_JAVA_HOME="$HOME/.sdkman/candidates/java/25.0.4.fx-librca"`.
- Engine machine tests (140) pass; several fail only when run from a path containing spaces, because tests resolve resources through URL paths (`%20`). Run them from a copy in a path without spaces.
- Swift tests (430) pass with `--skip SecurityElementsDetectorTests`, which times out after 60 s in `awaitAsync` on this machine, independent of these changes.

## Open items

1. `autogram://` URL scheme shared with the official Autogram (finding 13).
2. Main window ASiC-E output probably nests an unsigned container (finding 6).
3. The extension is not signed with Developer ID, so Safari turns "Allow unsigned extensions" off at every quit.
4. Automatic certificate reading in the web prompt stays out by choice; a possible later option.
