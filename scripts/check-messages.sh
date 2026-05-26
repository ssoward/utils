#!/usr/bin/env bash
# Check for incoming Slack messages queued by the bot
# Usage: ./scripts/check-messages.sh [--all] [--mark-read] [--limit N]

PORT="${CLI_BRIDGE_PORT:-3848}"
BASE="http://127.0.0.1:${PORT}"

UNREAD="true"
MARK_READ="false"
LIMIT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)       UNREAD="false"; shift ;;
    --mark-read) MARK_READ="true"; shift ;;
    --limit)     LIMIT="$2"; shift 2 ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
  esac
done

URL="${BASE}/messages?unread=${UNREAD}&mark_read=${MARK_READ}"
[ -n "$LIMIT" ] && URL="${URL}&limit=${LIMIT}"

curl -s "$URL" | jq .
