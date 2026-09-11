// Content script. Injects the page-context shim and relays its requests to the
// background worker, which is the only caller of native messaging.

console.log("[Autogram macOS] content script beží na", location.href);

const CHANNEL_REQUEST = "autogram-macos-request";
const CHANNEL_RESPONSE = "autogram-macos-response";

// ditec.js must land before the page script runs, so it is injected first and
// synchronously; inject.js only adds the direct window.autogramMacOS surface.
for (const file of ["ditec.js", "inject.js"]) {
  const script = document.createElement("script");
  script.src = browser.runtime.getURL(file);
  script.async = false;
  (document.head || document.documentElement).appendChild(script);
  script.remove();
}

window.addEventListener(CHANNEL_REQUEST, async (event) => {
  const detail = event.detail || {};
  const reply = await browser.runtime.sendMessage({
    kind: detail.kind,
    request: detail.request
  });
  window.dispatchEvent(new CustomEvent(CHANNEL_RESPONSE, {
    detail: { id: detail.id, reply }
  }));
});
