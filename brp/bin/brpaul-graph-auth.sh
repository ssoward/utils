#!/usr/bin/env bash
# brpaul-graph-auth.sh — one-time Microsoft identity OAuth dance for the
# Brother Paul Graph (Outlook calendar) integration. Uses PKCE so no client
# secret is required.
#
# Prereqs:
#   1. https://entra.microsoft.com → App registrations → New registration
#        Name: Brother Paul
#        Supported account types: pick one —
#          • "Accounts in this organizational directory only" (work-only, SSO),
#          • "Accounts in any organizational directory + personal" (broadest).
#        Redirect URI: leave blank, we'll add it next.
#      → Register.
#   2. In the new app → Authentication → Add a platform → "Mobile and desktop
#      applications" → custom URI: http://localhost:8765 → Configure → Save.
#      Also turn on "Allow public client flows" → Yes → Save.
#   3. API permissions → Add → Microsoft Graph → Delegated → Calendars.Read →
#      Add. (Grant admin consent if your tenant requires it.)
#   4. From the Overview page, copy the "Application (client) ID".
#
# Usage:
#   ./bin/brpaul-graph-auth.sh <CLIENT_ID>
#
# Optional:
#   BRPAUL_TENANT=<guid|"organizations"|"common">     # default: common
#   BRPAUL_OAUTH_PORT=8765                            # default: 8765
#
# What it does:
#   - Generates a PKCE verifier + challenge.
#   - Opens your browser to Microsoft's consent screen.
#   - Captures the auth code on a one-shot localhost listener.
#   - Exchanges code + verifier for a refresh token.
#   - Prints a config.json snippet you paste into BrotherPaul.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <CLIENT_ID>" >&2
    echo "  Set BRPAUL_TENANT to your tenant GUID for SSO-restricted accounts." >&2
    exit 1
fi

CLIENT_ID="$1"
TENANT="${BRPAUL_TENANT:-common}"
PORT="${BRPAUL_OAUTH_PORT:-8765}"
REDIRECT="http://localhost:${PORT}"
SCOPE="Calendars.Read offline_access"

# --- PKCE: code_verifier + code_challenge (S256) ---
VERIFIER=$(openssl rand 64 | base64 | tr -d '\n=' | tr '+/' '-_' | head -c 64)
CHALLENGE=$(printf '%s' "$VERIFIER" \
    | openssl dgst -sha256 -binary \
    | base64 \
    | tr -d '\n=' \
    | tr '+/' '-_')

urlenc() {
    /usr/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

SCOPE_ENC=$(urlenc "$SCOPE")
REDIRECT_ENC=$(urlenc "$REDIRECT")

AUTH_URL="https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/authorize"
AUTH_URL+="?client_id=${CLIENT_ID}"
AUTH_URL+="&response_type=code"
AUTH_URL+="&redirect_uri=${REDIRECT_ENC}"
AUTH_URL+="&response_mode=query"
AUTH_URL+="&scope=${SCOPE_ENC}"
AUTH_URL+="&code_challenge=${CHALLENGE}"
AUTH_URL+="&code_challenge_method=S256"
AUTH_URL+="&prompt=select_account"

echo "Opening browser for consent…"
echo "  $AUTH_URL"
open "$AUTH_URL" || true

echo "Waiting for redirect on ${REDIRECT}…"
RESPONSE=$(
    /usr/bin/nc -l "$PORT" <<'EOF'
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: 96
Connection: close

<html><body><h2>Brother Paul: code captured.</h2>You can close this tab.</body></html>
EOF
)

CODE=$(printf '%s\n' "$RESPONSE" | awk 'NR==1 { match($2, /code=[^& ]+/); print substr($2, RSTART+5, RLENGTH-5) }')
if [[ -z "$CODE" ]]; then
    echo "Couldn't find ?code= in the redirect. Raw line:" >&2
    printf '%s\n' "$RESPONSE" | head -1 >&2
    exit 1
fi
echo "Code captured (length ${#CODE}). Exchanging for refresh token…"

TOKEN_RESP=$(
    curl -sS "https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "scope=${SCOPE}" \
        --data-urlencode "code=${CODE}" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "redirect_uri=${REDIRECT}" \
        --data-urlencode "code_verifier=${VERIFIER}"
)

REFRESH=$(printf '%s' "$TOKEN_RESP" | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("refresh_token", ""))
')

if [[ -z "$REFRESH" ]]; then
    echo "No refresh_token in response:" >&2
    printf '%s\n' "$TOKEN_RESP" >&2
    exit 1
fi

cat <<EOF

✓ Success. Add the following under "missionControl" in your config.json
(replacing the empty graph block already there):

  "includeGraphCalendar": true,
  "graph": {
    "clientID":     "${CLIENT_ID}",
    "tenant":       "${TENANT}",
    "refreshToken": "${REFRESH}"
  }

Then choose "Reload Config" from the BrotherPaul menu, open Mission Control,
and click Refresh. Your Outlook calendar events will appear in the Events
section.
EOF
