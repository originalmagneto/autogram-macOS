// Background worker. The only place in the extension that talks to the native
// app: content scripts and injected page code never call sendNativeMessage.
//
// Transport is native messaging only. No HTTP, no localhost port, so a page can
// reach the signer only through this worker and only for the sites the manifest
// allows.

const NATIVE_APP = "sk.autogram.Autogram.WebExtension";

async function callNative(message) {
  try {
    const reply = await browser.runtime.sendNativeMessage(NATIVE_APP, message);
    if (!reply) {
      return { ok: false, error: "Autogram macOS neodpovedal." };
    }
    return reply;
  } catch (error) {
    return { ok: false, error: `Natívna správa zlyhala: ${error?.message ?? error}` };
  }
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
      return callNative({ kind: "sign", request: message.request });
    default:
      return Promise.resolve({ ok: false, error: `Neznámy typ správy: ${message?.kind}` });
  }
});
