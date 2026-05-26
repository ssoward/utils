---
name: slack-status
description: Post status updates to the ssoward-sandbox Slack channel. **AUTO-ACTIVATE when: (1) completing any task or feature implementation, (2) finishing a build or test run, (3) encountering significant errors or blockers, (4) user says "post status", "update slack", "notify slack", "send status", or "slack update".** Posts system status and task completion messages via the slack-bot CLI bridge.
---

# Slack Status Updates

Post status updates to the `ssoward-sandbox` Slack channel via the slack-bot CLI bridge running on `127.0.0.1:3848`.

## When to Post

**Always post a Slack update when:**
- Completing a task, feature, or bugfix
- Build or test results are available (pass or fail)
- Encountering a significant error or blocker
- Starting a major task (brief "starting X" message)
- User explicitly requests a status update

## How to Post

### Task completion / freeform update
```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"<what was done>","title":"<short title>"}'
```

### Task completion with session tag
```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"<what was done>","title":"<short title>","sessionId":"cc-a3f2"}'
```

### Full system status report (CPU, memory, disk, battery)
```bash
curl -s -X POST http://127.0.0.1:3848/status
```

### Reply to a specific Slack thread
```bash
curl -s -X POST http://127.0.0.1:3848/reply \
  -H "Content-Type: application/json" \
  -d '{"channel":"C0B4YDF6T5X","text":"<message>","threadTs":"<thread_ts>"}'
```

### Check for incoming Slack messages (all sessions)
```bash
curl -s http://127.0.0.1:3848/messages?mark_read=true
```

### Check for incoming Slack messages (scoped to session)
```bash
curl -s "http://127.0.0.1:3848/messages?mark_read=true&session_id=cc-a3f2"
```

## Message Guidelines

- Keep messages concise (1-3 sentences)
- Include what was done and the outcome (pass/fail/blocked)
- For errors, include the key error message
- Use a descriptive title that summarizes the update

## Examples

**After completing a feature:**
```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"Added bidirectional Slack messaging with message queue, 4 new API endpoints, and shell scripts. Build clean, 31 tests passing.","title":"Feature Complete: Slack Messaging"}'
```

**After a test run:**
```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"All 31 tests passing across 2 test files (message-queue, cli-bridge).","title":"Tests Passing"}'
```

**When hitting a blocker:**
```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"Build failing: TypeScript error in src/index.ts - event.user type mismatch. Investigating.","title":"Build Error"}'
```

## Important Notes

- The bot must be running (`npm run dev` in the slack-bot project) for posts to work
- If the curl fails (connection refused), the bot is not running — skip the post silently and continue working
- Channel ID for ssoward-sandbox: `C0B4YDF6T5X`
- Do not let a failed Slack post block your actual work
