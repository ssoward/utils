# slack-bot

A Slack bot for Mac system monitoring and Claude Code integration, using Socket Mode.

## Features

- **System Monitoring** — CPU, memory, disk, and battery status via slash commands
- **Scheduled Health Checks** — periodic battery/disk threshold alerts
- **Claude Code Integration** — webhook receiver for Claude Code events, bidirectional messaging
- **CLI Bridge** — HTTP API for external tools to send notifications and read messages
- **Session-Scoped Messaging** — multiple Claude Code sessions register with unique IDs and receive only messages addressed to them
- **Real-Time Channels** — WebSocket-based push delivery of Slack messages to Claude Code via MCP channel server (no polling required)
- **Web Dashboard** — browser-based dashboard at `/dashboard` with real-time chat, system status, session monitor, and message history

## Architecture

```
Slack (Socket Mode)
  ├── Slash commands (/status, /battery, /cpu, /memory, /disk, /uptime, /notify, /run, /claude)
  ├── @mentions → message queue → Claude Code sessions
  └── DMs → message queue → Claude Code sessions

CLI Bridge (HTTP :3848)
  ├── POST /notify          — send notification to Slack
  ├── POST /status          — post full system status
  ├── POST /reply           — reply in a Slack thread
  ├── GET  /messages        — read queued messages (supports session_id filtering)
  ├── POST /messages/mark-read — mark messages as read
  ├── DELETE /messages      — clear the queue
  ├── POST /sessions/register — register a Claude Code session
  ├── GET  /sessions        — list active sessions (includes wsConnected status)
  ├── DELETE /sessions/:id  — unregister a session
  ├── GET  /dashboard       — web dashboard UI
  ├── GET  /api/status      — raw system status JSON
  └── WS   /ws              — WebSocket endpoint for real-time message push

Hook Receiver (HTTP :3847)
  └── POST /hook            — receive Claude Code events → post to Slack

Scheduler
  └── Periodic battery & disk threshold checks → Slack alerts
```

## Setup

### Prerequisites

- Node.js 20+
- A Slack app with Socket Mode enabled, bot token, app token, and signing secret

### Environment Variables

Create a `.env` file:

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_SIGNING_SECRET=...
SLACK_CHANNEL_ID=C0...           # Channel for bot messages
ALLOWED_USER_ID=U0...            # Optional: restrict commands to one user
HOOK_PORT=3847                   # Claude hook receiver port (default: 3847)
CLI_BRIDGE_PORT=3848             # CLI bridge port (default: 3848)
SCHEDULER_INTERVAL_MINUTES=30   # Health check interval (default: 30)
MAX_QUEUE_MESSAGES=200           # Max queued messages (default: 200)
BATTERY_LOW_THRESHOLD=20         # Battery alert threshold (default: 20%)
DISK_USAGE_HIGH_THRESHOLD=90     # Disk alert threshold (default: 90%)
```

### Install and Run

```bash
npm install
npm run build
npm run dev     # development (tsx)
npm start       # production (compiled)
```

## Session-Scoped Messaging

Multiple Claude Code sessions can share the same bot without message collisions.

### How It Works

1. Each Claude Code session derives a short ID from `TERM_SESSION_ID` (SHA-256 hash → first 4 hex chars, prefixed `cc-`, e.g., `cc-817c`)
2. The hook script auto-registers the session on first run via `POST /sessions/register`
3. When polling `GET /messages?session_id=cc-817c`, only messages addressed to that session (or unaddressed broadcasts) are returned
4. Stale sessions (>60 min idle) are cleaned automatically

### Addressing a Session from Slack

```
@bot cc-817c: do the thing
```

The `cc-XXXX:` prefix routes the message to that specific session. Messages without a prefix are visible to all sessions (first to poll claims it).

### Session Endpoints

```bash
# Register
curl -s -X POST http://127.0.0.1:3848/sessions/register \
  -H "Content-Type: application/json" \
  -d '{"id":"cc-a3f2","termSessionId":"optional-term-id"}'

# List active sessions
curl -s http://127.0.0.1:3848/sessions

