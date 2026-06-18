import type { Settings } from "./types";

export const DEFAULT_SETTINGS: Settings = {
  enabled: true,
  apiProvider: "none",
  apiKey: "",
  privacyAcknowledged: false,
  threshold: { ai: 0.75, uncertain: 0.50 },
  colors: { ai: "#ff2d6b", uncertain: "#f9ff21" },
  minTextLength: 60,
  siteOverrides: {},
  showOnlyFlagged: false,
};

export const STORAGE_KEYS = {
  SETTINGS: "settings",
  STATS: "stats",
  CACHE_PREFIX: "cache:v2:",
  RATE_LIMITER: "ratelimiter:v1",
} as const;

export const CSS = {
  BLOCK_PREFIX: "hm-block",
  STATE_PREFIX: "hm-state",
  BADGE: "hm-badge",
  TOOLTIP: "hm-tooltip",
  SHADOW_HOST: "hm-shadow-host",
  TOGGLE_PILL: "hm-toggle",
} as const;

export const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24h
export const CACHE_MAX_ENTRIES = 5000;           // LRU cap to stay well under storage quota
export const BATCH_SIZE = 5;
export const DEBOUNCE_MS = 300;
