#!/usr/bin/env bash
# brpaul-gmail-auth.sh — one-time Google OAuth dance for Brother Paul.
#
# Prereqs:
#   1. Google Cloud Console → APIs & Services → OAuth consent screen → set up
#      (External, Testing, add your own email as a test user).
#   2. APIs & Services → Library → enable "Gmail API".
#   3. APIs & Services → Credentials → Create credentials → OAuth client ID
#      → Application type: "Desktop app". Note the Client ID + Client Secret.
#
# Usage:
#   ./bin/brpaul-gmail-auth.sh <CLIENT_ID> <CLIENT_SECRET>
#
# What it does:
#   - Starts a localhost HTTP server on 127.0.0.1:8765
#   - Opens your browser to Google's consent screen
#   - Captures the auth code, exchanges it for a refresh token
#   - Prints the refresh token (and a ready-to-paste config snippet)
#
# The refresh token never expires (until you revoke it). Paste it into
# ~/Library/Application Support/BrotherPaul/config.json under
# missionControl.gmail.refreshToken.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <CLIENT_ID> <CLIENT_SECRET>" >&2
    exit 1
fi

CLIENT_ID="$1"
CLIENT_SECRET="$2"
PORT="${BRPAUL_OAUTH_PORT:-8765}"
REDIRECT="http://127.0.0.1:${PORT}"
SCOPE="https://www.googleapis.com/auth/gmail.readonly"

# 1. Open consent URL.
AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth"
AUTH_URL+="?client_id=${CLIENT_ID}"
AUTH_URL+="&redirect_uri=${REDIRECT}"
AUTH_URL+="&response_type=code"
AUTH_URL+="&scope=${SCOPE}"
AUTH_URL+="&access_type=offline"
AUTH_URL+="&prompt=consent"

echo "Opening browser for consent…"
echo "  $AUTH_URL"
open "$AUTH_URL" || true

# 2. Listen for the redirect on localhost.
echo "Waiting for redirect on ${REDIRECT} (Ctrl+C to cancel)…"
# Read a single HTTP request and reply with a tiny confirmation page.
RESPONSE=$(
    /usr/bin/nc -l "$PORT" <<'EOF' &
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: 96
Connection: close

<html><body><h2>Brother Paul: code captured.</h2>You can close this tab.</body></html>
EOF
    wait $!
)

# 3. Parse the code from the GET line.
CODE=$(printf '%s\n' "$RESPONSE" | awk 'NR==1 { match($2, /code=[^& ]+/); print substr($2, RSTART+5, RLENGTH-5) }')
if [[ -z "$CODE" ]]; then
    echo "Failed to find ?code= in incoming request. Raw line was:" >&2
    echo "$RESPONSE" | head -1 >&2
    exit 1
fi
echo "Got authorization code (length ${#CODE})."

# 4. Exchange code for tokens.
TOKEN_RESP=$(
    curl -sS https://oauth2.googleapis.com/token \
        -d "client_id=${CLIENT_ID}" \
        -d "client_secret=${CLIENT_SECRET}" \
        -d "code=${CODE}" \
        -d "grant_type=authorization_code" \
        -d "redirect_uri=${REDIRECT}"
)

REFRESH=$(printf '%s' "$TOKEN_RESP" | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("refresh_token", ""))
')

if [[ -z "$REFRESH" ]]; then
    echo "No refresh_token in response. Full response:" >&2
    printf '%s\n' "$TOKEN_RESP" >&2
    exit 1
fi

cat <<EOF

✓ Success. Add the following under "missionControl" in your config.json:

  "gmail": {
    "clientID":     "${CLIENT_ID}",
    "clientSecret": "${CLIENT_SECRET}",
    "refreshToken": "${REFRESH}"
  }

Then in the BrotherPaul menu choose "Reload Config" (or quit + relaunch).
EOF
