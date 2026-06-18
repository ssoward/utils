# Chrome Web Store — Submission Copy

Paste-ready text for the Web Store dashboard. Each section maps to a field on the form.

---

## Item details

**Name** (≤ 45 chars)
```
HumanMark — AI Text Detector
```

**Summary / Short description** (≤ 132 chars)
```
Flag AI-generated text on any webpage with a confidence badge. Works offline by default; opt-in API mode for higher accuracy.
```

**Category**
```
Productivity
```

**Language**
```
English (United States)
```

---

## Detailed description

```
HumanMark spots likely AI-generated text on any webpage and shows you a confidence badge so you can read with context.

How it works
• Scans visible text blocks on the page (posts, comments, articles, search snippets, summaries).
• Scores each block with a fast offline heuristic — sentence-length variance ("burstiness"), vocabulary uniformity, punctuation patterns, and platform-specific tells (LinkedIn 3-bullet-plus-CTA cadence, Strava boilerplate motivational phrases, Twitter low-emoji contraction-free patterns).
• Optional API mode: bring your own GPTZero or Sapling key for higher accuracy on longer text. Opt-in, gated behind an explicit consent checkbox.

What you see
• Red outline + 🤖 badge for high-confidence AI (≥ 75 % by default).
• Amber outline + ⚠️ badge for uncertain (≥ 50 %).
• A floating HM pill (bottom-right) with a per-page count and prev/next arrows to jump between flagged items.
• Click any badge for a details popover: confidence, source, timestamp, and a "Dismiss" button.

What you control
• Global on/off and per-site toggle in the popup.
• Deny-list any domains in Settings.
• AI / uncertain thresholds, minimum text length, badge colors (with presets).

Privacy
• Heuristic mode is fully offline — zero outbound network calls.
• API mode only sends text to the provider you choose, only after you paste a key and accept the consent notice.
• No analytics, no telemetry, no cookies, no remote code, no phoning home.
• Settings, cache, and stats live in chrome.storage.local, sandboxed to the extension. The cache stores hashes and scores only — never your text.

Open source: https://github.com/ssoward/ideas/tree/main/humanmark
```

---

## Single-purpose statement

(Privacy practices tab → "Single purpose")

```
Detect likely AI-generated text on webpages and visually indicate confidence with an outline and a small badge that the user can dismiss or inspect.
```

---

## Permission justifications

(Privacy practices tab → permission rows)

**`storage`**
```
Persist user settings (thresholds, colors, deny-list, chosen API provider, opt-in API key), a per-text-block analysis cache (hash + score + timestamp; never the original text), and lifetime counters shown in the popup.
```

**`alarms`**
```
Schedule a periodic cleanup task that removes expired entries from the local analysis cache.
```

**`tabs`**
```
Read the current tab's hostname so the popup can show the per-site enable toggle and label which site the toggle applies to. No other tab data is accessed.
```

**`host_permissions: <all_urls>`**
```
The content script must run on whatever page the user is browsing in order to scan visible text and place flags. Users can deny-list any specific sites they don't want scanned via the Settings page.
```

---

## Data usage disclosures

(Privacy practices tab → "What user data does your extension collect?")

| Type | Collected? | Notes |
|---|---|---|
| Personally identifiable info | No | |
| Health info | No | |
| Financial info | No | |
| Authentication info | No | The extension never reads or transmits credentials. The API key (optional) is stored locally only. |
| Personal communications | No | |
| Location | No | |
| Web history | No | We do not log or transmit URLs. |
| User activity | No | |
| Website content | **Conditionally** | Only when the user explicitly enables API mode and provides their own key, the analyzed text is sent to the user's chosen detection provider (GPTZero or Sapling). Heuristic mode is fully offline. |

**Certification check-boxes** (all should be checkable):
- [x] I do not sell or transfer user data to third parties for purposes unrelated to the item's single purpose.
- [x] I do not use or transfer user data for purposes unrelated to the item's single purpose.
- [x] I do not use or transfer user data to determine creditworthiness or for lending purposes.

---

## Privacy policy URL

After pushing the latest commit (which includes `PRIVACY.md`), this URL works:

```
https://github.com/ssoward/ideas/blob/main/humanmark/PRIVACY.md
```

Or for a raw, plain-text version:

```
https://raw.githubusercontent.com/ssoward/ideas/main/humanmark/PRIVACY.md
```

GitHub-hosted policies are accepted by Web Store review.

---

## Distribution

- **Visibility**: pick **Unlisted** for the first review (installable via direct link, but not surfaced in store search). Once you've validated the listing renders well and works as expected, switch to **Public**.
- **Regions**: All regions
- **Mature content**: No
- **Pricing**: Free

---

## Screenshots — what to capture

You need at least **one** PNG at **1280×800** or **640×400**. Upload up to 5. Suggested shots:

1. **LinkedIn feed** with two or three flagged comments — shows the red outline and the 🤖 AI badge with percent. Pick a screen with a real recruiter post or comment that scores high.
2. **A blog article** with a single flagged paragraph and the popover open showing confidence + source.
3. **Google Search results page** with a few flagged AI snippets and the HM pill in the bottom-right showing a count.
4. **Settings page** showing thresholds, color presets, deny list.
5. **Popup** with stats and the per-site toggle.

Tip: Chrome → DevTools → Cmd+Shift+P → "Capture full size screenshot" or use the device toolbar at 1280×800.

**Promotional tile** (optional but encouraged): 440×280 PNG with the HM logo and tagline like "Spot AI-generated text".

---

## After approval

1. Receive approval email.
2. Switch visibility from Unlisted → Public if you want store search exposure.
3. Tag the release locally:
   ```
   git tag -a v0.3.4 -m "v0.3.4 — first public release" && git push origin v0.3.4
   ```
4. Future updates: bump version (`manifest.json` + `package.json`), `./scripts/package.sh`, upload the new zip in the dashboard, fill release notes, submit. Re-review for major version bumps; minor updates often auto-publish.
