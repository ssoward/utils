# HumanMark — User Guide

Just installed HumanMark? This page walks through everything you'll see and how to use it. No technical knowledge required.

---

## What HumanMark does

It scans the visible text on whichever webpage you're reading and draws a **colored outline** around blocks it suspects are AI-generated, with a small **percent badge** floating above each one.

- 🤖 **Red outline** + **AI ~XX%** badge → high-confidence AI (75 % or higher).
- ⚠️ **Amber outline** + **~XX%** badge → uncertain (50–74 %). Could be either.
- No outline → looks human, or there isn't enough text to evaluate.

You decide what to do with the information. HumanMark never blocks anything, never reports anything anywhere — it just adds the visual hint.

---

## What you'll see after installing

### 1. The toolbar icon

Click the **HM** icon at the top-right of Chrome (you may need to pin it via the puzzle-piece menu). The popup shows:

- **On/off toggle** — global switch. Turns the whole extension off if you ever want quiet.
- **Stats** — total blocks scanned, total flagged, and how many came from the cache. Lifetime counters.
- **Site toggle** — disable HumanMark just on the site you're currently on (e.g., your company's intranet).
- **Settings** link — opens the full preferences page.
- **Mode label** — "Heuristic mode" by default; shows the API name if you've configured one.

### 2. The HM pill (bottom-right of every page)

A small floating pill that looks like:

```
HM ◀ 3/12 ▶
```

- The number is **how many flags HumanMark has placed on this page** out of the total: `current/total`.
- **◀ ▶ arrows** jump between flagged blocks (smooth-scrolls and pulses the outline).
- **Click "HM"** to hide all flags temporarily — useful if a flag is in the way of something you're reading. Click again to show.
- **Drag the pill** anywhere on the screen if it's covering content. Position is remembered for the tab.
- The arrows are greyed out when there are no flags yet (page still scanning, or none found).

### 3. The badges (above flagged text)

Small pill chips just above the top-left corner of each flagged block:

```
🤖 AI ~89%        ⚠️ ~57%
```

**Click a badge** to open a small details popover:

| Field | Meaning |
|---|---|
| **Confidence** | Percent score from the analyzer. Higher = more confident the text is AI-generated. |
| **Source** | Where the score came from (see below — this is the bit users ask about). |
| **Analyzed** | When the analysis ran. |
| **Dismiss this flag** | Removes the badge and outline for this block until you reload the tab. |

Press **Escape**, scroll, or click anywhere outside to close the popover.

---

## Reading the "Source" field

This trips up most new users, so here's the full picture:

| Source label | What it means |
|---|---|
| **heuristic (offline)** | Default. The score was computed locally by HumanMark's built-in rules. Nothing left your browser. ~80 % accuracy on prose. |
| **cached** | The exact same text was already scored within the last 24 hours; HumanMark reused the previous result instead of re-analyzing. Identical to the original analysis. |
| **gptzero (API)** / **sapling (API)** | You've configured a third-party AI-detection API. The text was sent to that provider for a more accurate score. Only happens if you set this up — see below. |

**Default install = heuristic + cached only.** No outbound network calls happen unless you explicitly enable API mode.

---

## Switching to API mode (optional, for higher accuracy)

The offline heuristic is good enough for casual use. If you want sharper accuracy on long-form content (essays, articles, summaries), wire up an API.

### GPTZero (free tier, recommended)

1. Sign up at **https://gptzero.me** (free; 10,000 words/month at no cost).
2. Dashboard → **API Keys** → create a key, copy it.
3. Click **HM toolbar icon** → **Settings**.
4. **Provider** → select **GPTZero**.
5. **API Key** → paste your key.
6. Tick the **privacy consent checkbox** (required — text from analyzed blocks gets sent to GPTZero).
7. Click **Save Settings**.
8. Refresh any open tab. New badges should now say **Source: gptzero (API)** in the popover.

### Sapling (paid, ~$0.002 per 1k characters)

Same steps, but pick **Sapling** in the provider dropdown and use a Sapling key from https://sapling.ai.

### Going back to offline

Open Settings → **Provider** → **Heuristic only (offline, no key needed)** → Save. Your key stays stored locally; you can switch back any time.

---

## Settings tour

Open the popup → **Settings** to reach the full preferences page. Sections:

### Detection API
The provider/key/consent flow described above.

### Detection Thresholds
- **AI threshold** (default 75 %) — score at which a block gets the red 🤖 badge.
- **Uncertain threshold** (default 50 %) — minimum score for the amber ⚠️ badge. Below this = no flag.
- **Minimum text length (chars)** (default 60) — blocks shorter than this are skipped entirely. Raise this if you're getting false positives on captions and short snippets; lower it to catch shorter posts (Twitter-style).

Tip: if HumanMark feels too aggressive, raise the AI threshold to 80–85 %. If it misses things you're certain are AI, lower it to 65–70 %.

### Flag Colors
Pick any color for the AI and uncertain badges, or click a preset (Neon, Classic, Purple/Blue, Matrix). Useful if the default pink clashes with a site's design.

