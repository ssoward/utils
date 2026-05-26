#!/usr/bin/env bash
# slack-watcher.sh — Autonomous Slack task executor for Claude Code
#
# Polls the slack-bot CLI bridge for unread messages targeted at a session,
# then invokes `claude -p` for each task and replies in the Slack thread.
#
# Usage:
#   ./scripts/slack-watcher.sh              # auto-derive session from TERM_SESSION_ID
#   ./scripts/slack-watcher.sh cc-817c      # specify session explicitly
#   POLL_INTERVAL=10 ./scripts/slack-watcher.sh   # custom poll interval (seconds)
#   MAX_BUDGET=2.00 ./scripts/slack-watcher.sh    # custom budget cap per task

set -euo pipefail

PORT="${CLI_BRIDGE_PORT:-3848}"
BASE_URL="http://127.0.0.1:${PORT}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
MAX_BUDGET="${MAX_BUDGET:-1.00}"
CWD="$(pwd)"

# --- Session ID ---
derive_session_id() {
  if [ -n "${1:-}" ]; then
    echo "$1"
    return
  fi
  if [ -n "${TERM_SESSION_ID:-}" ]; then
    local hash
    hash=$(printf '%s' "$TERM_SESSION_ID" | shasum -a 256 | cut -c1-4)
    echo "cc-${hash}"
  else
    echo "cc-watcher-$$"
  fi
}

SESSION_ID=$(derive_session_id "${1:-}")

# --- Colors for terminal output ---
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
RED='\033[31m'
RESET='\033[0m'

log() {
  echo -e "${DIM}[$(date '+%H:%M:%S')]${RESET} $*"
}

# --- Cleanup on exit ---
cleanup() {
  log "${YELLOW}Shutting down watcher for ${SESSION_ID}...${RESET}"
  curl -s -X DELETE "${BASE_URL}/sessions/${SESSION_ID}" 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

# --- Check prerequisites ---
if ! command -v claude &>/dev/null; then
  echo -e "${RED}Error: 'claude' CLI not found in PATH${RESET}" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}Error: 'jq' not found in PATH${RESET}" >&2
  exit 1
fi

# --- Wait for bot to be reachable ---
log "Waiting for slack-bot at ${BASE_URL}..."
until curl -sf "${BASE_URL}/sessions" &>/dev/null; do
  sleep 2
done

# --- Register session ---
curl -s -X POST "${BASE_URL}/sessions/register" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"${SESSION_ID}\"}" >/dev/null 2>&1

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Slack Watcher — Autonomous Task Executor${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Session:        ${GREEN}${SESSION_ID}${RESET}"
echo -e "  Bot URL:        ${BASE_URL}"
echo -e "  Working dir:    ${CWD}"
echo -e "  Poll interval:  ${POLL_INTERVAL}s"
echo -e "  Budget cap:     \$${MAX_BUDGET}/task"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${DIM}Send a Slack message: @bot ${SESSION_ID}: <your task>${RESET}"
echo -e "  ${DIM}Press Ctrl+C to stop${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

TASK_COUNT=0

# --- Main loop ---
while true; do
  # Poll for unread messages
  RESPONSE=$(curl -s "${BASE_URL}/messages?unread=true&mark_read=true&session_id=${SESSION_ID}" 2>/dev/null) || {
    sleep "$POLL_INTERVAL"
    continue
  }

  COUNT=$(echo "$RESPONSE" | jq -r '.count // 0' 2>/dev/null) || COUNT=0

  if [ "$COUNT" -eq 0 ] 2>/dev/null; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Process each message
  MESSAGES=$(echo "$RESPONSE" | jq -c '.messages[]' 2>/dev/null)

  while IFS= read -r MSG; do
    TASK_COUNT=$((TASK_COUNT + 1))
    TEXT=$(echo "$MSG" | jq -r '.text // ""')
    CHANNEL=$(echo "$MSG" | jq -r '.channel // ""')
    MSG_TS=$(echo "$MSG" | jq -r '.messageTs // ""')
    USER_ID=$(echo "$MSG" | jq -r '.userId // "unknown"')
    MSG_ID=$(echo "$MSG" | jq -r '.id // ""')

    # Strip session prefix from task text (e.g., "cc-817c: do the thing" -> "do the thing")
    TASK_TEXT=$(echo "$TEXT" | sed -E "s/^${SESSION_ID}:[[:space:]]*//" | sed -E 's/^cc-[0-9a-f]+:[[:space:]]*//')

    echo ""
    log "${BOLD}${GREEN}━━━ Task #${TASK_COUNT} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    log "  From:    ${USER_ID}"
    log "  Channel: ${CHANNEL}"
    log "  Task:    ${TASK_TEXT}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""

    # Build the prompt for claude -p
    PROMPT="You are an autonomous Claude Code agent responding to a Slack task.
Working directory: ${CWD}

Task from Slack user ${USER_ID} in channel ${CHANNEL}:
${TASK_TEXT}

After completing the task, output a brief summary of what you did.
Do not ask questions — make reasonable decisions and proceed."

    # Invoke claude -p
    log "${CYAN}Invoking claude -p...${RESET}"
    CLAUDE_OUTPUT=""
    if CLAUDE_OUTPUT=$(claude -p "$PROMPT" \
      --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
      --max-turns 25 \
      2>&1); then
      log "${GREEN}claude -p completed successfully${RESET}"
    else
      log "${RED}claude -p exited with non-zero status${RESET}"
    fi

    # Truncate output for Slack reply (max ~3000 chars to stay under Slack limits)
    REPLY_TEXT="$CLAUDE_OUTPUT"
    if [ ${#REPLY_TEXT} -gt 3000 ]; then
      REPLY_TEXT="${REPLY_TEXT:0:2900}

... (output truncated — ${#CLAUDE_OUTPUT} chars total)"
    fi

    # Reply in the Slack thread
    if [ -n "$CHANNEL" ] && [ -n "$MSG_TS" ]; then
      REPLY_JSON=$(jq -n \
        --arg channel "$CHANNEL" \
        --arg text "$REPLY_TEXT" \
        --arg threadTs "$MSG_TS" \
        '{channel: $channel, text: $text, threadTs: $threadTs}')

      REPLY_RESULT=$(curl -s -X POST "${BASE_URL}/reply" \
        -H "Content-Type: application/json" \
        -d "$REPLY_JSON" 2>/dev/null) || true

      log "${GREEN}Replied in Slack thread${RESET}"
    else
      log "${YELLOW}No channel/threadTs — skipping Slack reply${RESET}"
    fi

    # Print summary
    echo ""
    log "${DIM}--- Output (Task #${TASK_COUNT}) ---${RESET}"
    echo "$CLAUDE_OUTPUT"
    log "${DIM}--- End Output ---${RESET}"
    echo ""

  done <<< "$MESSAGES"

  sleep "$POLL_INTERVAL"
done
