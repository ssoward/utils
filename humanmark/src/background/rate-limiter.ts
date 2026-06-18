import { STORAGE_KEYS } from "../shared/constants";

interface Bucket { tokens: number; lastRefill: number }
type BucketMap = Record<string, Bucket>;

// In-memory mirror to avoid a storage round-trip on every check; flushed on
// every mutation so a service-worker restart still sees fresh state.
let cache: BucketMap | null = null;

async function load(): Promise<BucketMap> {
  if (cache) return cache;
  const result = (await chrome.storage.session
    .get(STORAGE_KEYS.RATE_LIMITER)
    .catch(() => ({}))) as Record<string, BucketMap | undefined>;
  cache = result[STORAGE_KEYS.RATE_LIMITER] ?? {};
  return cache;
}

async function save(buckets: BucketMap): Promise<void> {
  cache = buckets;
  // chrome.storage.session is wiped on browser restart but survives SW idle;
  // ideal for short-lived counters that shouldn't leak across sessions.
  await chrome.storage.session.set({ [STORAGE_KEYS.RATE_LIMITER]: buckets }).catch(() => {});
}

export async function checkRateLimit(provider: string, maxPerMin: number): Promise<boolean> {
  const buckets = await load();
  const now = Date.now();
  const bucket = buckets[provider] ?? { tokens: maxPerMin, lastRefill: now };

  const elapsed = (now - bucket.lastRefill) / 60_000;
  bucket.tokens = Math.min(maxPerMin, bucket.tokens + elapsed * maxPerMin);
  bucket.lastRefill = now;

  if (bucket.tokens < 1) {
    buckets[provider] = bucket;
    await save(buckets);
    return false;
  }

  bucket.tokens -= 1;
  buckets[provider] = bucket;
  await save(buckets);
  return true;
}
