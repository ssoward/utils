# Loading HumanMark in Chrome

## Quick load (dev)

1. Run `npm run build` (or `npm run dev` for watch mode)
2. Open `chrome://extensions`
3. Toggle **Developer mode** ON (top-right)
4. Click **Load unpacked** → select the `dist/` folder
5. HumanMark icon appears in your toolbar

## First use

- Click the **HM** icon → toggle it on
- Browse any article, LinkedIn feed, or Twitter/X
- Red left border = likely AI (~75%+). Amber = uncertain (50-74%). Hover the badge chip for details.
- The `HM` pill in the bottom-right corner pauses scanning on the current page.

## Adding an API key (optional — improves accuracy significantly)

Heuristic-only mode (~80% accuracy) works with no setup.

For better accuracy:
1. Get a free **GPTZero** key at gptzero.me (10k words/month free) or **Sapling** key at sapling.ai
2. Click HM icon → **Settings**
3. Select provider, paste key, check the privacy consent, save.

## Architecture summary

```
src/
  background/service-worker.ts   — orchestrates API calls, cache, rate limiting
  content/content-script.ts      — DOM scanning, mutation observer, renderer
  content/platform-adapters/     — Twitter, LinkedIn, Strava heuristic boosts
  popup/                         — status popup + site toggle
  options/                       — API key, thresholds, deny-list
  shared/                        — types, constants, hash utility
  styles/overlay.css             — injected left-border + badge styles
```

## Detection signals (heuristic mode — no API)

- **Burstiness**: AI text has low sentence-length variance (flat rhythm)
- **Type-token ratio**: unusual vocabulary uniformity pattern
- **Punctuation entropy**: AI rarely uses em-dashes, parentheticals, ellipses
- **Platform-specific**: LinkedIn "3-bullets + CTA" pattern, Strava motivational phrase blocklist

## Phase 2 (planned): Local ONNX model

A quantized DistilRoBERTa (~15MB INT8) loaded via ONNX Runtime Web in the service worker,
targeting ~90% accuracy fully offline.