# Unregister
curl -s -X DELETE http://127.0.0.1:3848/sessions/cc-a3f2
```

### Sending Notifications with Session Tag

```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"Done","title":"Task Complete","sessionId":"cc-a3f2"}'
```

This prefixes the title in Slack: `[cc-a3f2] Task Complete`.

## Real-Time Channels (WebSocket + MCP)

The pull-based hook polling is reliable but introduces latency — messages only arrive when the user types a prompt. The **channel server** provides push-based, real-time delivery.

### How It Works

```
Slack → Bot (existing) → WebSocket push → Channel Server (MCP) → Claude Code
                                                      ↓
Claude Code → reply/notify tools → Channel Server → HTTP → Bot → Slack
```

1. Bot receives a @mention or DM, enqueues it, **and pushes it over WebSocket** to connected channel servers
2. Channel server converts the message to an MCP logging notification
3. Claude Code receives it immediately — no user prompt needed
4. Claude does the work, then calls `slack_reply` or `slack_notify` tools exposed by the channel server
5. Channel server forwards replies to the bot's HTTP endpoints

### Setup

The channel server is configured in `.mcp.json` and launched automatically by Claude Code:

```json
{
  "mcpServers": {
    "slack-channel": {
      "command": "npx",
      "args": ["tsx", "channel-server/server.ts"],
      "env": { "SLACK_BOT_PORT": "3848", "AUTONOMOUS": "true" }
    }
  }
}
```

Start Claude Code with the MCP server active — the channel server will:
1. Derive the session ID from `TERM_SESSION_ID` (same as the hook script)
2. Register with the bot via `POST /sessions/register`
3. Connect to `ws://127.0.0.1:3848/ws?session_id=cc-XXXX`
4. Deliver incoming messages as MCP notifications in real-time
5. **Autonomously execute** each incoming task via `claude -p` and reply in the Slack thread

### Autonomous Execution (Embedded)

When `AUTONOMOUS` is set (enabled by default), the channel server automatically spawns `claude -p` for each incoming Slack message, captures the output, and posts it as a reply in the originating Slack thread. This happens in addition to MCP notification delivery, so the active Claude Code session still sees the messages.

```
Slack message → Channel Server → MCP notification (passive visibility)
                       ↓
               claude -p (autonomous) → Slack reply
```

**Configuration:**

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `AUTONOMOUS` | `true` | Set to `"false"` to disable autonomous execution |
| `AUTONOMOUS_MAX_TURNS` | `25` | Max agentic turns per task |
| `AUTONOMOUS_TIMEOUT_MS` | `300000` | Timeout per task (5 minutes) |
| `AUTONOMOUS_WORKING_DIR` | `process.cwd()` | Default working directory for spawned claude processes |

**Per-Task Working Directory:**

You can override the working directory for a single task by prefixing the message with `pwd=<path>`:

```
@bot cc-a9cd: pwd=/Users/ssoward/other-project run the tests
@bot cc-a9cd: pwd=~/my-app what files are in src/
```

- `pwd=` must appear immediately after the session prefix (or at the start if no session prefix)
- Supports absolute paths and `~` expansion
- If the directory does not exist, the task is skipped and an error is posted in the Slack thread
- Without `pwd=`, the default `AUTONOMOUS_WORKING_DIR` is used

**Safety:**
- Sequential processing — one task at a time
- 5-minute timeout per task
- 10 MB output buffer cap
- Spawned `claude -p` uses `--allowedTools` without MCP tools, preventing recursive execution
- `execFile` with callback ensures child stdout never touches MCP stdio transport

### WebSocket Protocol

Clients connect to `ws://127.0.0.1:3848/ws?session_id=cc-XXXX`. The bot validates the session against the registry.

Messages are JSON:
```json
{ "type": "message", "message": { "id": "...", "text": "...", "channel": "...", ... } }
```

The server sends pings every 30s; clients must respond with pong to stay alive.

### Hook Script

The hook script always polls for messages regardless of WebSocket status. The channel server provides real-time visibility (dashboard, MCP notifications), while the hook provides actionable task delivery that triggers Claude Code to act.

### Channel Server Tools

| Tool | Purpose |
|------|---------|
| `slack_reply` | Reply in a Slack thread (channel, text, thread_ts) |
| `slack_notify` | Post a status notification (title, message) |

