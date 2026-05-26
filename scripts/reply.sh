#!/usr/bin/env bash
# Reply to a Slack channel/thread
# Usage: ./scripts/reply.sh <channel> <text> [thread_ts]

PORT="${CLI_BRIDGE_PORT:-3848}"
BASE="http://127.0.0.1:${PORT}"

CHANNEL="$1"
TEXT="$2"
THREAD_TS="$3"

if [ -z "$CHANNEL" ] || [ -z "$TEXT" ]; then
  echo "Usage: $0 <channel> <text> [thread_ts]"
  exit 1
fi

BODY="{\"channel\":\"${CHANNEL}\",\"text\":\"${TEXT}\""
[ -n "$THREAD_TS" ] && BODY="${BODY},\"threadTs\":\"${THREAD_TS}\""
BODY="${BODY}}"

curl -s -X POST "${BASE}/reply" \
  -H "Content-Type: application/json" \
  -d "$BODY" | jq .
