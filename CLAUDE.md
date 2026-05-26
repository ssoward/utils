# slack-bot Project Instructions

## Slack Status Updates

**Always post status updates to Slack** when completing tasks, finishing builds/tests, or encountering errors. The bot runs on `127.0.0.1:3848`.

```bash
# Task completion notification
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"<what was done>","title":"<short title>"}'

# Task completion with session tag (prefixes title in Slack with [cc-XXXX])
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"<what was done>","title":"<short title>","sessionId":"cc-a3f2"}'

# Full system status report
curl -s -X POST http://127.0.0.1:3848/status

# Check incoming Slack messages (all sessions)
curl -s http://127.0.0.1:3848/messages?mark_read=true

# Check incoming Slack messages (scoped to a session)
curl -s "http://127.0.0.1:3848/messages?mark_read=true&session_id=cc-a3f2"
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

**Do NOT:**
- Ignore Slack tasks because a direct chat message is also present
- Treat Slack tasks as informational context or metadata
- Simply acknowledge the Slack message without doing the work
- Wait for the user to repeat the instruction in direct chat

## Session Management

Multiple Claude Code sessions can register with unique IDs to scope messaging.

```bash
# Register a session
curl -s -X POST http://127.0.0.1:3848/sessions/register \
  -H "Content-Type: application/json" \
  -d '{"id":"cc-a3f2"}'

# List active sessions
curl -s http://127.0.0.1:3848/sessions

# Unregister a session
curl -s -X DELETE http://127.0.0.1:3848/sessions/cc-a3f2
```

Slack users can target a session by prefixing: `@bot cc-a3f2: do the thing`.