### Site Deny-List
One hostname per line — e.g. `mybank.com`, `internal.work.com`. HumanMark will not scan these sites at all. Use this for:
- Banking / financial portals (no reason to scan there)
- Internal company tools where you don't want any analysis happening
- Sites where the heuristic is consistently wrong and noisy

You can also disable a site one-off by clicking the per-site toggle in the popup — that's equivalent to adding the host here.

---

## Accuracy expectations — read this once

HumanMark is a **hint, not a verdict.** AI-text detection is a hard, unsolved problem. Even commercial APIs get it wrong sometimes. Specifically:

- **The offline heuristic is roughly 80 % accurate on long-form prose.** It's noisier on short text, technical content, lists, and non-English text.
- **False positives happen.** Predictable, well-edited human writing (corporate press releases, formal reports, FAQ pages) can score high even when written by a human.
- **False negatives happen too.** A skilled writer or a well-prompted model can produce text that scores low even when it is AI.
- **HumanMark is calibrated for English prose.** Other languages, code, lyrics, and poetry will be unreliable.
- **Threshold tuning matters.** If a category of content always gets flagged wrong on your typical sites, adjust the thresholds in Settings.

If a flag is wrong, click the badge → **Dismiss this flag**. That hides it for the session.

---

## Troubleshooting

### "I don't see any flags on this page."
- Has HumanMark finished scanning? Wait a few seconds after page load.
- Check the HM pill at bottom-right — does it say `0`? Then nothing on this page met the criteria.
- Is the global toggle on? (Click the HM icon — first toggle.)
- Is this site in your deny-list? (Settings → Site Deny-List, or popup → site toggle.)
- Is the text long enough? Below 60 chars by default, blocks are ignored.
- Does the text have terminal punctuation? Single sentences below 100 chars get skipped to avoid false positives.

### "The badges are stuck after I clicked another menu item / switched tabs in a SPA."
Should auto-clear in v0.3.4+. If you see lingering badges, refresh the page. (We've fixed this for LinkedIn, Google Search, and other SPAs — please open an issue if you still hit it.)

### "I got a flag on UI text / a form / a button."
Forms and elements containing inputs are excluded as of v0.3.5. If you still see one, please open an issue with the page URL.

### "The HM pill is covering content."
- Drag it anywhere on screen. Position is remembered for the session.
- Or click **HM** to hide all flags temporarily.

### "I want to start fresh."
Open Chrome → `chrome://extensions` → HumanMark → **Remove**. Then reinstall from the store. This wipes all settings, cache, and stats.

### "I configured an API and it's still saying heuristic."
- Did you check the privacy-consent checkbox in Settings? It's required.
- Is the key valid? (HumanMark falls back to heuristic silently on API errors. Check the provider's dashboard for quota or auth errors.)
- Is the text shorter than the minimum length? Short blocks bypass the API to save quota.
- Did you click **Save Settings**?

### "I want to clear the cache."
Cache entries auto-expire in 24 hours. If you want immediate reset, remove and reinstall the extension.

---

## FAQ

**Does HumanMark see everything I read?**
No. The content script only **scans visible text blocks** — paragraphs, posts, comments, search snippets. It does not read URLs, form inputs (those are skipped), passwords, or UI controls.

**Does HumanMark send my browsing history anywhere?**
No. Heuristic mode is fully offline. API mode only sends the text of analyzed blocks to the provider you chose, only after you opt in.

**Can other websites read my API key?**
No. The key lives in `chrome.storage.local`, which is sandboxed to this extension. Web pages have no access to it. The key is also redacted (`•••`) when settings are passed through internal extension messages.

**Can HumanMark see what I type into form fields?**
No. Forms, fieldsets, and any element containing an input/textarea/select/button are explicitly skipped.

**What about sites with end-to-end encryption (Gmail, banking)?**
HumanMark works on rendered text in your browser. It only sees what your browser already shows you. But if you don't want the extension touching banking or webmail, deny-list those sites — that's exactly what the deny list is for.

**Does it work on PDFs?**
No. PDF viewers usually don't expose text in a way our content script can read.

**Does it work in iframes / embedded YouTube comments / etc.?**
Sometimes. Most embedded widgets run in cross-origin iframes that the extension's content script doesn't run inside. For now, only the top-level document is reliably scanned.

**Why does the same text sometimes get a different score?**
It shouldn't, with caching. If you see a score change for unchanged text within 24 hours, the text probably changed slightly (an extra space, an emoji added) — that produces a different cache key. After 24 hours, the cache expires and re-analysis happens.

**Is the source open?**
Yes — https://github.com/ssoward/ideas/tree/main/humanmark

**How do I report a bug or suggest a feature?**
https://github.com/ssoward/ideas/issues

---

## Quick reference card

| Action | How |
|---|---|
| Hide all flags for a moment | Click the **HM** pill at bottom-right |
| Jump between flagged blocks | **◀ ▶** arrows on the pill |
| See score details | Click any badge |
| Dismiss a wrong flag | Click badge → **Dismiss this flag** |
| Disable on this site | HM toolbar icon → site toggle |
| Disable everywhere | HM toolbar icon → top toggle |
| Change colors / thresholds | HM toolbar icon → **Settings** |
| Use a paid API for accuracy | Settings → pick provider → paste key → consent → save |
