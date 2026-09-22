// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

// Per-site switch. Turning this off hands the page back to whatever D.Signer it
// would have used on its own, typically Ditec D.Bridge 2, without disabling the
// whole extension. The shim defines window.ditec for good once it is in the
// page, so the switch takes effect on the next load and the popup reloads the tab.

const hostLabel = document.getElementById("host");
const toggle = document.getElementById("enabled");
const note = document.getElementById("note");
const status = document.getElementById("status");

let currentTab = null;
let currentHost = null;

function keyFor(host) {
  return "siteDisabled:" + host;
}

function renderNote() {
  note.textContent = toggle.checked
    ? "Podpisovanie na tejto stránke preberá Chevron7."
    : "Stránka použije svoj pôvodný D.Signer (napríklad D.Bridge 2).";
}

async function load() {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  currentTab = tabs && tabs[0];
  if (!currentTab || !currentTab.url) {
    hostLabel.textContent = "Žiadna stránka";
    toggle.disabled = true;
    return;
  }
  try {
    currentHost = new URL(currentTab.url).host;
  } catch (error) {
    hostLabel.textContent = "Nepodporovaná stránka";
    toggle.disabled = true;
    return;
  }
  hostLabel.textContent = currentHost;
  const stored = await browser.storage.local.get(keyFor(currentHost));
  toggle.checked = stored[keyFor(currentHost)] !== true;
  renderNote();
}

toggle.addEventListener("change", async () => {
  if (!currentHost) return;
  const disabled = !toggle.checked;
  await browser.storage.local.set({ [keyFor(currentHost)]: disabled });
  renderNote();
  // The content script keeps a copy of the flag the reloaded page reads before
  // anything else runs. Without it the reload would still use the old choice.
  let copied = false;
  try {
    const reply = await browser.tabs.sendMessage(currentTab.id, {
      kind: "site-enabled-changed",
      host: currentHost,
      enabled: !disabled
    });
    copied = reply?.ok === true;
  } catch (error) {
    // No content script in the tab, for instance a page opened before the
    // extension was turned on. The reloaded page catches up on the load after.
  }
  status.textContent = copied
    ? "Stránka sa obnoví, aby sa zmena prejavila."
    : "Stránka sa obnoví. Ak sa zmena neprejaví, obnovte ju ešte raz.";
  try {
    await browser.tabs.reload(currentTab.id);
  } catch (error) {
    status.textContent = "Obnovte stránku, aby sa zmena prejavila.";
  }
});

load();
