import type { MessageResponse, Settings } from "../shared/types";
import { initRenderer, updateRendererSettings } from "./renderer";
import { startObserving, updateActiveSettings } from "./mutation-observer";
import { setPostProcessor } from "./scheduler";
import { TwitterAdapter } from "./platform-adapters/twitter";
import { LinkedInAdapter } from "./platform-adapters/linkedin";
import { StravaAdapter } from "./platform-adapters/strava";

const ADAPTERS = [TwitterAdapter, LinkedInAdapter, StravaAdapter];

function getPlatformPostProcess(hostname: string): ((score: number, text: string) => number) | null {
  const adapter = ADAPTERS.find((a) => hostname.includes(a.hostname));
  return adapter ? adapter.postProcessScore.bind(adapter) : null;
}

function shouldRun(settings: Settings, hostname: string): boolean {
  const override = settings.siteOverrides[hostname];
  if (override === false) return false;
  if (!settings.enabled && override !== true) return false;
  return true;
}

let started = false;

async function init(): Promise<void> {
  const resp = await sendMessage({ type: "GET_SETTINGS" }) as MessageResponse;
  if (resp.type !== "SETTINGS") return;

  const settings: Settings = resp.payload;
  const hostname = location.hostname;
  if (!shouldRun(settings, hostname)) {
    // Listen anyway so flipping the toggle on takes effect without a reload
    listenForChanges();
    return;
  }

  start(settings);
  listenForChanges();
}

function start(settings: Settings): void {
  if (started) return;
  started = true;
  setPostProcessor(getPlatformPostProcess(location.hostname));
  initRenderer(settings);
  startObserving(settings);
}

function listenForChanges(): void {
  chrome.storage.onChanged.addListener((changes) => {
    const change = changes["settings"];
    if (!change) return;
    const newSettings = change.newValue as Settings;
    if (!newSettings) return;

    if (!started && shouldRun(newSettings, location.hostname)) {
      start(newSettings);
      return;
    }
    if (started) {
      updateRendererSettings(newSettings);
      updateActiveSettings(newSettings);
    }
  });
}

function sendMessage(msg: object): Promise<MessageResponse> {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(msg, (resp: MessageResponse) => {
      if (chrome.runtime.lastError) return reject(chrome.runtime.lastError.message);
      resolve(resp);
    });
  });
}

init().catch(console.error);
