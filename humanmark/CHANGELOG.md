# Changelog

All notable changes to HumanMark. Versions follow [SemVer](https://semver.org/) (`MAJOR.MINOR.PATCH`).

## [0.3.7] — 2026-05-08
**Added**
- Inline tooltips (ⓘ indicators) on every Settings field — hover for a one-sentence explanation of what each control does and when to adjust it.
- Footer link on the Settings page to the User Guide and the GitHub issues page.

## [0.3.6] — 2026-05-08
**Added**
- `USER_GUIDE.md` — single-page walkthrough for end users (badges, popover, popup, settings tour, accuracy expectations, troubleshooting, FAQ).
- `CHANGELOG.md` (this file).
- Top-of-file pointer in `README.md` linking to the user guide.

No code changes.

## [0.3.5] — 2026-05-08
**Fixed**
- False positives on form UI. Anything inside `<form>`/`<fieldset>` or containing an input/textarea/select/button is no longer scored. (AWS Budgets and similar field-label pages were previously getting 80 %+ flags.)
- False positives on short text. The heuristic's burstiness/TTR signals over-fire when there are only 2 short sentences. Score is now capped at 0.45 (below the 0.50 uncertain threshold) when there are fewer than 3 sentences or fewer than 30 words.

**Changed**
- Cache version bumped (`v1` → `v2`) so previously stored false-positive scores don't keep returning for up to 24 hours from local storage.

## [0.3.4] — 2026-05-08
**Fixed**
- Stale badges on SPA navigation (LinkedIn nav clicks between Jobs/Messaging/Notifications, etc.). Frameworks like Ember keep cached DOM trees attached, so the previous "is target still in DOM?" check wasn't enough — orphan badges floated above invisible cached content. Replaced with a full wipe on URL change (badges, outline rules, per-element state), followed by a re-scan that rebuilds visible state from the cache.

## [0.3.3] — 2026-05-08
**Fixed**
- Initial cleanup attempt for stale badges on SPA navigation. Superseded by 0.3.4.

## [0.3.2] — 2026-05-08
**Added**
- Generic TreeWalker fallback in the page scanner — finds substantial text blocks regardless of tag/class. Catches Google Search snippets and modern SPAs that don't use `<p>` for body content.

**Changed**
- Sentence filter relaxed: now accepts long single sentences (≥ 100 chars) in addition to multi-sentence blocks. AI is sometimes one run-on sentence; the previous ≥ 2-sentence requirement rejected most search snippets.

## [0.3.1] — 2026-05-07
**Fixed**
- Page scanner stops working after SPA pagination (Google Search next-page click, hash routes, etc.). Now polls `location.href`, listens to `popstate` and `hashchange`, and re-scans twice (400 ms / 1200 ms after the URL change) since SPAs often render in two phases.

## [0.3.0] — 2026-05-07
**Added**
- Security-hardening pass: all popover content built via DOM construction (no `innerHTML`), API key redacted (`•••`) in runtime message channel, deny-list hostnames validated against a strict DNS-name regex.
- New "Security model" section in `README.md` enumerating threat surfaces and mitigations.
- Expanded release process documentation with Chrome Web Store submission steps.

## [0.2.3] — 2026-05-07
**Fixed**
- Mutation accumulation bug: rapid mutations during fast scroll on LinkedIn dropped most batches because each new MutationObserver callback clobbered the previous debounce timer. Replaced with a roots Set that accumulates across the throttle window.

**Added**
- 250 ms throttled scroll-triggered re-scan (catches infinite-scroll lazy-loaded content).
- 4 s safety-net interval for full re-scan (idempotent; cheap because already-done elements are filtered).

## [0.2.2] — 2026-05-07
**Fixed**
- Default position of the bottom-right HM pill (now offset 60 px from the right edge instead of 20 px) so the wider pill with the always-visible counter doesn't run off the page.

## [0.2.1] — 2026-05-07
**Changed**
- The HM pill always shows the per-page find count and ◀/▶ arrows. Previously the controls only appeared once flags were found, leaving users guessing whether HumanMark had finished scanning.

**Note**
- The popup's "Flagged AI" stat is lifetime across all sites; the pill counter is per-page. They will commonly differ.

## [0.2.0] — 2026-05-07
**Added**
- Click a badge to open a details popover: heading, confidence percent, source (provider/cached/heuristic), analyzed timestamp, and a **Dismiss this flag** button.
- Dismiss removes the badge and outline and prevents re-flagging the same comment for the rest of the session.

**Changed**
- Replaced the previous click action (scroll + outline pulse) — the badge is already next to its target so the previous interaction was mostly cosmetic.

## [0.1.9] — 2026-05-07
**Fixed**
- Badges drifted away from their target as the user scrolled, when content shifted due to lazy-loading. Switched to viewport-relative positioning with a capture-phase scroll listener on `document` so inner scroll containers also trigger reposition.

## [0.1.8] — 2026-05-07
**Fixed**
- All badges stacked at the very top of the viewport when many comments were processed offscreen-above. Removed the `Math.max(4, …)` clamp that collapsed every offscreen-above target's coordinate to `top: 4 px`.

## [0.1.7] — 2026-05-07
**Fixed**
- Invisible badges on LinkedIn (and other sites with body-level transforms / `will-change`). Mounted badges and the HM pill on `document.documentElement` to escape body-scoped containing blocks. Switched z-index from `Number.MAX_SAFE_INTEGER` (exceeds CSS int32 range) to `2147483647`.

## [0.1.6] — initial public-ready release
**Added**
- Initial release. Heuristic offline mode, optional GPTZero / Sapling API integration, deny-list, color picker, prev/next instance navigation, popup with stats and per-site toggle.

---

For commit-level history, see `git log` or https://github.com/ssoward/ideas/commits/main.