## Standalone Watcher Daemon (Fallback)

> **Note:** The channel server now includes embedded autonomous execution (see above). This standalone watcher is a fallback option for environments where the MCP channel server is not available.

The watcher daemon (`scripts/slack-watcher.sh`) provides autonomous task execution via polling. It polls for Slack messages addressed to a session, invokes `claude -p` for each task, and replies in the Slack thread.

### How It Works

```
┌─────────────────────────────────────────────────┐
│  slack-watcher.sh (runs in a terminal)          │
│                                                 │
│  loop every 5s:                                 │
│    GET /messages?session_id=cc-XXXX&mark_read=1 │
│    for each message:                            │
│      claude -p "<task prompt>"                  │
│      POST /reply with claude's output           │
│    done                                         │
│  done                                           │
└─────────────────────────────────────────────────┘
```

1. Watcher registers a session with the bot on startup
2. Polls `GET /messages` every 5 seconds for unread messages
3. For each message, builds a prompt and invokes `claude -p`
4. Captures the output and posts it as a reply in the originating Slack thread
5. All activity is visible in the terminal where the watcher runs

### Usage

```bash
# Auto-derive session from TERM_SESSION_ID
./scripts/slack-watcher.sh

# Or specify a session ID explicitly
./scripts/slack-watcher.sh cc-817c
```

Then send a Slack message:
```
@bot cc-817c: what files are in the src directory
```

The watcher picks it up, runs `claude -p`, and replies in-thread.

### Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `POLL_INTERVAL` | `5` | Seconds between polls |
| `MAX_BUDGET` | `1.00` | Budget cap per task (USD) |
| `CLI_BRIDGE_PORT` | `3848` | Bot HTTP port |

### Design Decisions

- **`claude -p` (print mode)** — each task is processed and exits, no interactive session
- **Sequential processing** — one task at a time to avoid race conditions
- **Thread replies** — output is posted in the originating Slack thread
- **Visible output** — all activity prints to the terminal for monitoring

## CLI Bridge API

### POST /notify

Send a notification to Slack.

```bash
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"Build passed","title":"CI Update"}'
```

### POST /status

Collect and post full system status (CPU, memory, disk, battery) to Slack.

```bash
curl -s -X POST http://127.0.0.1:3848/status
```

### GET /messages

Read queued incoming messages. Query params:

| Param | Default | Description |
|-------|---------|-------------|
| `unread` | `true` | Set to `false` to include read messages |
| `mark_read` | `false` | Set to `true` to mark returned messages as read |
| `limit` | all | Max messages to return (when `unread=false`) |
| `session_id` | none | Filter to messages visible to this session |

```bash
curl -s "http://127.0.0.1:3848/messages?mark_read=true&session_id=cc-817c"
```

### POST /reply

Reply in a Slack thread.

```bash
curl -s -X POST http://127.0.0.1:3848/reply \
  -H "Content-Type: application/json" \
  -d '{"channel":"C0B4YDF6T5X","text":"Got it","threadTs":"1234567890.123456"}'
```

## Claude Code Hook Integration

The hook script (`scripts/claude-hook-check.sh`) is registered as a `UserPromptSubmit` hook. On each user prompt:

1. Derives or retrieves the session ID from `TERM_SESSION_ID`
2. Registers with the bot (idempotent, first run only)
3. Polls `GET /messages` scoped to the session
4. Outputs messages as **actionable tasks** — Claude Code treats each delivered message as a user instruction, executes the request, and replies in the originating Slack thread

Messages are formatted as task blocks so Claude Code acts on them rather than treating them as passive notifications.

## Web Dashboard

Open `http://127.0.0.1:3848/dashboard` in a browser to access the real-time dashboard.

**Panels:**
- **System Status** — CPU, memory, disk, battery with progress bars (auto-refreshes every 10s)
- **Sessions** — Active Claude Code sessions with WebSocket connection indicators
- **Chat** — Real-time incoming Slack messages via WebSocket + compose/send messages through the bot
- **Message History** — Queued messages with read/unread state, mark-read and clear controls

The dashboard registers itself as a `dash-XXXX` session and connects over the existing WebSocket endpoint. No additional ports or dependencies required.

