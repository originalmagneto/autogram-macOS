// Background worker. The only place in the extension that talks to the native
// app: content scripts and injected page code never call sendNativeMessage.
//
// Transport is native messaging only. No HTTP, no localhost port, so a page can
// reach the signer only through this worker and only for the sites the manifest
// allows.

const NATIVE_APP = "sk.autogram.Autogram.WebExtension";

// A status request starts Autogram when it is not running. macOS then registers
// the app again, and the extension manager ends this extension's native handler in
// the middle of the request (SFErrorDomain error 3). The status request changes
// nothing, so it is sent again once the app is up. Signing requests are never
// repeated: one that reached the app must not raise a second prompt.
const STATUS_ATTEMPTS = 4;
const STATUS_RETRY_DELAY_MS = 1500;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function callNative(message) {
  const attempts = message?.kind === "status" ? STATUS_ATTEMPTS : 1;
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const reply = await browser.runtime.sendNativeMessage(NATIVE_APP, message);
      if (!reply) {
        return { ok: false, error: "Autogram macOS neodpovedal." };
      }
      return reply;
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        await delay(STATUS_RETRY_DELAY_MS);
      }
    }
  }
  return { ok: false, error: `Natívna správa zlyhala: ${lastError?.message ?? lastError}` };
}

browser.runtime.onMessage.addListener((message, sender) => {
  // Only our own content scripts may reach the app.
  if (!sender || sender.id !== browser.runtime.id) {
    return Promise.resolve({ ok: false, error: "Neoprávnený odosielateľ." });
  }

  switch (message?.kind) {
    case "status":
      return callNative({ kind: "status" });
    case "sign":
    case "sign-begin":
    case "sign-result":
      return callNative({ kind: message.kind, request: message.request });
    default:
      return Promise.resolve({ ok: false, error: `Neznámy typ správy: ${message?.kind}` });
  }
});
