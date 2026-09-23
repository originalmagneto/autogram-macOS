# OpenSC as a signing driver

Status (2026-09-23): **prepared, not verified on a card.** The work lives on the branch `feature/opensc-driver`. It must not reach `main` before a real card has signed through it: every push to `main` with a `feat` or `fix` commit publishes a release (`.github/workflows/release.yml`), so merging this branch ships it to users.

The goal is a second, open-source route to the card next to the vendor middleware. For the Slovak eID it could replace the eID klient; for other cards it could replace proprietary drivers. The eID klient stays the preferred driver until the open questions below are answered.

## What OpenSC is (verified)

| Fact | Source |
|---|---|
| Open-source smart card middleware (PKCS#11 module, Windows minidriver, macOS CryptoTokenKit token), LGPL-2.1, actively maintained | https://github.com/OpenSC/OpenSC |
| Latest release 0.27.1 (2026-03-31), ships `OpenSC-0.27.1.dmg` for macOS | https://github.com/OpenSC/OpenSC/releases |
| The macOS installer puts the PKCS#11 module in `/Library/OpenSC/lib/opensc-pkcs11.so` (copies in `/usr/local/lib`) and installs the CryptoTokenKit plugin (OpenSCToken) for native apps | https://github.com/OpenSC/OpenSC/wiki/macOS-Quick-Start |
| Slovak eID driver `card-skeid.c` and emulator `pkcs15-skeid.c`, added 2023-03-22 (PR #2672, Juraj Šarinay), last touched 2026-04-24 | `src/libopensc/card-skeid.c`, `src/libopensc/pkcs15-skeid.c` in the OpenSC repo |

What the skeid driver declares (read from the source, not tested):

- It matches exactly one ATR, `3b:d2:18:00:81:31:fe:58:c9:04:11` ("Slovak eID v3, CardOS 5.4"), and then checks the card's CIF URL `http://www.minv.sk/cif/cif-sk-eid-v3.xml`. Other card generations are not matched.
- Three certificates: "Kvalifikovany certifikat pre elektronicky podpis", "Certifikat pre elektronicky podpis", "Sifrovaci certifikat".
- Two PINs: `BOK` (reference 0x03, path `3F00`, max 6 digits, 5 tries) and `Podpisovy PIN` (reference 0x87, path `3F000101`, local, max 10 digits, 3 tries).
- Three RSA 3072 keys. `Podpisovy kluc (KEP)` (non-repudiation + sign) is guarded by the **Podpisový PIN** and has `user_consent = 1`, which OpenSC exposes as `CKA_ALWAYS_AUTHENTICATE`. The other signing key and the decryption key are guarded by the BOK.
- Signing uses `MSE RESTORE`, following the vendor driver; algorithms RSA PKCS#1 v1.5 without hashing on card. The driver has no PACE code, so it reaches the card only through a contact reader, never over NFC.

## What this branch changes

- **Engine** (`engine/src/main/java/digital/slovensko/autogram/core/DefaultDriverDetector.java`): a macOS driver `OpenSC` (shortname `opensc`) whose module is the first present of `/Library/OpenSC/lib/opensc-pkcs11.so`, `/opt/homebrew/lib/opensc-pkcs11.so`, `/usr/local/lib/opensc-pkcs11.so`. It is listed after the vendor drivers and is offered only when the module exists. Test: `DefaultDriverDetectorOpenSCTest`.
- **App fallback** (`Chevron7/Sources/Chevron7Kit/Signing/PKCS11Module.swift`): the installer paths join `candidatePaths`. This list is used only by `pkcs11-helper`, which runs only when the bundled engine is missing (`SigningProviderFactory.makeDefault()` prefers the engine), so this change matters for the no-engine fallback only.
- **Diagnostics** (`Chevron7/scripts/opensc-check.sh`): readers, ATR, matched driver, PKCS#11 slots and public objects, PKCS#15 PIN objects with tries left, the CryptoTokenKit view and what the engine detects. It never logs in and never sends a PIN or BOK.

Deliberately **not** done, because each depends on how the card really behaves:

- Two secrets in the machine protocol. Today v1 and v2 sign requests carry exactly one non-blank `pin` (`MachineCliApp.requiredSignRequest`, `MachineV2RequestValidator.validateSign`), and `MachineSecretUI` hands the same value to `CKU_USER` login and to the `CKU_CONTEXT_SPECIFIC` login in `NativePkcs11SignatureToken.runContextSpecificLoginIfNeeded`.
- Choosing the slot that holds the KEP key. `PKCS11TokenDriver.createToken` takes the first slot with a token (`PKCS11TokenPresenceProbe.firstTokenSlotIndex`).
- Bundling OpenSC in `Chevron7.app`, any UI, and the CryptoTokenKit route.

## How the app would use OpenSC today

1. The engine lists drivers in the order of `getMacDrivers()`. The app (`EngineBridgeSigningProvider.resolveIdentities` and `sign`) takes the `eid` driver when it has a token, otherwise the first driver with a token. With the eID klient installed, an eID card therefore still goes through the eID klient; OpenSC is used when no earlier driver claims the card.
2. `EngineBridgeSigningProvider.requiresPIN(driverID:)` is true for every driver except `eid`, so for `opensc` the app asks for a PIN in its own field (the I.CA route), not in the eID klient's window.
3. The engine sends that single PIN to `C_Login(CKU_USER)` on the first token slot and, because the KEP key has `CKA_ALWAYS_AUTHENTICATE`, again to `C_Login(CKU_CONTEXT_SPECIFIC)`.

**Hypothesis to verify, not a conclusion:** if OpenSC creates one virtual slot per PIN, the first slot is the BOK slot, which does not hold the KEP key, and one PIN cannot be both the BOK and the Podpisový PIN. Then the engine needs a slot choice and possibly a second secret. Research prompts B and C decide this.

## Safety rules for testing on a real card

- The Podpisový PIN has **3 tries** and the BOK **5** (as declared by `pkcs15-skeid.c`; check the real counters with `opensc-check.sh`, section "PKCS#15 view"). A blocked PIN has to be unblocked with the PUK; find out how (eID klient or a police office) before the first test.
- Order: `opensc-check.sh` (no PIN) → one manual `pkcs11-tool` signature with the PIN typed by hand → only then the engine and the app. Never test with the app first, never put a PIN in a script or a loop, and stop after the first wrong-PIN error.
- Check tries left before and after every attempt that sends a PIN.
- Close the eID klient during OpenSC tests, or record that it was running (prompt D).

## Test plan

1. The owner installs `OpenSC-0.27.1.dmg` (or newer) from the OpenSC releases page. Not automated on purpose: it installs a system-wide driver and a CryptoTokenKit plugin.
2. Insert the eID into a contact reader and run:
   ```bash
   Chevron7/scripts/opensc-check.sh 2>&1 | tee opensc-check.log
   ```
   Record the ATR, the matched driver (`skeid` expected), the slot list with labels, which slot lists the KEP certificate, and tries left for both PINs.
3. One manual signature of test data with the KEP key (prompts the PIN interactively; replace `<slot>` and `<id>` from step 2):
   ```bash
   printf 'chevron7 opensc test' > /tmp/opensc-data.txt
   pkcs11-tool --module /Library/OpenSC/lib/opensc-pkcs11.so --slot <slot> --login --sign --mechanism SHA256-RSA-PKCS --id <id> -i /tmp/opensc-data.txt -o /tmp/opensc-data.sig
   ```
   Note which PIN it asked for and whether it asked twice (user login and context-specific login). Verify the signature with the certificate read in step 2 (`pkcs11-tool --read-object --type cert --id <id>`, then `openssl dgst -sha256 -verify` with the extracted public key).
4. Build the engine and the app from this branch without installing over `/Applications`:
   ```bash
   cd Chevron7
   scripts/build-engine.sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build_app.sh
   open "$(swift build --show-bin-path)/Chevron7.app"
   ```
   `opensc-check.sh` should now show an `opensc` entry in the engine's DRIVERS output. The app still prefers the eID klient when it sees the card, so to exercise OpenSC in the app, quit the eID klient and move `/Applications/eID_klient.app` aside for the test (put it back afterwards). Only after step 3 worked, try one signature in the app.

## Research prompts

Each prompt is self-contained: paste it into a fresh session in this repository. Write the answer back into this file (section "Findings") with sources and the date, and turn verified facts into tasks.

### A. Which eID generations does OpenSC recognise?

> Context: Chevron7 (this repo) wants to sign with the Slovak eID through OpenSC. OpenSC's `src/libopensc/card-skeid.c` matches only ATR `3b:d2:18:00:81:31:fe:58:c9:04:11` (eID v3, CardOS 5.4) plus the CIF URL `http://www.minv.sk/cif/cif-sk-eid-v3.xml`. Question: which Slovak identity card generations with the electronic chip are in circulation today (issue dates, chip platform, ATR), and which of them this driver matches? Check OpenSC issues and PRs mentioning skeid or Slovak eID, the minv.sk eID documentation, and slovensko.sk / slovensko.digital sources. If a card is at hand, `opensc-tool --atr` gives its ATR. Output: a table generation → chip → ATR → matched by skeid (yes/no/unknown), with sources.

### B. Slot layout and where the KEP key lives

> Context: see `Chevron7/docs/OPENSC-INTEGRATION.md` and `engine/src/main/java/digital/slovensko/autogram/drivers/PKCS11TokenDriver.java` (it picks the first slot with a token via `PKCS11TokenPresenceProbe.firstTokenSlotIndex`). Question: with OpenSC's default configuration on macOS, how many PKCS#11 slots does a Slovak eID v3 produce, what are their token labels, and which slot exposes the KEP private key (`Podpisovy kluc (KEP)`) and certificate? Read OpenSC's `src/pkcs11/framework-pkcs15.c` (`create_slots_for_pins`, virtual slots per PIN) and `etc/opensc.conf` defaults, and compare with `onepin-opensc-pkcs11.so`. If a card is at hand, confirm with `pkcs11-tool --module /Library/OpenSC/lib/opensc-pkcs11.so -L` and `-O --slot <id>` (no login). Output: the slot table and a recommendation for how `PKCS11TokenDriver` should choose the slot for the `opensc` driver.

### C. PIN sequence for a KEP signature

> Context: `pkcs15-skeid.c` guards the KEP key with the Podpisový PIN (reference 0x87, 3 tries) and sets `user_consent = 1` (CKA_ALWAYS_AUTHENTICATE); the other keys use the BOK (reference 0x03, 5 tries). Chevron7's engine sends one secret both to `C_Login(CKU_USER)` and to `C_Login(CKU_CONTEXT_SPECIFIC)` (`NativePkcs11SignatureToken.runContextSpecificLoginIfNeeded`, `ui/machine/MachineSecretUI.java`). Question: to produce a KEP signature through OpenSC, which secrets must be verified and in which order: only the Podpisový PIN, or the BOK first and then the Podpisový PIN? Does the card require the BOK to be verified in the same session before the Podpisový PIN? Read OpenSC's skeid sources and its PKCS#11 login code, the eID klient documentation from minv.sk, and upstream Autogram's handling of the eID. Do not answer by trying PINs on a card. Output: the exact PKCS#11 call sequence, and whether Chevron7's machine protocol needs a second secret field (and its name) for the `opensc` driver.

### D. eID klient and OpenSC side by side

> Context: Chevron7's engine probes every installed driver for a token (`PKCS11TokenPresenceProbe`) and prefers the eID klient (`driver id eid`). Question: can the eID klient (`/Applications/eID_klient.app`, `libPkcs11.dylib`) and OpenSC (`opensc-pkcs11.so` plus the OpenSCToken CryptoTokenKit plugin) be installed together on macOS and access the same eID over PC/SC without exclusive-access conflicts, stale sessions or one of them blocking the other? Look for reports in OpenSC issues, the eID klient FAQ and slovensko.digital forums. Output: known conflicts and a recommended test procedure.

### E. Other cards Chevron7 users sign with

> Context: besides the eID, Chevron7 users sign with I.CA cards (SecureStore middleware), Disig cards, SAK advocate cards and Gemalto IDPrime 940 (see `getMacDrivers()` in `engine/src/main/java/digital/slovensko/autogram/core/DefaultDriverDetector.java`). Question: for each of these, which chip and applet is used, and does OpenSC 0.27+ support it for qualified signing (driver name, known limitations)? Use OpenSC's `src/libopensc/card-*.c`, its wiki page "Supported hardware (smart cards and USB tokens)", and the vendors' documentation. If a card is at hand, `opensc-tool --name` shows the matched driver. Output: a table card → chip → OpenSC driver → qualified signing possible (yes/no/unknown) → notes.

### F. Bundling OpenSC in Chevron7.app

> Context: Chevron7 is EUPL-1.2, ad hoc signed, distributed as a DMG (`Chevron7/scripts/package-release.sh`), arm64 only, macOS 27+. Question: can OpenSC's PKCS#11 module be shipped inside `Chevron7.app` (for example `Contents/Frameworks`) so users need no separate install? Cover: LGPL-2.1 obligations (notice, source offer, relinking) and compatibility with EUPL-1.2; what `opensc-pkcs11.so` loads at runtime (`libopensc`, `opensc.conf`, hardcoded `/Library/OpenSC` paths, `OPENSC_CONF`); building it for arm64 in GitHub Actions on the `xcode-27` runner; code signing and library validation when an ad hoc signed app loads it via SunPKCS11 in the bundled Java runtime. Output: a go/no-go with the concrete steps and the files `build_app.sh` would have to add.

### G. CryptoTokenKit route

> Context: `SigningProviderFactory.makeDefault()` in `Chevron7/Sources/Chevron7Kit/Signing/SigningProvider.swift` uses the bundled engine when present, otherwise `KeychainXAdESSigningProvider` if the Keychain holds an identity with a private key; `CardPresenceMonitor` watches `TKTokenWatcher`. The OpenSC installer adds the OpenSCToken CryptoTokenKit plugin. Question: with OpenSC installed, does a Slovak eID appear as a Keychain identity (`security list-smartcards`, `sc_auth identities`, `system_profiler SPSmartCardsDataType`), which of its keys, and how does macOS ask for the BOK and the Podpisový PIN for `SecKeyCreateSignature`? Could this replace the Java engine for eID signing, and does it change what `CardPresenceMonitor` reports? Output: observed behaviour and a recommendation.

### H. pkcs11-spy for the drivers we already use

> Context: `Chevron7/docs/WEB-SIGNING-FINDINGS-2026-09-16.md` and `docs/PHASES.md` record PKCS#11 problems with the eID klient (a module that reported 0 slots, BOK handling) and I.CA SecureStore (slot choice). OpenSC ships `pkcs11-spy.so`, which wraps a real module (`PKCS11SPY=<module>`, `PKCS11SPY_OUTPUT=<log>`) and logs every call. Question: how to run Chevron7's engine (`Chevron7/.build/engine/Contents/Helpers/AutogramCLI-arm64`, machine protocol v1, see `engine/protocol/v1`) and `pkcs11-tool` through `pkcs11-spy` on macOS arm64, and what is the smallest engine change (for example an environment variable in `DefaultDriverDetector`) that routes a chosen driver through the spy for diagnostics only? Output: the commands and the proposed change, with the logs redacted of PINs.

### I. Qualified status with third-party middleware

> Context: a qualified electronic signature (KEP) under eIDAS needs a qualified certificate and a qualified signature creation device (QSCD). Question: does creating the signature through OpenSC instead of the eID klient affect whether a signature made with the Slovak eID counts as qualified? Check the QSCD certification of the Slovak eID (what exactly is certified: chip, applet, middleware), the EU list of certified QSCDs, the minv.sk terms of use of the eID, and any statement from NBÚ or slovensko.sk. Output: a short answer with sources, and any wording Chevron7 must show to users.

## Findings

(Empty. Add dated findings with sources here.)