### API Status Endpoint

`GET /api/status` returns raw system metrics as JSON (unlike `POST /status` which posts to Slack):

```bash
curl -s http://127.0.0.1:3848/api/status | jq .
```

## Testing

```bash
npm test          # run all tests
npm run build     # type-check
```

79 tests across 4 test suites:
- `session-registry.test.ts` — session registration, cleanup, staleness
- `message-queue.test.ts` — enqueue, read/unread, session filtering, queue limits
- `cli-bridge.test.ts` — all HTTP endpoints including session management
- `ws-bridge.test.ts` — WebSocket connection, session validation, message push, disconnect cleanup

## Project Structure

```
src/
├── index.ts                 Main app entry point
├── config.ts                Environment variable config
├── types.ts                 TypeScript interfaces
├── commands/                Slack slash commands
├── monitors/                System metrics (CPU, memory, disk, battery)
├── scheduler/               Periodic health check jobs
├── dashboard/               Web dashboard UI
├── notifier/
│   ├── slack-sender.ts      Slack message sending
│   ├── cli-bridge.ts        HTTP API server
│   └── ws-bridge.ts         WebSocket server for real-time push
├── claude-hook/             Claude Code event webhook
├── message-queue/           Incoming message persistence
├── session-registry/        Claude Code session tracking
└── utils/                   Logger, formatter, exec helpers
scripts/
├── claude-hook-check.sh     UserPromptSubmit hook for message polling
└── slack-watcher.sh         Autonomous watcher daemon for headless task execution
channel-server/
├── server.ts                MCP channel server for real-time Slack ↔ Claude Code
└── package.json             Channel server dependencies
```

## Recent Changes

- **Embedded autonomous execution** — The MCP channel server now automatically spawns `claude -p` for each incoming Slack task and replies in-thread. Enabled by default via `AUTONOMOUS=true` in `.mcp.json`. No separate daemon required — every Claude Code session with the channel server gets autonomous task execution built in. Configurable max turns, timeout, and working directory. Disable with `AUTONOMOUS=false`.
- **Standalone watcher daemon (fallback)** — `scripts/slack-watcher.sh` polls for Slack messages and invokes `claude -p` for each task without any manual prompt. Replies are posted in the originating Slack thread. Configurable poll interval and per-task budget cap.
- **Hook script fix** — Removed the WebSocket early-exit bug in `scripts/claude-hook-check.sh` that prevented ACTION REQUIRED task delivery when the MCP channel server was connected. The hook now always polls for messages.
- **Web dashboard** — Browser-based dashboard at `GET /dashboard` with four panels: system status (CPU/memory/disk/battery), active sessions, real-time chat via WebSocket, and message history with read/unread controls. Also adds `GET /api/status` for raw system metrics JSON. No new dependencies or ports.
- **Real-time channels** — WebSocket bridge (`src/notifier/ws-bridge.ts`) pushes Slack messages to connected MCP channel servers in real-time. Channel server (`channel-server/server.ts`) converts messages to MCP notifications and exposes `slack_reply`/`slack_notify` tools. Hook script auto-skips polling when a channel is active. Configured via `.mcp.json`.
- **Session-scoped messaging** — Each Claude Code session gets a unique `cc-XXXX` ID derived from `TERM_SESSION_ID`. Sessions register with the bot, and Slack users can address specific sessions with `@bot cc-XXXX: message`. Messages without a prefix are broadcast to all sessions.
- **Session registry** — New `src/session-registry/` module with file-based persistence (`data/sessions.json`), automatic stale session cleanup (>60 min), and idempotent re-registration.
- **Session API endpoints** — `POST /sessions/register`, `GET /sessions`, `DELETE /sessions/:id` on the CLI bridge.
- **Session-filtered message polling** — `GET /messages?session_id=cc-XXXX` returns only messages targeted to that session or unaddressed broadcasts.
- **Session-tagged notifications** — `POST /notify` with `sessionId` field prefixes the Slack title with `[cc-XXXX]`.
- **Actionable hook output** — The hook script now frames delivered Slack messages as tasks with explicit instructions to execute and reply in-thread, rather than displaying them as passive log entries.

## License

Private project.
