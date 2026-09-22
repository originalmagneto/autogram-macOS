// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

// Content script. Injects the page-context shim and relays its requests to the
// background worker, which is the only caller of native messaging.
//
// Safari injects content scripts again into pages that are already open when the
// extension is reloaded, for instance after Chevron7 is reinstalled. A second copy
// in the same isolated world failed on its `const` declarations, so the whole
// script runs once per frame.
(() => {
if (globalThis.__chevron7ContentScript) {
  return;
}
globalThis.__chevron7ContentScript = true;

console.log("[Chevron7] content script beží na", location.href);

const CHANNEL_REQUEST = "chevron7-request";
const CHANNEL_RESPONSE = "chevron7-response";

// ditec.js must land before the page script runs, so it is injected first and
// synchronously; inject.js only adds the direct window.chevron7 surface.
for (const file of ["ditec.js", "inject.js"]) {
  const script = document.createElement("script");
  script.src = browser.runtime.getURL(file);
  script.async = false;
  (document.head || document.documentElement).appendChild(script);
  script.remove();
}

// The per-site switch. Storage is async and the shim must win the race for
// window.ditec at document_start, so it always installs first and hands control
// back here if this site is switched off.
(async () => {
  try {
    const key = "siteDisabled:" + location.host;
    const stored = await browser.storage.local.get(key);
    const disabled = stored && stored[key] === true;
    window.dispatchEvent(new CustomEvent("chevron7-set-enabled", {
      detail: { enabled: !disabled }
    }));
    if (disabled) {
      console.log("[Chevron7] na tejto stránke vypnuté, ponechávam pôvodný D.Signer");
    }
  } catch (error) {
    console.error("[Chevron7] nepodarilo sa načítať nastavenie stránky", error);
  }
})();

browser.runtime.onMessage.addListener((message) => {
  if (message?.kind !== "site-enabled-changed") return;
  window.dispatchEvent(new CustomEvent("chevron7-set-enabled", {
    detail: { enabled: message.enabled }
  }));
  return Promise.resolve({ ok: true });
});

window.addEventListener(CHANNEL_REQUEST, async (event) => {
  const detail = event.detail || {};
  // Safari may have ended the background worker, which rejects the message or
  // answers undefined. The page always gets an answer so it can retry.
  // The page builds the request, so it could claim any origin. The host is set
  // here from the content script's own location, overwriting whatever it sent.
  let request = detail.request;
  if ((detail.kind === "sign" || detail.kind === "sign-begin") && typeof request === "string") {
    try {
      const parsed = JSON.parse(request);
      parsed.pageHost = location.hostname;
      request = JSON.stringify(parsed);
    } catch (error) {
      console.warn("[Chevron7] požiadavku na podpis sa nepodarilo doplniť o adresu stránky", error);
    }
  }
  let reply;
  try {
    reply = await browser.runtime.sendMessage({
      kind: detail.kind,
      request: request
    });
  } catch (error) {
    console.warn("[Chevron7] správa pre pozadie rozšírenia zlyhala", error);
    reply = undefined;
  }
  window.dispatchEvent(new CustomEvent(CHANNEL_RESPONSE, {
    detail: { id: detail.id, reply }
  }));
});

})();
