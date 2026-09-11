// Per-site switch. Turning this off hands the page back to whatever D.Signer it
// would have used on its own, typically Ditec D.Bridge 2, without disabling the
// whole extension.

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
    ? "Podpisovanie na tejto stránke preberá Autogram macOS."
    : "Stránka použije svoj pôvodný D.Signer (napríklad D.Bridge 2). Zmena platí hneď, bez obnovenia stránky.";
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
  try {
    await browser.tabs.sendMessage(currentTab.id, {
      kind: "site-enabled-changed",
      enabled: !disabled
    });
    status.textContent = "";
  } catch (error) {
    // The content script is not there, for instance right after switching a
    // site back on. A reload picks it up.
    status.textContent = "Obnovte stránku, aby sa zmena prejavila.";
  }
});

load();
