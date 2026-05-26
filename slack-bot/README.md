# Slack-Driven Claude Code Agent

A personal coding assistant controlled via Slack. Send tasks as Slack messages, get results back in-thread. Thread replies continue conversations with full context.

## Features

- **Conversational task execution** -- @mention or DM the bot with a coding task; it spawns `claude -p` and replies with the result
- **Thread-based context** -- reply in a thread to continue the conversation with full history
- **Built-in commands** -- `help`, `status`, `sessions`, `history` available directly in Slack
- **CLI bridge API** -- HTTP API with agent routes for programmatic task submission and status
- **MCP channel server** -- thin bridge exposing `slack_reply` and `slack_notify` tools
- **WebSocket real-time delivery** -- push-based message delivery to connected clients

## Architecture

```
Slack (Socket Mode)
  ├── @mentions → Router → Executor (claude -p)
  ├── DMs → Router → Executor (claude -p)
  └── Thread replies → Router → Session Manager → Executor (with context)

CLI Bridge (HTTP :3848)
  ├── POST /notify           — send notification to Slack
  ├── POST /reply            — reply in a Slack thread
  ├── GET  /messages         — read queued messages
  ├── POST /messages/mark-read — mark messages as read
  ├── DELETE /messages       — clear the queue
  ├── POST /sessions/register — register a Claude Code session
  ├── GET  /sessions         — list active sessions
  ├── DELETE /sessions/:id   — unregister a session
  ├── GET  /agent/status     — executor status (busy/idle, queue)
  ├── POST /agent/task       — submit a task programmatically
  ├── GET  /agent/sessions   — list conversation sessions
  ├── GET  /agent/sessions/:channel/:threadTs — get session history
  └── WS   /ws              — WebSocket for real-time message push
```

## Setup

### Prerequisites

- Node.js 22+
- A Slack app with Socket Mode enabled, bot token, app token, and signing secret

### Environment Variables

Create a `.env` file:

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_SIGNING_SECRET=...
SLACK_CHANNEL_ID=C0...           # Channel for bot messages

CLI_BRIDGE_PORT=3848             # CLI bridge port (default: 3848)
MAX_QUEUE_MESSAGES=200           # Max queued messages (default: 200)

# Agent configuration
AGENT_WORKING_DIR=/Users/you/projects   # Working directory for claude -p
AGENT_MAX_TURNS=25                      # Max agentic turns per task (default: 25)
AGENT_TIMEOUT_MS=300000                 # Timeout per task in ms (default: 300000)
AGENT_ALLOWED_TOOLS=Bash,Read,Write,Edit,Glob,Grep  # Tools available to claude -p
AGENT_MODEL=                            # Model override (default: empty, uses default)
AGENT_SESSION_TTL_HOURS=24              # Session history TTL in hours (default: 24)
```

### Install and Run

```bash
npm install
npm run build
npm run dev     # development (tsx)
npm start       # production (compiled)
```

## Usage

### Slack Interaction

**Start a task** by @mentioning the bot or sending a DM:

```
@bot refactor the login function in src/auth.ts
```

**Continue a conversation** by replying in the thread:

```
(in thread) now add error handling for the edge case where token is expired
```

**Override working directory** with the `pwd=` prefix:

```
@bot pwd=/Users/me/other-project run the tests
@bot pwd=~/my-app what files are in src/
```

**Built-in commands** (no `claude -p` invocation):

| Command | Description |
|---------|-------------|
| `help` | Show available commands |
| `status` | Show executor status (busy/idle, queue depth) |
| `sessions` | List active conversation sessions |
| `history` | Show conversation history for current thread |

### Programmatic API

```bash
# Submit a task
curl -s -X POST http://127.0.0.1:3848/agent/task \
  -H "Content-Type: application/json" \
  -d '{"text":"run the test suite"}'

# Check executor status
curl -s http://127.0.0.1:3848/agent/status

# List conversation sessions
curl -s http://127.0.0.1:3848/agent/sessions

# Send a notification to Slack
curl -s -X POST http://127.0.0.1:3848/notify \
  -H "Content-Type: application/json" \
  -d '{"message":"Build passed","title":"CI"}'
```

## Project Structure

```
src/
├── index.ts                 Entry point — Bolt app, delegates to router
├── config.ts                Environment config (agent-focused)
├── types.ts                 TypeScript interfaces
├── agent/
│   ├── executor.ts          Task execution (claude -p management)
│   ├── session-manager.ts   Thread → conversation history mapping
│   └── router.ts            Message routing + built-in commands
├── slack/
│   ├── sender.ts            Slack message posting
│   ├── cli-bridge.ts        HTTP API server
│   └── ws-bridge.ts         WebSocket server
├── message-queue/           Incoming message persistence
├── session-registry/        External session tracking (MCP clients)
└── utils/                   Logger, exec helpers
channel-server/
├── server.ts                MCP channel server (thin bridge)
└── package.json
scripts/
├── notify.sh
├── reply.sh
└── check-messages.sh
```

## Testing

```bash
npm test          # run all tests
npm run build     # type-check
```

Test suites:

- `session-registry.test.ts` -- session registration, cleanup, staleness
- `message-queue.test.ts` -- enqueue, read/unread, session filtering, queue limits
- `cli-bridge.test.ts` -- all HTTP endpoints including agent routes
- `ws-bridge.test.ts` -- WebSocket connection, session validation, message push
- `config.test.ts` -- environment variable parsing and defaults
- `executor.test.ts` -- task execution, queuing, timeout, error handling
- `session-manager.test.ts` -- conversation history, TTL, context building
- `router.test.ts` -- message routing, built-in commands, pwd parsing

## License

Private project.
