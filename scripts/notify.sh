#!/bin/bash
# Send a notification to Slack via the CLI bridge
# Usage: ./notify.sh "Your message here" ["Optional title"]

PORT="${CLI_BRIDGE_PORT:-3848}"
MESSAGE="$1"
TITLE="${2:-Notification}"

if [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <message> [title]"
  exit 1
fi

PAYLOAD=$(cat <<EOF
{"message": "$MESSAGE", "title": "$TITLE"}
EOF
)

curl -s -X POST "http://127.0.0.1:${PORT}/notify" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"

echo ""
