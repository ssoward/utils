# HumanMark — Privacy Policy

_Last updated: 2026-05-07_

HumanMark is a Chrome extension that flags AI-generated text on webpages with a confidence badge. This document describes what data the extension handles, where it goes, and what it never touches.

## What HumanMark stores locally

All of the following live in `chrome.storage.local`, sandboxed to this extension. Other extensions and websites cannot read it.

- **Settings**: enable toggle, AI/uncertain thresholds, badge colors, deny-listed hostnames, minimum text length, your chosen API provider, your API key (if you provided one), and your privacy consent status.
- **Cache**: per-text-block analysis results — a hash of the text, the score, the source (api/cache/heuristic), provider name, and timestamp. **The text itself is never stored.** Cache entries expire after 24 hours and are bounded at 5,000 entries (LRU eviction).
- **Stats**: lifetime counters for blocks scanned, API calls made, cache hits, and items flagged.

Nothing in local storage leaves your browser.

## What HumanMark sends over the network

**Heuristic mode (default)**: nothing. Zero outbound network requests.

**API mode (opt-in only)**: when you explicitly select an AI-detection provider, paste an API key, and check the consent box in Settings, HumanMark may send the text of analyzed blocks to your chosen provider:

- **GPTZero** — `https://api.gptzero.me/v2/predict/text` (text in JSON body, key in `x-api-key` header)
- **Sapling** — `https://api.sapling.ai/api/v1/aidetect` (text and key in JSON body)

Both endpoints use HTTPS. We send only the text being analyzed and your key — no URL, page metadata, browser fingerprint, or identifier.

Whatever those providers do with text you send is governed by **their** privacy policies, not ours. Read them before enabling API mode:

- GPTZero: https://gptzero.me/privacy-policy
- Sapling: https://sapling.ai/privacy

Quota protection: a token-bucket rate limiter caps requests per provider, and API failures fall back to the offline heuristic instead of retrying.

## What HumanMark does not collect

- **No analytics.** No telemetry, no error reporting service, no cookies, no fingerprints.
- **No personally identifiable information.** We never read or transmit names, emails, addresses, phone numbers, or account identifiers.
- **No browsing history.** We do not record the URLs you visit. The popup only reads the *current* tab's hostname to label the per-site enable toggle.
- **No content from your screen** beyond the text blocks the heuristic actually evaluates, and only when API mode is on.
- **No remote code execution.** Everything ships in the extension package. Nothing is loaded from the internet at runtime.
- **No sale or sharing of any data with us.** There is no "us" — the extension does not phone home.

## Permissions

| Permission | Purpose |
|---|---|
| `storage` | Save the settings, cache, and stats listed above. |
| `alarms` | Trigger periodic cleanup of the local cache. |
| `tabs` | Read the active tab's hostname so the popup can show the per-site toggle. |
| `host_permissions: <all_urls>` | The content script must run on whatever page you're browsing in order to flag AI text. You can deny-list any sites you don't want scanned. |

## Your controls

- **Disable globally** from the toolbar popup at any time.
- **Disable per-site** via the popup toggle or the deny list in Settings.
- **Clear all stored data** by removing the extension (Chrome will purge `chrome.storage.local` for the extension automatically) or by clearing browser data for extensions in Chrome's settings.
- **Switch off API mode** by setting the provider back to "Heuristic only" in Settings; outbound network calls stop immediately.

## Children

HumanMark is not directed to children under 13 and does not knowingly collect data from anyone.

## Contact

Questions or concerns: open an issue at https://github.com/ssoward/ideas/issues.

## Changes

This policy may be updated as the extension evolves. The "Last updated" date at the top reflects the current version. The current text is always available at `humanmark/PRIVACY.md` in the source repository.
