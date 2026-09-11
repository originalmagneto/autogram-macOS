// Page-context shim.
//
// State portals drive signing through the Ditec D.Signer object at
// `window.ditec`. This file owns that surface and forwards to the content
// script, which reaches the app through the background worker.
//
// Scope note: the full D.Signer surface (dSigXadesJs and dSigXadesBpJs with the
// per-filetype strategies) is not ported yet. What is here is the transport and
// the object shape; the adapters are the remaining task, and the upstream
// EUPL-1.2 implementations in slovensko-digital/autogram-extension under
// src/dbridge_js/ditecx are the reference to port from.

(function () {
  const CHANNEL_REQUEST = "autogram-macos-request";
  const CHANNEL_RESPONSE = "autogram-macos-response";

  let counter = 0;
  const pending = new Map();

  window.addEventListener(CHANNEL_RESPONSE, (event) => {
    const { id, reply } = event.detail || {};
    const resolve = pending.get(id);
    if (!resolve) return;
    pending.delete(id);
    resolve(reply);
  });

  function call(kind, request) {
    const id = `autogram-${Date.now()}-${counter++}`;
    return new Promise((resolve) => {
      pending.set(id, resolve);
      window.dispatchEvent(new CustomEvent(CHANNEL_REQUEST, {
        detail: { id, kind, request }
      }));
    });
  }

  const autogram = {
    isAutogram: true,

    /** Whether Autogram macOS is running and ready to sign. */
    async status() {
      return call("status", null);
    },

    /**
     * Signs one document.
     *
     * `request` matches WebSignRequest in the app: requestID, filename,
     * content (base64), payloadMimeType, signatureLevel and optional eform.
     */
    async sign(request) {
      return call("sign", JSON.stringify(request));
    }
  };

  // Exposed for the spike and for pages that integrate directly rather than
  // through the D.Signer surface.
  Object.defineProperty(window, "autogramMacOS", {
    value: Object.freeze(autogram),
    writable: false,
    configurable: false
  });
})();
