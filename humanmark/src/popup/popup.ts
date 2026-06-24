import type { MessageResponse, Settings, Stats } from "../shared/types";

async function send(msg: object): Promise<MessageResponse> {
  return new Promise((resolve) => chrome.runtime.sendMessage(msg, resolve));
}

async function init(): Promise<void> {
  const [settingsResp, statsResp] = await Promise.all([
    send({ type: "GET_SETTINGS" }),
    send({ type: "GET_STATS" }),
  ]);

  const settings = (settingsResp as { type: string; payload: Settings }).payload;
  const stats = (statsResp as { type: string; payload: Stats }).payload;

  // Global enable toggle — read storage directly (popup runs in extension
  // context) so we don't accidentally clobber the apiKey, which is redacted
  // when settings flow through the runtime message channel.
  const toggleEnabled = document.getElementById("toggle-enabled") as HTMLInputElement;
  toggleEnabled.checked = settings.enabled;
  toggleEnabled.addEventListener("change", async () => {
    const stored = await chrome.storage.local.get("settings");
    const real = (stored.settings ?? {}) as Settings;
    await chrome.storage.local.set({ settings: { ...real, enabled: toggleEnabled.checked } });
  });

  // Stats
  (document.getElementById("stat-scanned") as HTMLElement).textContent = String(stats.totalScanned);
  (document.getElementById("stat-flagged") as HTMLElement).textContent = String(stats.flaggedCount);
  (document.getElementById("stat-cache") as HTMLElement).textContent = String(stats.cacheHits);

  // Site override toggle
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const hostname = tab.url ? new URL(tab.url).hostname : "";
  const siteLbl = document.getElementById("site-label") as HTMLElement;
  siteLbl.textContent = hostname || "This site";

  const toggleSite = document.getElementById("toggle-site") as HTMLInputElement;
  const override = settings.siteOverrides[hostname];
  toggleSite.checked = override !== false;
  toggleSite.addEventListener("change", () => {
    chrome.runtime.sendMessage({
      type: "SET_SITE_OVERRIDE",
      hostname,
      enabled: toggleSite.checked,
    });
  });

  // Provider label
  const providerEl = document.getElementById("provider-label") as HTMLElement;
  providerEl.textContent =
    settings.apiProvider === "none" ? "Heuristic mode" : `API: ${settings.apiProvider}`;

  // Settings link
  document.getElementById("open-options")?.addEventListener("click", (e) => {
    e.preventDefault();
    chrome.runtime.openOptionsPage();
  });
}

init().catch(console.error);
