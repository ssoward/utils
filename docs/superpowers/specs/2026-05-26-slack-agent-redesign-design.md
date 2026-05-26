# Slack-Driven Claude Code Agent - Design Spec

**Date:** 2026-05-26
**Status:** Draft
**Purpose:** Transform the slack-bot from a system monitoring tool into a personal Claude Code agent controlled entirely via Slack.

---

## 1. Overview

The app becomes a background macOS service that runs a Claude Code agent you control through Slack. Send it tasks via @mention or DM, get results in-thread. Continue conversations by replying in a thread. No slash commands, no system monitoring - just a coding assistant available 24/7 via Slack.

### Core Interaction Model

- **New top-level message** (DM or @mention) = new single-shot task
- **Reply in a Slack thread** = continue that task's conversation (persistent context)
- All agent output appears as replies in the originating thread
- Thread becomes the full conversation history for that task

---

## 2. Architecture

### Component Diagram

```
Slack (Cloud, Socket Mode)
        |
        v
+------------------+
| Bolt App         |  src/index.ts - thin message router
| (Socket Mode)    |
+--------+---------+
         |
    +----+----+
    |         |
    v         v
New Msg    Thread Reply
    |         |
    v         v
+--------+ +------------------+
| Task   | | Session Manager  |
| Runner | | (thread->session) |
+---+----+ +--------+---------+
    |                |
    v                v
claude -p       claude -p
(single-shot)   (with context replay)
    |                |
    +-------+--------+
            |
            v
    Slack Thread Reply
    (slack-sender.ts)
```

### Process Model

Single Node.js process running:
1. **Slack Bolt app** - Socket Mode connection to Slack
2. **Task executor** - Manages `claude -p` child processes
3. **Session manager** - Maps Slack threads to conversation histories
4. **CLI bridge** (HTTP, port 3848) - Local API for external tools/scripts
5. **WebSocket server** - Real-time event push (attached to CLI bridge)

### Data Flow

1. User sends message in Slack (DM or @mention)
2. Bolt app receives event via Socket Mode
3. Router checks: is this a new message or a thread reply?
   - **New message**: Create task record, spawn `claude -p` with message as prompt
   - **Thread reply**: Look up session for this thread, append message to context, spawn `claude -p` with full conversation history as prompt
4. Post immediate acknowledgment in thread ("Working on it...")
5. `claude -p` executes with allowed tools, produces output
6. Post result in thread (replace or follow up on acknowledgment)
7. Store the exchange (user message + agent response) in session history

---

## 3. Components to Remove

All of these are cleanly isolated and can be deleted without affecting the core Slack/messaging infrastructure:

| Component | Files | Reason |
|-----------|-------|--------|
| System monitors | `src/monitors/*` | No longer needed - not a monitoring tool |
| Slash commands | `src/commands/*` | Replaced by conversational interface |
| Scheduler | `src/scheduler/*` | Health check alerts removed |
| Hook receiver | `src/claude-hook/*` | Agent IS Claude Code; no external hook needed |
| Dashboard | `src/dashboard/*` | Web UI not needed for MVP; can add later |
| Hook script | `scripts/claude-hook-check.sh` | Replaced by direct Slack integration |
| Watcher daemon | `scripts/slack-watcher.sh` | Replaced by built-in executor |
| Metric formatters | `src/utils/format.ts` | System metric formatting no longer needed |
| launchd plist | `launchd/*` | Will need a new one; old config references monitoring |

### Files to Keep and Modify

| Component | Files | Changes |
|-----------|-------|---------|
| Entry point | `src/index.ts` | Strip command registration, simplify to message router |
| Config | `src/config.ts` | Remove monitoring configs, add agent configs |
| Types | `src/types.ts` | Remove system types, add agent/session types |
| Slack sender | `src/notifier/slack-sender.ts` | Keep as-is, rename module to `src/slack/` |
| CLI bridge | `src/notifier/cli-bridge.ts` | Strip monitoring routes, keep message/session/notify routes |
| WebSocket bridge | `src/notifier/ws-bridge.ts` | Keep as-is for real-time events |
| Message queue | `src/message-queue/*` | Extend with task status lifecycle |
| Session registry | `src/session-registry/*` | Extend to map Slack threads to conversation history |
| Logger | `src/utils/logger.ts` | Keep as-is |
| Exec util | `src/utils/exec.ts` | Keep as-is |

