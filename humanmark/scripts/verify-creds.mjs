// Non-mutating credential check — exchanges the refresh token for an access
// token via Google's OAuth endpoint. Confirms .env is wired correctly without
// touching the Chrome Web Store API at all.
import { readFileSync } from "fs";

const env = {};
for (const line of readFileSync(new URL("../.env", import.meta.url), "utf8").split("\n")) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2];
}

const required = ["CLIENT_ID", "CLIENT_SECRET", "REFRESH_TOKEN", "EXTENSION_ID"];
for (const k of required) {
  if (!env[k]) {
    console.error(`Missing ${k} in .env`);
    process.exit(1);
  }
}

const body = new URLSearchParams({
  client_id: env.CLIENT_ID,
  client_secret: env.CLIENT_SECRET,
  refresh_token: env.REFRESH_TOKEN,
  grant_type: "refresh_token",
});

const res = await fetch("https://oauth2.googleapis.com/token", {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body,
});
const data = await res.json();

if (!res.ok || !data.access_token) {
  console.error("✗ Credential check failed at OAuth token exchange.");
  console.error(JSON.stringify(data, null, 2));
  process.exit(1);
}

console.log("✓ OAuth token exchange succeeded.");
console.log(`  Scope: ${data.scope ?? "(default)"}`);

// Now confirm the Chrome Web Store API can be reached for our specific item.
// GET /items/{id}?projection=DRAFT is read-only — confirms the extension ID
// is valid and the access token has the right permissions, without touching
// any state.
const itemRes = await fetch(
  `https://www.googleapis.com/chromewebstore/v1.1/items/${env.EXTENSION_ID}?projection=DRAFT`,
  {
    headers: {
      Authorization: `Bearer ${data.access_token}`,
      "x-goog-api-version": "2",
    },
  }
);
const itemData = await itemRes.json();

if (!itemRes.ok) {
  console.error("✗ Chrome Web Store API call failed.");
  console.error(JSON.stringify(itemData, null, 2));
  process.exit(1);
}

console.log("✓ Chrome Web Store API reachable for this item.");
console.log(`  Extension ID: ${env.EXTENSION_ID}`);
console.log(`  Upload state: ${itemData.uploadState ?? "(unknown)"}`);
console.log(`  Public key fingerprint: ${(itemData.publicKey ?? "(none)").slice(0, 60)}…`);
if (itemData.crxVersion) console.log(`  Latest crx version: ${itemData.crxVersion}`);
if (itemData.itemError && itemData.itemError.length > 0) {
  console.log(`  Item warnings: ${itemData.itemError.length}`);
  for (const e of itemData.itemError) console.log(`    - ${e.error_code}: ${e.error_detail ?? ""}`);
}
console.log("\n✓ CLI is fully wired. You can run `npm run release` when ready.");
