# Release process

Day-to-day publishing uses the Chrome Web Store Publish API via [`chrome-webstore-upload-cli`](https://github.com/fregante/chrome-webstore-upload-cli). Two commands instead of dashboard clicks.

## One-time setup

You need three OAuth values that the CLI uses to talk to Google. Once obtained, they're reusable forever — store them in `.env` (gitignored).

### 1. Create a Google Cloud project and enable the Chrome Web Store API

1. Visit https://console.cloud.google.com.
2. Top header → project picker → **New Project**. Name it something like `humanmark-publish`. Create.
3. Make sure that project is selected.
4. Sidebar → **APIs & Services** → **Library**.
5. Search **Chrome Web Store API** → click → **Enable**.

### 2. Configure the OAuth consent screen

1. Sidebar → **APIs & Services** → **OAuth consent screen**.
2. User type: **External** → Create.
3. Fill the required fields:
   - App name: `humanmark-publish-cli`
   - User support email: your email
   - Developer contact email: your email
4. **Scopes** screen — leave defaults, Save and continue.
5. **Test users** screen — add your own publisher Google account (`scott.soward@gmail.com`). Save.
6. Back to OAuth consent screen — leave **Publishing status** as "Testing". You don't need to submit for verification; the app will only ever auth your own account.

### 3. Create OAuth client credentials

1. Sidebar → **APIs & Services** → **Credentials** → **+ Create Credentials** → **OAuth client ID**.
2. Application type: **Desktop app**.
3. Name: `humanmark-cli`.
4. Create — a dialog shows your **Client ID** and **Client secret**. Copy both. You can also download the JSON.

### 4. Generate a refresh token

The CLI ships a helper that walks you through the OAuth dance and prints the refresh token at the end:

```bash
npx chrome-webstore-upload-keys
```

It will:
- Prompt for the Client ID and Client secret you just got.
- Open a browser tab asking you to sign in with the publisher Google account and approve scope.
- Print a `refresh_token` value.

(There may be a Google warning that the app isn't verified — click **Advanced → Go to humanmark-publish-cli (unsafe)**. It's "unsafe" only in the sense that Google hasn't reviewed an app you wrote for yourself.)

### 5. Save credentials

```bash
cp .env.example .env
# edit .env, paste in CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN
```

EXTENSION_ID is already filled in the template.

`.env` is in `.gitignore` — never commit it.

## Day-to-day release loop

After the initial setup, every release is:

```bash
# 1. Make code changes
# 2. Bump version in manifest.json + package.json
# 3. Add a CHANGELOG.md entry
# 4. Commit, push to main

# 5. Build, package, upload (does NOT publish — uploads as draft)
npm run release

# 6. Verify in the dashboard that the new package looks right
#    https://chrome.google.com/webstore/devconsole

# 7. Publish (submits for review; users get the update after approval)
npm run release:publish
```

`npm run release` runs:
1. `npm run build` — production bundle into `dist/`
2. `npm run package` — wraps `dist/` into `humanmark-v<version>.zip`
3. `npm run release:upload` — uploads the zip via API, leaves as draft

Splitting upload from publish gives you a sanity check in the dashboard before triggering the review queue. If you trust the change end-to-end and want one command, run:

```bash
npm run release && npm run release:publish
```

## Available scripts

| Command | What it does |
|---|---|
| `npm run dev` | Watch build into `dist/` |
| `npm run build` | One-shot production build |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run package` | Wrap `dist/` into a versioned zip |
| `npm run release:upload` | Upload the existing zip as draft |
| `npm run release:publish` | Submit the current draft for review |
| `npm run release` | build → package → upload (no publish) |

## Caveats

- **Don't run `release:upload` while a previous version is in review.** The upload cancels the in-flight review and pushes you to the back of the queue. Wait for **Published** status.
- **Review still applies.** The CLI just bypasses the dashboard UI; Google still reviews each submission, especially with `<all_urls>` host permission.
- **Refresh tokens can expire** if the Google account changes password or 2FA settings. If a release fails with "invalid_grant", re-run `npx chrome-webstore-upload-keys` to mint a new refresh token.
- **Don't put the Client ID, Client secret, or refresh token in CI logs.** Use repository secrets if/when you wire up GitHub Actions.

## Optional: GitHub Actions CI

A tag-triggered release workflow that builds and uploads on `git push --tags` is one possible next step. The PlasmoHQ/bpp action wraps `chrome-webstore-upload-cli` for CI use:

```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
        working-directory: humanmark
      - run: npm run build && npm run package
        working-directory: humanmark
      - uses: PlasmoHQ/bpp@v3
        with:
          keys: ${{ secrets.SUBMIT_KEYS }}
          artifact: humanmark/humanmark-${{ github.ref_name }}.zip
```

`SUBMIT_KEYS` is a single repository secret holding all four values as JSON:

```json
{
  "$schema": "https://raw.githubusercontent.com/PlasmoHQ/bpp/main/keys.schema.json",
  "chrome": {
    "zip": "humanmark/humanmark-<version>.zip",
    "clientId": "...",
    "clientSecret": "...",
    "refreshToken": "...",
    "extID": "picgigikbhpifiockbpnlpfedfmbihan"
  }
}
```
