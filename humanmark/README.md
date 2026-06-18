# HumanMark

A Chrome extension (Manifest V3) that flags AI-generated text on any webpage. It outlines suspicious blocks, drops a small floating badge with a confidence score, and lets you jump between flagged instances on the page.

> **Just installed from the Chrome Web Store?**
> Read the **[User Guide](USER_GUIDE.md)** — explains the badges, popover, settings, accuracy, and troubleshooting in plain English. The rest of this README is for developers.

- **Heuristic mode** — works offline, no API key. ~80 % accuracy.
- **API mode (optional)** — use [GPTZero](https://gptzero.me) (10k words/mo free) or [Sapling](https://sapling.ai) for higher accuracy. Text is only sent after explicit consent.
- **Per-site control** — toggle scanning on/off for the current site from the popup, or maintain a global deny list in Settings.
- **Privacy-first defaults** — heuristic mode never makes a network call.

See [`CHANGELOG.md`](CHANGELOG.md) for what changed in each release, [`PRIVACY.md`](PRIVACY.md) for the privacy policy, [`RELEASE.md`](RELEASE.md) for the publish-to-store workflow, [`STATUS.md`](STATUS.md) for current operational state and next-action notes.

## Install (developer mode)

```bash
npm install
npm run build
```

1. Open `chrome://extensions`
2. Toggle **Developer mode** (top-right)
3. Click **Load unpacked** → select the `dist/` folder
4. Pin the **HM** icon to your toolbar

For a watch build during development: `npm run dev`.

## Usage

- **Red outline + 🤖 badge** — score ≥ AI threshold (default 75%)
- **Amber outline + ⚠️ badge** — score ≥ uncertain threshold (default 50%)
- **Floating HM pill (bottom-right)** — click to hide/show flags, drag to relocate, ◀ ▶ to navigate between flagged blocks. Click any badge to jump to its block.

Open the popup to:

- Toggle the extension globally
- Disable scanning for the current site
- View per-session stats (scanned / flagged / cache hits)

Open Settings (popup → "Settings") to:

- Pick an API provider and paste your key (consent required)
- Adjust AI / uncertain thresholds and minimum text length
- Customize flag colors (presets included)
- Maintain a deny-list of hostnames

## How it works

```
src/
  background/
    service-worker.ts    Routes ANALYZE_BLOCK messages, owns cache + rate limit + stats
    api-client.ts        GPTZero / Sapling adapters + offline heuristic scorer
    cache.ts             chrome.storage.local with TTL + LRU cap (5000 entries)
    rate-limiter.ts      Token bucket persisted to chrome.storage.session
  content/
    content-script.ts    Boot — reads settings, wires up renderer + observer
    block-eligibility.ts CSS selectors + filters for what counts as a "block"
    mutation-observer.ts Watches for new posts/comments; ignores HM's own DOM
    scheduler.ts         Per-tab queue, intersection-observer priority, batching
    renderer.ts          Outlines, badges, floating pill, prev/next nav
    platform-adapters/   Twitter / LinkedIn / Strava signal boosts
  popup/                 Toolbar UI
  options/               Full settings page
  shared/                Types, constants, hash
```

### Detection signals (offline heuristic)

- **Burstiness** — variance in sentence length. AI text is unusually flat.
- **Type-token ratio** — vocabulary uniformity in short passages.
- **Punctuation richness** — em-dashes, ellipses, parentheticals are uncommon in AI output.
- **Platform tweaks** — LinkedIn "3 short bullets + CTA" pattern; Strava boilerplate motivational phrases; Twitter contraction-free, low-emoji tells.

The score is clamped to `[0, 1]` and compared against the configured thresholds.

## Privacy

- Heuristic mode is fully offline.
- API mode is opt-in: provider + key + an explicit consent checkbox are all required before any text leaves the browser.
- The cache stores only the score, hash, source, and timestamp — never the original text.
- The API key is stored in `chrome.storage.local` (the extension's sandboxed storage).
- No telemetry. No analytics. Outbound fetches only to the AI-detection provider you configure (`api.gptzero.me` or `api.sapling.ai`).

## Security model

Threats considered, with mitigations:

| Surface | Mitigation |
|---|---|
| **Host-page script reading API key** | Content scripts run in an isolated world; `apiKey` is redacted (`•••`) when settings flow through the runtime message channel; only the service worker holds the real key in memory at request time. |
| **Host-page CSS hiding our overlay** | Critical positioning props (`position`, `z-index`, `display`, `visibility`, `pointer-events`) set with `!important` via `setProperty`; outline applied via dedicated `<style>` rule with `!important`. |
| **HTML injection into popover** | Popover built via `document.createElement` + `textContent` only — no `innerHTML`, `outerHTML`, `insertAdjacentHTML`, or template interpolation into HTML strings. |
| **Selector / regex injection via `nodeId`** | `nodeId` is generated as `hm-${Math.random().toString(36).slice(2,10)}` — alphanumeric only. |
| **Prototype pollution via deny list** | Hostnames are validated against a strict DNS-name regex before being used as object keys. |
| **Quota exhaustion / cost burn** | Token-bucket rate limiter persisted across SW restarts; min-text-length gate before API call; API failures fall back to heuristic instead of retrying. |
| **Cache poisoning** | Cache key is a 64-bit composite hash plus length tag — collision probability vanishingly small at the configured cap. Cache is per-extension; no cross-origin write path. |
| **Storage exhaustion** | LRU eviction at `CACHE_MAX_ENTRIES = 5000` plus 24 h TTL. |
| **Stats race** | `chrome.storage.local` read-modify-write serialised through a single promise chain. |
| **Concurrent settings overwrite** | Options page re-reads storage on Save and merges with in-flight popup changes (per-site enables preserved). |
| **Page-CSP exfiltration via inline scripts** | We never inject `<script>` into the host page; all logic stays in the content script's isolated world. Extension page CSP: `script-src 'self' 'wasm-unsafe-eval'; object-src 'self'`. |

What we **do** trust:
- The two API endpoints (`api.gptzero.me`, `api.sapling.ai`) are hardcoded in source.
- `chrome.storage.*` integrity (sandboxed per extension).
- The user's own deny list and threshold settings.

What we **do not** trust:
- Anything in the host page DOM. Selectors are scoped, mutations from our own injected nodes are filtered out, all content goes through `textContent` extraction.
- Service-worker message payloads — they're validated against a discriminated union before dispatch; unknown types return `ERROR`.

## Permissions

| Permission | Why |
|---|---|
| `storage` | Settings, cache, stats |
| `alarms` | Periodic cache cleanup |
| `tabs` | Read the active tab's hostname for the per-site toggle |
| `<all_urls>` | Content script needs to scan whatever page you're on |

## Release process

1. **Bump the version** in both `manifest.json` and `package.json` (kept in sync).
2. **Build the production package**:
   ```bash
   ./scripts/package.sh           # builds + zips dist/ → humanmark-vX.Y.Z.zip
   ./scripts/package.sh 0.2.0     # override version
   ```
3. **Smoke-test the unpacked dist** via `chrome://extensions` → Load unpacked → `dist/`. Verify on at least one feed-style site (LinkedIn) and one article (any blog).
4. **Submit to the Chrome Web Store**:
   - Open the [Developer Dashboard](https://chrome.google.com/webstore/devconsole). One-time $5 developer fee for new accounts.
   - Click **New item** → upload `humanmark-vX.Y.Z.zip`.
   - Fill the store listing: short description, detailed description, screenshots (≥ 1 at 1280×800 or 640×400), promotional tile, primary category (Productivity), language.
   - **Privacy practices** tab — declare:
     - Personally identifiable information: none collected.
     - Health, financial, location, web history, user activity: none collected/transmitted *unless* the user enables an AI-detection API, in which case the analyzed text is sent to the chosen provider.
     - "Single purpose" statement: "Flag AI-generated text on webpages and show a confidence badge."
     - Permission justifications:
       - `storage` — settings, cache, stats
       - `alarms` — periodic cache cleanup
       - `tabs` — show current site hostname in popup for per-site toggle
       - `host_permissions: <all_urls>` — content script must scan whichever page the user is on; user can deny-list specific sites
     - Remote code: none.
   - **Distribution**: choose visibility (Public, Unlisted, or Private). For first review, Unlisted is a good way to validate review without prematurely going public.
   - Click **Submit for review**. First review typically completes in 1–7 business days.
5. After approval, tag the release in git:
   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   ```

## Scripts

| Command | Description |
|---|---|
| `npm run dev` | Watch build into `dist/` |
| `npm run build` | One-shot production build |
| `npm run typecheck` | `tsc --noEmit` |
| `./scripts/package.sh` | Build + create store-ready zip |

## Roadmap

- Local ONNX model (quantized DistilRoBERTa) loaded via ONNX Runtime Web in the service worker — targets ~90% accuracy fully offline.
- Per-site sensitivity profiles.
- Export / import of settings and deny-list.
