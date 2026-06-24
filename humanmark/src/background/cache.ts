import type { BlockResult } from "../shared/types";
import { STORAGE_KEYS, CACHE_TTL_MS, CACHE_MAX_ENTRIES } from "../shared/constants";

export async function cacheGet(hash: string): Promise<BlockResult | null> {
  const key = STORAGE_KEYS.CACHE_PREFIX + hash;
  const result = await chrome.storage.local.get(key);
  const entry = result[key] as BlockResult | undefined;
  if (!entry) return null;
  if (Date.now() - entry.analyzedAt > CACHE_TTL_MS) {
    await chrome.storage.local.remove(key);
    return null;
  }
  return entry;
}

export async function cacheSet(hash: string, result: BlockResult): Promise<void> {
  const key = STORAGE_KEYS.CACHE_PREFIX + hash;
  await chrome.storage.local.set({ [key]: result });
  // Opportunistic LRU enforcement — only checks size every ~50 writes
  if (Math.random() < 0.02) await enforceMaxSize();
}

export async function cacheClearExpired(): Promise<void> {
  const all = await chrome.storage.local.get(null);
  const expiredKeys: string[] = [];
  const now = Date.now();
  for (const [key, value] of Object.entries(all)) {
    if (key.startsWith(STORAGE_KEYS.CACHE_PREFIX)) {
      const entry = value as BlockResult;
      if (now - entry.analyzedAt > CACHE_TTL_MS) expiredKeys.push(key);
    }
  }
  if (expiredKeys.length > 0) await chrome.storage.local.remove(expiredKeys);
  await enforceMaxSize();
}

async function enforceMaxSize(): Promise<void> {
  const all = await chrome.storage.local.get(null);
  const entries: Array<[string, BlockResult]> = [];
  for (const [key, value] of Object.entries(all)) {
    if (key.startsWith(STORAGE_KEYS.CACHE_PREFIX)) {
      entries.push([key, value as BlockResult]);
    }
  }
  if (entries.length <= CACHE_MAX_ENTRIES) return;
  // Evict oldest first
  entries.sort((a, b) => a[1].analyzedAt - b[1].analyzedAt);
  const toRemove = entries.slice(0, entries.length - CACHE_MAX_ENTRIES).map(([k]) => k);
  if (toRemove.length > 0) await chrome.storage.local.remove(toRemove);
}