### Files to Keep As-Is

| Component | Files |
|-----------|-------|
| Channel server | `channel-server/server.ts` | Keep as MCP integration point |
| Helper scripts | `scripts/notify.sh`, `scripts/reply.sh`, `scripts/check-messages.sh` |
| MCP config | `.mcp.json` |

---

## 4. New Components

### 4.1 Task Executor (`src/agent/executor.ts`)

Replaces the channel server's embedded autonomous execution with a proper module in the main app.

**Responsibilities:**
- Spawn `claude -p` child processes
- Manage execution lifecycle (start, monitor, timeout, complete)
- Sequential execution with a queue (one task at a time)
- Capture and return output

**Configuration:**
- `AGENT_MAX_TURNS` (default: 25) - max agentic turns per invocation
- `AGENT_TIMEOUT_MS` (default: 300000) - 5-minute timeout per invocation
- `AGENT_WORKING_DIR` (default: configurable) - default working directory
- `AGENT_ALLOWED_TOOLS` (default: `Bash,Read,Write,Edit,Glob,Grep`) - tool allowlist
- `AGENT_MODEL` (optional) - model override

**Interface:**
```typescript
interface TaskRequest {
  prompt: string;
  workingDir?: string;          // override default
  conversationHistory?: string; // for thread continuations
  threadTs: string;             // Slack thread identifier
  channel: string;              // Slack channel
}

interface TaskResult {
  output: string;
  exitCode: number;
  timedOut: boolean;
  durationMs: number;
}

function executeTask(request: TaskRequest): Promise<TaskResult>
```

**Execution mechanics:**
- Uses `execFile('claude', ['-p', prompt, ...flags])` with callback
- Flags: `--allowedTools`, `--max-turns`, `--model` (if set)
- For thread continuations: prepend conversation history to the prompt so the agent has context
- Output buffer capped at 10MB, truncated to 3000 chars for Slack posting
- Working directory validated before execution; falls back to default if invalid

### 4.2 Session Manager (`src/agent/session-manager.ts`)

Maps Slack threads to conversation histories for persistent multi-turn interactions.

**Responsibilities:**
- Track thread-to-session mapping
- Store conversation history (user messages + agent responses)
- Build context prompts for thread continuations
- Clean up stale sessions

**Storage:** File-based JSON at `data/sessions/` (one file per thread, keyed by `channel-threadTs`).

**Session record:**
```typescript
interface AgentSession {
  threadTs: string;
  channel: string;
  createdAt: string;
  lastActiveAt: string;
  workingDir: string;
  exchanges: Array<{
    role: 'user' | 'agent';
    content: string;
    timestamp: string;
  }>;
}
```

**Context replay strategy:**
When a thread reply comes in, build the prompt as:
```
You are continuing a previous conversation. Here is the history:

User: <first message>
Agent: <first response>
User: <second message>
Agent: <second response>
...

User's new message: <current message>
```

This gives `claude -p` full context without needing interactive session persistence.

**Context window management:**
- If conversation history exceeds ~50,000 characters, summarize older exchanges
- Keep the most recent 5 exchanges verbatim, summarize the rest
- Summary generated by a quick `claude -p` call with a summarization prompt

**Stale session cleanup:**
- Sessions with no activity for 24 hours are archived (moved to `data/sessions/archive/`)
- Sessions older than 7 days in archive are deleted
- Cleanup runs on a timer (every hour)

### 4.3 Message Router (`src/agent/router.ts`)

Thin routing logic extracted from `index.ts`.

