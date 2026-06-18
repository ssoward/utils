import type { Settings } from "../shared/types";

const SKIP_TAGS = new Set(["SCRIPT", "STYLE", "CODE", "PRE", "NOSCRIPT", "TEMPLATE", "TEXTAREA", "INPUT", "BUTTON"]);

// Ordered from most-specific (platform) to most-generic (fallback)
const TEXT_BLOCK_SELECTORS = [
  // LinkedIn
  "span.break-words",
  ".feed-shared-update-v2__description",
  ".update-components-text",
  ".feed-shared-text-view",
  // Twitter/X
  '[data-testid="tweetText"]',
  // Strava
  ".activity-description",
  ".comment-text",
  // Generic article / blog content
  "article p",
  ".post-body p",
  ".entry-content p",
  ".article-body p",
  ".story-body p",
  "main p",
  // Fallback — standalone paragraphs and blockquotes not inside nav/header/footer
  "p:not(nav p):not(header p):not(footer p)",
  "blockquote",
].join(", ");

// Block-level tags considered valid text containers by the generic walker.
// SPAN is included because Google/Twitter/many SPAs wrap snippet text in spans.
const TEXT_BLOCK_TAGS = new Set(["DIV", "P", "SPAN", "ARTICLE", "SECTION", "BLOCKQUOTE", "LI", "TD", "DD"]);
const GENERIC_MIN_TEXT = 100; // longer threshold for the generic walker — avoid noise

export function getTextBlocks(root: Element | Document = document): Element[] {
  const seen = new Set<Element>();
  const out: Element[] = [];
  for (const el of root.querySelectorAll<Element>(TEXT_BLOCK_SELECTORS)) {
    if (!seen.has(el)) { seen.add(el); out.push(el); }
  }
  // Generic fallback: walk text nodes, climb to the smallest block-level
  // container with substantial aggregated text. Catches Google Search
  // snippets, modern SPAs, and anywhere not using <p> for body copy.
  const walkRoot: Node = root instanceof Document ? (root.body ?? root.documentElement) : root;
  if (walkRoot) collectGenericBlocks(walkRoot, seen, out);
  return out;
}

function collectGenericBlocks(root: Node, seen: Set<Element>, out: Element[]): void {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const t = node.textContent;
      if (!t || t.trim().length < 30) return NodeFilter.FILTER_REJECT;
      const parent = node.parentElement;
      if (!parent || SKIP_TAGS.has(parent.tagName)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    },
  });

  let n: Node | null;
  while ((n = walker.nextNode())) {
    let el: Element | null = n.parentElement;
    let found: Element | null = null;
    // Climb until we hit a block-level container with enough aggregated text
    while (el && el.parentElement) {
      if (TEXT_BLOCK_TAGS.has(el.tagName)) {
        const len = (el.textContent ?? "").trim().length;
        if (len >= GENERIC_MIN_TEXT) { found = el; break; }
      }
      el = el.parentElement;
    }
    if (!found || seen.has(found)) continue;
    // Skip if an ancestor was already collected — keep the leaf-most container.
    let ancestor = found.parentElement;
    let dominated = false;
    while (ancestor) {
      if (seen.has(ancestor)) { dominated = true; break; }
      ancestor = ancestor.parentElement;
    }
    if (dominated) continue;
    seen.add(found);
    out.push(found);
  }
}

export function isEligible(el: Element, settings: Settings): boolean {
  if (SKIP_TAGS.has(el.tagName)) return false;

  // aria-hidden on element OR any ancestor — skip the whole subtree
  if (el.closest('[aria-hidden="true"]')) return false;

  // Skip our own injected DOM
  if ((el as HTMLElement).hasAttribute("data-hm-target-id")) return false;
  if (el.id === "hm-toggle" || el.id === "hm-outlines") return false;

  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;

  if ((el as HTMLElement).dataset.hmState === "done") return false;

  // For SPAN elements, prefer the outermost match — if a tracked ancestor
  // (article body, post description) is also being scanned, skip the inner span.
  if (el.tagName === "SPAN") {
    const wrappingPost = el.parentElement?.closest(
      ".feed-shared-update-v2__description, .update-components-text, article"
    );
    if (wrappingPost && wrappingPost !== el) return false;
  }

  // Form UI is not prose. Skip anything inside a <form>/<fieldset> or any
  // container that holds interactive controls — the AWS Budgets / settings-
  // style "Field name + helper + input" group is the canonical false
  // positive: terse, structurally similar across all such forms, never
  // human creative text or AI text.
  if (el.closest("form, fieldset")) return false;
  if (el.querySelector("input, textarea, select, button, [role='textbox'], [role='combobox'], [role='button']")) return false;

  const text = (el.textContent ?? "").trim();
  if (text.length < settings.minTextLength) return false;
  if (text.length > 20_000) return false;

  // Allow either: 2+ sentences, OR a single long sentence (>= 100 chars).
  // AI text is sometimes a single run-on sentence; rejecting all single
  // sentences misses Google search snippets and many summary blocks.
  const sentenceCount =
    (text.match(/[.!?]+[\s\n]+[A-Z]/g) ?? []).length +
    (text.match(/\n{2,}/g) ?? []).length +
    1;
  if (sentenceCount < 2 && text.length < 100) return false;

  return true;
}

export function extractText(el: Element): string {
  return (el.textContent ?? "").replace(/\s+/g, " ").trim();
}
