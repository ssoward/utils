# slack-bot Project Instructions

## Overview

This is a Slack-driven Claude Code agent. It runs as a background service and executes coding tasks sent via Slack messages. Thread replies continue conversations with full context.

## Slack Status Updates

**Always post status updates to Slack** when completing tasks or encountering errors.

```bash
# Task completion notification
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"<what was done>","title":"<short title>"}'

# Submit a task programmatically
curl -s -X POST http://127.0.0.1:3848/agent/task \
  -H "Content-Type: application/json" \
  -d '{"text":"<task description>"}'

# Check agent status
curl -s http://127.0.0.1:3848/agent/status

# Check incoming Slack messages
curl -s http://127.0.0.1:3848/messages?mark_read=true
```

If the bot is not running (connection refused), skip silently and continue working.

## Handling Incoming Slack Messages

**CRITICAL: When the hook delivers Slack messages marked as "Slack Task", you MUST act on them BEFORE responding to anything else in the conversation.** These are user instructions arriving via Slack and have the same priority as direct chat messages.

**Execution order when Slack tasks are present:**
1. Read the Slack task message text
2. Execute the requested work (write code, run tests, update docs, etc.)
3. Reply in the Slack thread to confirm what was done
4. Then respond to any direct chat message from the user

**Reply in Slack thread after completing the task:**
```bash
curl -s -X POST http://127.0.0.1:3848/reply \
  -H "Content-Type: application/json" \
  -d '{"channel":"<channel>","text":"<what was done>","threadTs":"<messageTs>"}'
```