**Logic:**
```
on message:
  if message is a thread reply:
    look up session by (channel, threadTs)
    if session exists:
      append to conversation, execute with history
    else:
      treat as new task (thread from a non-agent message)
  else (top-level message):
    create new session
    execute as single-shot task
    store result in session (in case user replies in thread later)
```

**Built-in commands** (detected before routing to agent):
- `help` - Show usage instructions
- `status` - Show agent status (busy/idle, current task, queue depth)
- `config workspace <path>` - Set default working directory
- `cancel` - Cancel the currently executing task
- `history` - Show recent task summaries

These are detected by simple string matching on the message text, not slash commands.

### 4.4 Slack Interface Updates

**Acknowledgment behavior:**
- On task receipt: post "Working on this..." with a spinner emoji in the thread
- On completion: post the full result as a follow-up message in the thread
- On error/timeout: post error details in the thread
- On long-running tasks (>30s): update the acknowledgment message with elapsed time

**Message formatting:**
- Code blocks for code output
- Collapsible sections for long output (Slack mrkdwn doesn't support this natively, so truncate with "Full output: <link>" if we add a viewer later)
- Error states clearly marked

**Working directory override:**
- Prefix message with `pwd=/path/to/project` to override for that task
- Example: `pwd=/Users/ssoward/myproject fix the failing tests`
- Already exists in the channel server; promote to the main router

---

## 5. CLI Bridge (HTTP API) Changes

### Routes to Keep

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Health check |
| POST | `/notify` | Post notification to Slack |
| POST | `/reply` | Reply in a Slack thread |
| GET | `/messages` | Get queued messages |
| POST | `/messages/mark-read` | Mark messages as read |
| DELETE | `/messages` | Clear message queue |
| POST | `/sessions/register` | Register external session |
| GET | `/sessions` | List sessions |
| DELETE | `/sessions/:id` | Unregister session |

### Routes to Remove

| Method | Path | Reason |
|--------|------|--------|
| POST | `/status` | System monitoring removed |
| GET | `/dashboard` | Dashboard removed |
| GET | `/api/status` | System metrics removed |

### Routes to Add

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/agent/status` | Agent status (idle/busy, current task, queue) |
| POST | `/agent/task` | Submit a task programmatically |
| GET | `/agent/sessions` | List active conversation sessions |
| GET | `/agent/sessions/:id` | Get conversation history for a session |

---

## 6. Configuration Changes

### Environment Variables

**Remove:**
- `HOOK_PORT` - No hook receiver
- `SCHEDULER_INTERVAL_MINUTES` - No scheduler
- `BATTERY_LOW_THRESHOLD` - No battery monitoring
- `DISK_USAGE_HIGH_THRESHOLD` - No disk monitoring

**Keep:**
- `SLACK_BOT_TOKEN` - Slack auth
- `SLACK_APP_TOKEN` - Socket Mode
- `SLACK_SIGNING_SECRET` - Request verification
- `SLACK_CHANNEL_ID` - Default channel for notifications
- `CLI_BRIDGE_PORT` - HTTP API port (default 3848)
- `MAX_QUEUE_MESSAGES` - Message queue cap

**Add:**
- `AGENT_WORKING_DIR` - Default working directory for tasks
- `AGENT_MAX_TURNS` - Max agentic turns per task (default: 25)
- `AGENT_TIMEOUT_MS` - Task timeout in milliseconds (default: 300000)
- `AGENT_ALLOWED_TOOLS` - Comma-separated tool allowlist (default: Bash,Read,Write,Edit,Glob,Grep)
- `AGENT_MODEL` - Model override (optional, uses default if unset)
- `AGENT_SESSION_TTL_HOURS` - Session inactivity timeout (default: 24)

---

## 7. Channel Server (MCP) Changes

The channel server at `channel-server/server.ts` continues to serve as the MCP integration point for Claude Code sessions that want real-time Slack connectivity.

**Changes:**
- Remove the embedded autonomous execution logic (it moves to `src/agent/executor.ts`)
- Keep MCP tools (`slack_reply`, `slack_notify`)
- Keep WebSocket connection for real-time message delivery
- Keep session registration
- The channel server becomes a thin MCP-to-HTTP bridge

---

## 8. Testing Strategy

### Existing Tests to Update

- `cli-bridge.test.ts` - Remove tests for `/status`, `/dashboard`, `/api/status`; add tests for new `/agent/*` routes
- `message-queue.test.ts` - Add tests for task status lifecycle if we extend the queue
- `session-registry.test.ts` - Keep as-is; thread session manager gets its own tests
- `ws-bridge.test.ts` - Keep as-is

### New Tests

- `executor.test.ts` - Task execution, timeout handling, output capture, working dir validation
- `session-manager.test.ts` - Thread mapping, conversation history, context replay, stale cleanup, context summarization
- `router.test.ts` - Message routing logic, built-in command detection, thread vs new message
- Integration test for end-to-end flow (mock Slack events through to execution)

---

## 9. File Structure (Post-Refactor)

```
src/
  index.ts                    # Entry point: Bolt app + message handlers
  config.ts                   # Environment config (agent-focused)
  types.ts                    # TypeScript interfaces (agent-focused)
  agent/
    executor.ts               # Task execution (claude -p management)
    session-manager.ts        # Thread-to-session mapping + conversation history
    router.ts                 # Message routing logic
  slack/
    sender.ts                 # Slack message posting (renamed from notifier/)
    cli-bridge.ts             # HTTP API server
    ws-bridge.ts              # WebSocket server
  message-queue/
    index.ts
    queue.ts                  # Message queue (with task status)
  session-registry/
    index.ts
    registry.ts               # External session registry (MCP clients)
  utils/
    exec.ts                   # Shell exec wrapper
    logger.ts                 # Structured logger
  __tests__/
    executor.test.ts
    session-manager.test.ts
    router.test.ts
    cli-bridge.test.ts
    message-queue.test.ts
    session-registry.test.ts
    ws-bridge.test.ts
channel-server/
  server.ts                   # MCP channel server (thinned)
  package.json
scripts/
  notify.sh
  reply.sh
  check-messages.sh
data/
  messages.json               # Message queue
  sessions.json               # External session registry
  sessions/                   # Agent conversation sessions (new)
```

---

## 10. Migration Path

This is a refactor, not a rewrite. Steps in order:

1. **Remove monitoring code** - Delete `src/monitors/`, `src/commands/`, `src/scheduler/`, `src/dashboard/`, `src/claude-hook/`, `src/utils/format.ts`, `scripts/claude-hook-check.sh`, `scripts/slack-watcher.sh`, `launchd/`
2. **Restructure directories** - Move `src/notifier/` to `src/slack/`, create `src/agent/`
3. **Build executor** - Port autonomous execution logic from channel server to `src/agent/executor.ts`
4. **Build session manager** - New component for thread-based conversation tracking
5. **Build router** - Extract and simplify message routing from `index.ts`
6. **Update index.ts** - Simplify to thin message handler that delegates to router
7. **Update config** - Remove old env vars, add new agent configs
8. **Update types** - Remove system types, add agent types
9. **Update CLI bridge** - Remove monitoring routes, add agent routes
10. **Thin channel server** - Remove embedded execution, keep MCP bridge
11. **Update tests** - Remove obsolete tests, add new component tests
12. **Update documentation** - README, CLAUDE.md, .env.example

---

## 11. Out of Scope (Future)

These are explicitly not part of this redesign:

- **Web dashboard** - Can add later; Slack is the primary interface
- **Multi-user support** - Personal tool; single user assumed
- **Task prioritization** - Sequential execution; queue is FIFO
- **File attachment handling** - Text messages only
- **Slack interactive components** - No buttons, modals, or dropdown menus (can add later)
- **Agent memory across sessions** - Each thread is independent; no cross-thread learning
- **Streaming output** - Results posted after completion, not streamed
