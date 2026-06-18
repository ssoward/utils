import type { Settings } from "../shared/types";
import { getTextBlocks, isEligible } from "./block-eligibility";
import { enqueue, setActiveSettings } from "./scheduler";
import { wipeAll } from "./renderer";
import { DEBOUNCE_MS } from "../shared/constants";

let activeSettings: Settings | null = null;

// Pending roots accumulate across the throttle window. Using a Set keeps each
// added subtree just once even if multiple mutations affect it.
const pendingRoots = new Set<Element>();
let scanQueued = false;

export function startObserving(settings: Settings): void {
  activeSettings = settings;
  setActiveSettings(settings);
  scanPage();

  const observer = new MutationObserver((mutations) => {
    let added = false;
    for (const m of mutations) {
      if (m.type !== "childList" || m.addedNodes.length === 0) continue;
      // Ignore mutations whose target is part of HumanMark's own UI
      const target = m.target as Element | null;
      if (target?.id === "hm-toggle" || target?.id === "hm-outlines") continue;
      if ((target as HTMLElement | null)?.hasAttribute?.("data-hm-target-id")) continue;

      for (const node of m.addedNodes) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;
        const el = node as Element;
        if ((el as HTMLElement).hasAttribute?.("data-hm-target-id")) continue;
        if (el.id === "hm-toggle" || el.id === "hm-outlines") continue;
        pendingRoots.add(el);
        added = true;
      }
    }
    if (!added) return;
    scheduleScan();
  });

  observer.observe(document.body, { childList: true, subtree: true });

  // Safety net: LinkedIn occasionally swaps content in ways the mutation
  // observer can miss (e.g. attribute-only re-renders that change visibility).
  // A periodic full re-scan is cheap because isEligible filters out anything
  // already seen via dataset.hmState === "done".
  setInterval(() => { if (activeSettings) scanPage(); }, 4000);

  // Also re-scan whenever the user scrolls — catches infinite-scroll content
  // that lazy-loads after a scroll gesture without ever firing a relevant
  // childList mutation in our subtree.
  let scrollScanQueued = false;
  const onScroll = () => {
    if (scrollScanQueued) return;
    scrollScanQueued = true;
    setTimeout(() => {
      scrollScanQueued = false;
      if (activeSettings) scanPage();
    }, 250);
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  document.addEventListener("scroll", onScroll, { passive: true, capture: true });

  // SPA navigation: Google Search pagination, LinkedIn feed switches, and
  // other client-routed pages change history without reloading the document,
  // so the content script never re-initializes. We can't intercept the
  // page's history.pushState (different JS world), but we can poll
  // location.href cheaply and watch popstate for back/forward.
  watchUrlChanges();
}

function watchUrlChanges(): void {
  let lastUrl = location.href;
  const onUrlChange = () => {
    if (location.href === lastUrl) return;
    lastUrl = location.href;
    if (!activeSettings) return;
    // Full wipe: orphan badges left over from the previous route would
    // otherwise float above invisible cached DOM. The re-scan rebuilds
    // visible state from cache (sub-ms hits).
    wipeAll();
    // Re-scan in two phases — SPAs often render skeleton then content.
    setTimeout(() => { if (activeSettings) scanPage(); }, 400);
    setTimeout(() => { if (activeSettings) scanPage(); }, 1200);
  };
  setInterval(onUrlChange, 500);
  window.addEventListener("popstate", onUrlChange);
  window.addEventListener("hashchange", onUrlChange);
}

export function updateActiveSettings(settings: Settings): void {
  activeSettings = settings;
  setActiveSettings(settings);
}

function scheduleScan(): void {
  if (scanQueued) return;
  scanQueued = true;
  setTimeout(() => {
    scanQueued = false;
    if (!activeSettings) { pendingRoots.clear(); return; }
    drainPending(activeSettings);
  }, DEBOUNCE_MS);
}

function drainPending(settings: Settings): void {
  const candidates = new Set<Element>();
  for (const root of pendingRoots) {
    if (!root.isConnected) continue;
    if (isEligible(root as HTMLElement, settings)) candidates.add(root);
    for (const child of getTextBlocks(root)) {
      if (isEligible(child as HTMLElement, settings)) candidates.add(child);
    }
  }
  pendingRoots.clear();
  for (const el of candidates) enqueue(el as HTMLElement);
}

function scanPage(): void {
  if (!activeSettings) return;
  const blocks = getTextBlocks(document);
  for (const block of blocks) {
    if (isEligible(block as HTMLElement, activeSettings)) {
      enqueue(block as HTMLElement);
    }
  }
}
