import type { MessageRequest, MessageResponse, Settings, Stats } from "../shared/types";
import { DEFAULT_SETTINGS, STORAGE_KEYS } from "../shared/constants";
import { ADAPTERS, heuristicScore, buildResult } from "./api-client";
import { cacheGet, cacheSet, cacheClearExpired } from "./cache";
import { checkRateLimit } from "./rate-limiter";

async function getSettings(): Promise<Settings> {
  const result = await chrome.storage.local.get(STORAGE_KEYS.SETTINGS);
  const saved = (result[STORAGE_KEYS.SETTINGS] as Partial<Settings>) ?? {};
  return {
    ...DEFAULT_SETTINGS,
    ...saved,
    threshold: { ...DEFAULT_SETTINGS.threshold, ...(saved.threshold ?? {}) },
    colors:    { ...DEFAULT_SETTINGS.colors,    ...(saved.colors    ?? {}) },
    siteOverrides: saved.siteOverrides ?? {},
  };
}

async function getStats(): Promise<Stats> {
  const result = await chrome.storage.local.get(STORAGE_KEYS.STATS);
  return (result[STORAGE_KEYS.STATS] as Stats) ?? {
    totalScanned: 0, apiCallCount: 0, cacheHits: 0, flaggedCount: 0, lastReset: Date.now(),
  };
}

// Serialize stat updates so concurrent ANALYZE_BLOCK messages don't drop counts
// in the read-modify-write window.
let statsChain: Promise<void> = Promise.resolve();
function bumpStats(deltas: Partial<Omit<Stats, "lastReset">>): Promise<void> {
  statsChain = statsChain.then(async () => {
    const stats = await getStats();
    for (const [k, v] of Object.entries(deltas)) {
      stats[k as keyof Stats] = (stats[k as keyof Stats] as number) + (v as number);
    }
    await chrome.storage.local.set({ [STORAGE_KEYS.STATS]: stats });
  }).catch(() => {});
  return statsChain;
}

chrome.runtime.onInstalled.addListener(async () => {
  const fresh = await getSettings();
  await chrome.storage.local.set({ [STORAGE_KEYS.SETTINGS]: fresh });
});

chrome.alarms.create("cache-cleanup", { periodInMinutes: 360 });
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === "cache-cleanup") await cacheClearExpired();
});

chrome.runtime.onMessage.addListener(
  (msg: MessageRequest, _sender, sendResponse: (r: MessageResponse) => void) => {
    handleMessage(msg).then(sendResponse).catch((err) => {
      sendResponse({ type: "ERROR", reason: String(err) });
    });
    return true;
  }
);

// Strip the API key before sending settings over the runtime message channel.
// Callers that legitimately need it (options page) read storage directly.
function redact(s: Settings): Settings {
  return { ...s, apiKey: s.apiKey ? "•••" : "" };
}

async function handleMessage(msg: MessageRequest): Promise<MessageResponse> {
  if (msg.type === "GET_SETTINGS") {
    return { type: "SETTINGS", payload: redact(await getSettings()) };
  }

  if (msg.type === "GET_STATS") {
    return { type: "STATS", payload: await getStats() };
  }

  if (msg.type === "SET_SITE_OVERRIDE") {
    const settings = await getSettings();
    settings.siteOverrides[msg.hostname] = msg.enabled;
    await chrome.storage.local.set({ [STORAGE_KEYS.SETTINGS]: settings });
    return { type: "SETTINGS", payload: redact(settings) };
  }

  if (msg.type === "ANALYZE_BLOCK") {
    const { hash, text } = msg.payload;
    const settings = await getSettings();

    const cached = await cacheGet(hash);
    if (cached) {
      // Cache hits count toward "scanned" too — same content was evaluated
      // once before, but the user is seeing it now. flaggedCount only bumps
      // on the original analysis (counted at cache-write time) so cached
      // re-views don't inflate the flag counter.
      void bumpStats({ cacheHits: 1, totalScanned: 1 });
      return { type: "BLOCK_RESULT", result: { ...cached, source: "cache" } };
    }

    // Use the configured API only if there's enough text to be worth a quota hit
    const useApi =
      settings.apiProvider !== "none" &&
      settings.apiKey &&
      settings.privacyAcknowledged &&
      text.length >= settings.minTextLength;

    if (useApi) {
      const adapter = ADAPTERS[settings.apiProvider];
      if (adapter) {
        const allowed = await checkRateLimit(adapter.name, adapter.requestsPerMin);
        if (allowed) {
          try {
            const truncated = text.slice(0, adapter.maxChars);
            const score = await adapter.analyze(truncated, settings.apiKey);
            const result = buildResult(hash, score, "api", adapter.name);
            await cacheSet(hash, result);
            void bumpStats({
              apiCallCount: 1,
              totalScanned: 1,
              flaggedCount: score >= settings.threshold.uncertain ? 1 : 0,
            });
            return { type: "BLOCK_RESULT", result };
          } catch (err) {
            // Network error / quota / bad key — silently fall through to heuristic.
            // Logging at warn level only so production users aren't spammed.
            console.warn("[HumanMark] API failed, using heuristic:", err);
          }
        }
      }
    }

    const score = heuristicScore(text);
    const result = buildResult(hash, score, "heuristic");
    await cacheSet(hash, result);
    void bumpStats({
      totalScanned: 1,
      flaggedCount: score >= settings.threshold.uncertain ? 1 : 0,
    });
    return { type: "BLOCK_RESULT", result };
  }

  return { type: "ERROR", reason: "Unknown message type" };
}
