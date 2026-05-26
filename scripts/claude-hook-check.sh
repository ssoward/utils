#!/usr/bin/env bash
# Claude Code hook script — surfaces unread Slack messages with content
# Registered as a UserPromptSubmit hook so Claude sees incoming messages each turn
# Session-aware: derives a short ID from TERM_SESSION_ID and scopes message polling

PORT="${CLI_BRIDGE_PORT:-3848}"
BASE_URL="http://127.0.0.1:${PORT}"

# --- Session ID derivation ---
# Derive a short session ID from TERM_SESSION_ID (hash → first 4 hex chars, prefixed cc-)
# Falls back to a random ID if TERM_SESSION_ID is not set
derive_session_id() {
  if [ -n "$TERM_SESSION_ID" ]; then
    local cache_file="/tmp/claude-session-${TERM_SESSION_ID}.id"
    if [ -f "$cache_file" ]; then
      cat "$cache_file"
      return
    fi
    local hash
    hash=$(printf '%s' "$TERM_SESSION_ID" | shasum -a 256 | cut -c1-4)
    local sid="cc-${hash}"
    echo "$sid" > "$cache_file"
    echo "$sid"
  else
    # No TERM_SESSION_ID — use a random fallback, cached per shell PID
    local cache_file="/tmp/claude-session-pid-$$.id"
    if [ -f "$cache_file" ]; then
      cat "$cache_file"
      return
    fi
    local hash
    hash=$(head -c 16 /dev/urandom | shasum -a 256 | cut -c1-4)
    local sid="cc-${hash}"
    echo "$sid" > "$cache_file"
    echo "$sid"
  fi
}

SESSION_ID=$(derive_session_id)

# --- Auto-register session (idempotent) ---
# Use a flag file so we only register once per terminal session
REGISTER_FLAG="/tmp/claude-session-registered-${SESSION_ID}"
if [ ! -f "$REGISTER_FLAG" ]; then
  REG_RESULT=$(curl -s -X POST "${BASE_URL}/sessions/register" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${SESSION_ID}\",\"termSessionId\":\"${TERM_SESSION_ID:-}\"}" 2>/dev/null)
  if [ $? -eq 0 ]; then
    touch "$REGISTER_FLAG"
  fi
fi

# --- Poll for messages scoped to this session ---
# Always poll regardless of WebSocket status. The MCP channel server provides
# real-time visibility (dashboard, notifications), but only the hook can deliver
# ACTION REQUIRED tasks that trigger Claude Code to act.
RESULT=$(curl -s "${BASE_URL}/messages?unread=true&mark_read=true&session_id=${SESSION_ID}" 2>/dev/null)

if [ $? -ne 0 ]; then
  exit 0
fi

COUNT=$(echo "$RESULT" | jq -r '.count // 0' 2>/dev/null)

if [ "$COUNT" -gt 0 ] 2>/dev/null; then
  echo "ACTION REQUIRED: ${COUNT} Slack task(s) for session ${SESSION_ID}."
  echo "You MUST execute these tasks BEFORE responding to the user's direct message."
  echo "After completing each task, reply in the Slack thread: POST http://127.0.0.1:${PORT}/reply with {channel, text, threadTs}."
  echo ""
  echo "$RESULT" | jq -r '.messages[] | "=== SLACK TASK (EXECUTE NOW) ===\nChannel: \(.channel)\nThreadTs: \(.messageTs)\nRef: \(.id)\nTask: \(.text)\n================================\n"' 2>/dev/null
fi
