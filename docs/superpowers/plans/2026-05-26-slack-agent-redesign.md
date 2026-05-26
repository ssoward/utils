# Slack-Driven Claude Code Agent — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the slack-bot from a system monitoring tool into a personal Claude Code agent controlled entirely via Slack, with thread-based conversation persistence and hybrid single-shot/multi-turn execution.

**Architecture:** Refactor in-place. Remove all monitoring code. Keep Slack Bolt + Socket Mode, message queue, session registry, WebSocket bridge, and CLI bridge. Add a new `src/agent/` module containing a task executor (spawns `claude -p`), session manager (maps Slack threads to conversation histories), and message router (dispatches incoming Slack events). The channel server becomes a thin MCP bridge with execution logic removed.

**Tech Stack:** TypeScript, Node.js 22, `@slack/bolt` (Socket Mode), `ws` (WebSocket), `vitest` (testing), `claude` CLI (`claude -p` for execution)

---

## File Structure (Post-Refactor)

```
src/
  index.ts                      # Entry point — Bolt app, delegates to router
  config.ts                     # Environment config (agent-focused)
  types.ts                      # TypeScript interfaces (agent-focused)
  agent/
    executor.ts                 # Spawns claude -p, manages lifecycle
    session-manager.ts          # Thread → conversation history mapping
    router.ts                   # Message routing + built-in commands
  slack/
    sender.ts                   # Slack message posting (moved from notifier/)
    cli-bridge.ts               # HTTP API server (moved from notifier/)
    ws-bridge.ts                # WebSocket server (moved from notifier/)
  message-queue/
    index.ts                    # Re-exports
    queue.ts                    # Message queue
  session-registry/
    index.ts                    # Re-exports
    registry.ts                 # External session registry
  utils/
    exec.ts                     # Shell exec wrapper
    logger.ts                   # Structured logger
  __tests__/
    executor.test.ts            # NEW
    session-manager.test.ts     # NEW
    router.test.ts              # NEW
    cli-bridge.test.ts          # MODIFIED (remove monitoring tests)
    message-queue.test.ts       # KEPT
    session-registry.test.ts    # KEPT
    ws-bridge.test.ts           # KEPT
channel-server/
  server.ts                     # MCP bridge (execution logic removed)
  package.json
scripts/
  notify.sh                     # KEPT
  reply.sh                      # KEPT
  check-messages.sh             # KEPT
```

---

## Task 1: Remove Monitoring Code

**Files:**
- Delete: `src/monitors/index.ts`, `src/monitors/system.ts`, `src/monitors/battery.ts`, `src/monitors/disk.ts`
- Delete: `src/commands/index.ts`, `src/commands/status.ts`, `src/commands/battery.ts`, `src/commands/cpu.ts`, `src/commands/memory.ts`, `src/commands/disk.ts`, `src/commands/uptime.ts`, `src/commands/notify.ts`, `src/commands/run.ts`, `src/commands/claude.ts`
- Delete: `src/scheduler/scheduler.ts`, `src/scheduler/jobs.ts`
- Delete: `src/claude-hook/index.ts`, `src/claude-hook/hook-receiver.ts`, `src/claude-hook/formatters.ts`
- Delete: `src/dashboard/index.ts`, `src/dashboard/dashboard-html.ts`
- Delete: `src/utils/format.ts`
- Delete: `scripts/claude-hook-check.sh`, `scripts/slack-watcher.sh`
- Delete: `launchd/com.ssoward.slack-bot.plist` (if exists)

- [ ] **Step 1: Delete monitoring directories and files**

```bash
rm -rf src/monitors src/commands src/scheduler src/claude-hook src/dashboard
rm -f src/utils/format.ts
rm -f scripts/claude-hook-check.sh scripts/slack-watcher.sh
rm -rf launchd
```

- [ ] **Step 2: Verify the project still compiles (it won't — broken imports)**

```bash
npx tsc --noEmit 2>&1 | head -30
```

Expected: Compilation errors in `src/index.ts` and `src/notifier/cli-bridge.ts` referencing deleted modules. This is expected — we'll fix these in subsequent tasks.

- [ ] **Step 3: Commit the deletions**

```bash
git add -A
git commit -m "chore: remove monitoring, commands, scheduler, dashboard, hooks

Strip all system monitoring code to prepare for agent-focused redesign.
Broken imports in index.ts and cli-bridge.ts will be fixed in next tasks."
```

---

## Task 2: Update Types and Config

**Files:**
- Modify: `src/types.ts`
- Modify: `src/config.ts`
- Modify: `.env.example`

- [ ] **Step 1: Write failing test for new config shape**

Create `src/__tests__/config.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { config } from '../config.js';

describe('config', () => {
  it('should have agent configuration', () => {
    expect(config.agent).toBeDefined();
    expect(config.agent.workingDir).toBeDefined();
    expect(typeof config.agent.maxTurns).toBe('number');
    expect(typeof config.agent.timeoutMs).toBe('number');
    expect(typeof config.agent.allowedTools).toBe('string');
    expect(typeof config.agent.sessionTtlHours).toBe('number');
  });

  it('should not have monitoring config', () => {
    expect(config).not.toHaveProperty('hookPort');
    expect(config).not.toHaveProperty('schedulerIntervalMinutes');
    expect(config).not.toHaveProperty('thresholds');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npx vitest run src/__tests__/config.test.ts 2>&1
```

Expected: FAIL — `config.agent` is undefined, `config.hookPort` still exists.

- [ ] **Step 3: Replace `src/types.ts` with agent-focused types**

```typescript
export interface NotifyPayload {
  message: string;
  channel?: string;
  title?: string;
  sessionId?: string;
}

export interface SlackIncomingMessage {
  id: string;
  source: 'dm' | 'mention';
  text: string;
  userId: string;
  channel: string;
  threadTs?: string;
  messageTs: string;
  receivedAt: string;
  read: boolean;
  targetSession?: string;
}

export interface MessageQueueFile {
  version: number;
  lastUpdated: string;
  messages: SlackIncomingMessage[];
}

export interface SessionInfo {
  id: string;
  termSessionId?: string;
  registeredAt: string;
  lastSeenAt: string;
  label?: string;
  wsConnected?: boolean;
}

export interface SessionRegistryFile {
  version: number;
  lastUpdated: string;
  sessions: SessionInfo[];
}

export interface ReplyPayload {
  channel: string;
  text: string;
  threadTs?: string;
  blocks?: unknown[];
}

// --- Agent types ---

export interface TaskRequest {
  prompt: string;
  workingDir?: string;
  conversationHistory?: string;
  threadTs: string;
  channel: string;
  messageTs: string;
  userId: string;
}

export interface TaskResult {
  output: string;
  exitCode: number;
  timedOut: boolean;
  durationMs: number;
}

export interface AgentSession {
  threadTs: string;
  channel: string;
  createdAt: string;
  lastActiveAt: string;
  workingDir: string;
  exchanges: AgentExchange[];
}

export interface AgentExchange {
  role: 'user' | 'agent';
  content: string;
  timestamp: string;
}
```

- [ ] **Step 4: Replace `src/config.ts` with agent-focused config**

```typescript
import 'dotenv/config';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function optionalInt(name: string, fallback: number): number {
  const val = process.env[name];
  return val ? parseInt(val, 10) : fallback;
}

export const config = {
  slack: {
    botToken: requireEnv('SLACK_BOT_TOKEN'),
    appToken: requireEnv('SLACK_APP_TOKEN'),
    signingSecret: requireEnv('SLACK_SIGNING_SECRET'),
    channelId: process.env.SLACK_CHANNEL_ID || '',
  },
  cliBridgePort: optionalInt('CLI_BRIDGE_PORT', 3848),
  maxQueueMessages: optionalInt('MAX_QUEUE_MESSAGES', 200),
  agent: {
    workingDir: process.env.AGENT_WORKING_DIR || process.cwd(),
    maxTurns: optionalInt('AGENT_MAX_TURNS', 25),
    timeoutMs: optionalInt('AGENT_TIMEOUT_MS', 300000),
    allowedTools: process.env.AGENT_ALLOWED_TOOLS || 'Bash,Read,Write,Edit,Glob,Grep',
    model: process.env.AGENT_MODEL || '',
    sessionTtlHours: optionalInt('AGENT_SESSION_TTL_HOURS', 24),
  },
} as const;
```

- [ ] **Step 5: Update `.env.example`**

```
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-level-token
SLACK_SIGNING_SECRET=your-signing-secret

# Optional: Slack channel for notifications
# SLACK_CHANNEL_ID=C0123456789

# CLI bridge port (default 3848)
CLI_BRIDGE_PORT=3848

# Max messages to keep in the incoming message queue (default 200)
MAX_QUEUE_MESSAGES=200

# Agent configuration
AGENT_WORKING_DIR=/Users/you/projects
AGENT_MAX_TURNS=25
AGENT_TIMEOUT_MS=300000
AGENT_ALLOWED_TOOLS=Bash,Read,Write,Edit,Glob,Grep
# AGENT_MODEL=
AGENT_SESSION_TTL_HOURS=24
```

- [ ] **Step 6: Run the config test to verify it passes**

```bash
npx vitest run src/__tests__/config.test.ts 2>&1
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/types.ts src/config.ts .env.example src/__tests__/config.test.ts
git commit -m "feat: replace config and types with agent-focused versions

Remove monitoring types (SystemStatus, CpuInfo, etc.) and config
(hookPort, thresholds, scheduler). Add agent config (workingDir,
maxTurns, timeoutMs) and agent types (TaskRequest, AgentSession)."
```

---

## Task 3: Restructure Directories — Move `notifier/` to `slack/`

**Files:**
- Move: `src/notifier/slack-sender.ts` → `src/slack/sender.ts`
- Move: `src/notifier/ws-bridge.ts` → `src/slack/ws-bridge.ts`
- Move: `src/notifier/cli-bridge.ts` → `src/slack/cli-bridge.ts`
- Delete: `src/notifier/` (empty after moves)
- Update: all import paths referencing `notifier/`

- [ ] **Step 1: Create `src/slack/` directory and move files**

```bash
mkdir -p src/slack
mv src/notifier/slack-sender.ts src/slack/sender.ts
mv src/notifier/ws-bridge.ts src/slack/ws-bridge.ts
mv src/notifier/cli-bridge.ts src/slack/cli-bridge.ts
rmdir src/notifier 2>/dev/null || rm -rf src/notifier
```

- [ ] **Step 2: Update internal imports in `src/slack/cli-bridge.ts`**

Replace the import block at the top of `src/slack/cli-bridge.ts`. Remove dead imports (`formatNotification`, `formatFullStatus`, `getFullStatus`, `getDashboardHtml`) and update relative paths:

```typescript
import http from 'node:http';
import { replyInThread } from './sender.js';
import { logger } from '../utils/logger.js';
import { getUnreadMessages, getUnreadMessagesForSession, getAllMessages, markAsRead, clearQueue } from '../message-queue/index.js';
import { registerSession, unregisterSession, getActiveSessions, touchSession } from '../session-registry/index.js';
import { createWebSocketServer, isWsConnected, closeWebSocketServer } from './ws-bridge.js';
import type { NotifyPayload, ReplyPayload } from '../types.js';
```

- [ ] **Step 3: Update `handleNotifyPost` in `src/slack/cli-bridge.ts`**

The old `handleNotifyPost` used `formatNotification` and `sendBlocks` which are deleted. Replace with a simple `replyInThread` / `sendMessage` approach. Replace the entire `handleNotifyPost` function:

```typescript
async function handleNotifyPost(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const raw = await readBody(req);
  let payload: NotifyPayload;
  try {
    payload = JSON.parse(raw) as NotifyPayload;
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON' });
    return;
  }

  if (!payload.message || typeof payload.message !== 'string') {
    sendJson(res, 400, { error: 'Missing required field: message' });
    return;
  }

  const rawTitle = payload.title || 'Notification';
  const title = payload.sessionId ? `[${payload.sessionId}] ${rawTitle}` : rawTitle;
  const text = `*${title}*\n${payload.message}`;

  try {
    const { sendMessage } = await import('./sender.js');
    await sendMessage(text, undefined, payload.channel);
    sendJson(res, 200, { ok: true });
  } catch (error) {
    logger.error(COMPONENT, 'Failed to send notification', {
      error: error instanceof Error ? error.message : String(error),
    });
    sendJson(res, 500, { error: 'Failed to send message' });
  }
}
```

- [ ] **Step 4: Remove `handleStatusPost`, dashboard, and `/api/status` routes from `cli-bridge.ts`**

Delete the `handleStatusPost` function entirely. In the `handleRequest` function, remove these route blocks:

- The `POST /status` block (lines referencing `handleStatusPost`)
- The `GET /dashboard` block (lines referencing `getDashboardHtml`)
- The `GET /api/status` block (lines referencing `getFullStatus`)

- [ ] **Step 5: Update `src/slack/ws-bridge.ts` imports**

In `src/slack/ws-bridge.ts`, the imports already use relative paths to `../utils/logger.js` and `../session-registry/index.js` — these paths remain correct after the move. No changes needed to this file.

- [ ] **Step 6: Update `src/slack/sender.ts` imports**

In `src/slack/sender.ts`, the import is `../utils/logger.js` — this remains correct. No changes needed.

- [ ] **Step 7: Update `src/index.ts` imports** (temporary — will be fully rewritten in Task 6)

Update `src/index.ts` to fix import paths. Remove dead imports and update paths:

```typescript
import { App, LogLevel } from '@slack/bolt';
import { config } from './config.js';
import { initSender } from './slack/sender.js';
import { startCliBridge } from './slack/cli-bridge.js';
import { enqueueMessage } from './message-queue/index.js';
import { getActiveSessions, isSessionActive } from './session-registry/index.js';
import { pushToClients } from './slack/ws-bridge.js';
import { logger } from './utils/logger.js';
import type { SlackIncomingMessage } from './types.js';
```

Also remove from `main()`:
- The `registerCommands(app)` call
- The `hookServer` creation and logging
- The `startScheduler` call and its conditional block
- Remove `hookServer.close()` from the shutdown handler

The `main()` function becomes:

```typescript
async function main() {
  const app = new App({
    token: config.slack.botToken,
    appToken: config.slack.appToken,
    signingSecret: config.slack.signingSecret,
    socketMode: true,
    logLevel: LogLevel.WARN,
  });

  initSender(app.client, config.slack.channelId);

  // Event handlers remain for now (will be replaced in Task 6)
  app.event('app_mention', async ({ event, say }) => {
    const rawText = event.text.replace(/<@[A-Z0-9]+>\s*/g, '').trim();
    if (!rawText) {
      await say(`Hi <@${event.user}>! Send me a message and I'll queue it for processing.`);
      return;
    }

    const textAfterSession = rawText.replace(SESSION_PREFIX_RE, '').trim();
    if (HELP_RE.test(textAfterSession)) {
      await say(buildHelpText());
      return;
    }
    if (LIST_CC_RE.test(textAfterSession)) {
      await say(buildSessionList());
      return;
    }

    const { targetSession, cleanText } = parseSessionTarget(rawText);
    const id = enqueueMessage('mention', cleanText, event.user ?? 'unknown', event.channel, event.ts, event.thread_ts, targetSession);

    const mentionMsg: SlackIncomingMessage = {
      id, source: 'mention', text: cleanText, userId: event.user ?? 'unknown',
      channel: event.channel, messageTs: event.ts, receivedAt: new Date().toISOString(), read: false,
      ...(event.thread_ts && { threadTs: event.thread_ts }),
      ...(targetSession && { targetSession }),
    };
    pushToClients(mentionMsg);

    const activeSessions = getActiveSessions();
    const sessionList = activeSessions.length > 0
      ? ` Active sessions: ${activeSessions.map((s) => `\`${s.id}\``).join(', ')}`
      : '';
    const targetNote = targetSession ? ` (routed to \`${targetSession}\`)` : '';
    await say(`Got it! Your message is queued (ref: \`${id}\`)${targetNote}.${sessionList}`);
  });

  app.event('message', async ({ event, say }) => {
    if (event.channel_type !== 'im') return;
    if ('bot_id' in event || ('subtype' in event && event.subtype !== undefined)) return;

    const rawText = 'text' in event ? (event.text || '') : '';
    if (!rawText.trim()) return;

    const dmTextAfterSession = rawText.replace(SESSION_PREFIX_RE, '').trim();
    if (HELP_RE.test(dmTextAfterSession)) {
      await say(buildHelpText());
      return;
    }
    if (LIST_CC_RE.test(dmTextAfterSession)) {
      await say(buildSessionList());
      return;
    }

    const { targetSession, cleanText } = parseSessionTarget(rawText);
    const userId = 'user' in event ? (event.user as string) : 'unknown';
    const id = enqueueMessage('dm', cleanText, userId, event.channel, event.ts, undefined, targetSession);

    const dmMsg: SlackIncomingMessage = {
      id, source: 'dm', text: cleanText, userId,
      channel: event.channel, messageTs: event.ts, receivedAt: new Date().toISOString(), read: false,
      ...(targetSession && { targetSession }),
    };
    pushToClients(dmMsg);

    const targetNote = targetSession ? ` (routed to \`${targetSession}\`)` : '';
    await say(`Message queued (ref: \`${id}\`)${targetNote}. I'll process it shortly.`);
  });

  await app.start();
  logger.info('app', 'Slack bot connected via Socket Mode');

  const bridgeServer = startCliBridge(config.cliBridgePort);
  logger.info('app', `CLI bridge listening on 127.0.0.1:${config.cliBridgePort}`);

  logger.info('app', 'Agent ready');

  const shutdown = async () => {
    logger.info('app', 'Shutting down...');
    bridgeServer.close();
    await app.stop();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
```

- [ ] **Step 8: Update test import paths**

In `src/__tests__/cli-bridge.test.ts`, update the import:

```typescript
import { startCliBridge } from '../slack/cli-bridge.js';
```

Remove the dashboard and api/status test blocks:

- Delete the `describe('GET /dashboard', ...)` block
- Delete the `describe('GET /api/status', ...)` block
- Delete the `describe('POST /status', ...)` block

- [ ] **Step 9: Verify compilation**

```bash
npx tsc --noEmit 2>&1
```

Expected: No errors (or only minor ones we can fix).

- [ ] **Step 10: Run existing tests**

```bash
npx vitest run 2>&1
```

Expected: All remaining tests pass. Some tests that referenced deleted routes have been removed.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "refactor: move notifier/ to slack/, strip monitoring routes

Rename src/notifier/ to src/slack/ (sender, cli-bridge, ws-bridge).
Remove /status, /dashboard, /api/status routes from CLI bridge.
Remove command registration, hook receiver, scheduler from index.ts.
Update all import paths across source and test files."
```

---

## Task 4: Build Task Executor

**Files:**
- Create: `src/agent/executor.ts`
- Test: `src/__tests__/executor.test.ts`

- [ ] **Step 1: Write failing tests for the executor**

Create `src/__tests__/executor.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { executeTask, getExecutorStatus, cancelCurrentTask } from '../agent/executor.js';
import type { TaskRequest } from '../types.js';
import fs from 'node:fs';
import path from 'node:path';

// We test against actual claude CLI if available, but primarily test
// the executor logic using mocked child_process.

vi.mock('node:child_process', () => {
  const mockExecFile = vi.fn();
  return { execFile: mockExecFile };
});

const { execFile } = await import('node:child_process');
const mockExecFile = vi.mocked(execFile);

describe('executor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should report idle when no task is running', () => {
    const status = getExecutorStatus();
    expect(status.busy).toBe(false);
    expect(status.queueDepth).toBe(0);
    expect(status.currentTask).toBeNull();
  });

  it('should execute a task and return output', async () => {
    // Mock execFile to simulate claude -p
    mockExecFile.mockImplementation((_cmd: any, _args: any, _opts: any, cb: any) => {
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(null, 'Task completed successfully', ''), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'echo hello',
      threadTs: '1.0',
      channel: 'C123',
      messageTs: '1.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.output).toBe('Task completed successfully');
    expect(result.exitCode).toBe(0);
    expect(result.timedOut).toBe(false);
  });

  it('should handle task failure', async () => {
    mockExecFile.mockImplementation((_cmd: any, _args: any, _opts: any, cb: any) => {
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(new Error('Process exited with code 1'), 'partial output', 'error text'), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'failing task',
      threadTs: '2.0',
      channel: 'C123',
      messageTs: '2.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.exitCode).not.toBe(0);
  });

  it('should reject invalid working directory', async () => {
    const request: TaskRequest = {
      prompt: 'do something',
      workingDir: '/nonexistent/path/that/does/not/exist',
      threadTs: '3.0',
      channel: 'C123',
      messageTs: '3.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.exitCode).toBe(1);
    expect(result.output).toContain('Directory not found');
  });

  it('should include conversation history in prompt when provided', async () => {
    let capturedPrompt = '';
    mockExecFile.mockImplementation((_cmd: any, args: any, _opts: any, cb: any) => {
      capturedPrompt = args[1]; // -p is args[0], prompt is args[1]
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(null, 'done', ''), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'now fix the tests',
      conversationHistory: 'User: add a login page\nAgent: I created src/login.tsx',
      threadTs: '4.0',
      channel: 'C123',
      messageTs: '4.0',
      userId: 'U123',
    };

    await executeTask(request);
    expect(capturedPrompt).toContain('previous conversation');
    expect(capturedPrompt).toContain('add a login page');
    expect(capturedPrompt).toContain('now fix the tests');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/__tests__/executor.test.ts 2>&1
```

Expected: FAIL — module `../agent/executor.js` does not exist.

- [ ] **Step 3: Implement the executor**

Create `src/agent/executor.ts`:

```typescript
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import { config } from '../config.js';
import { logger } from '../utils/logger.js';
import type { TaskRequest, TaskResult } from '../types.js';

const COMPONENT = 'executor';
const MAX_SLACK_CHARS = 3000;
const MAX_BUFFER = 10 * 1024 * 1024; // 10 MB

interface ExecutorStatus {
  busy: boolean;
  queueDepth: number;
  currentTask: { threadTs: string; channel: string; startedAt: string } | null;
}

let currentChild: ReturnType<typeof execFile> | null = null;
let currentTaskInfo: { threadTs: string; channel: string; startedAt: string } | null = null;
const taskQueue: Array<{ request: TaskRequest; resolve: (r: TaskResult) => void }> = [];
let isProcessing = false;

export function getExecutorStatus(): ExecutorStatus {
  return {
    busy: isProcessing,
    queueDepth: taskQueue.length,
    currentTask: currentTaskInfo,
  };
}

export function cancelCurrentTask(): boolean {
  if (currentChild && currentChild.pid) {
    currentChild.kill('SIGTERM');
    return true;
  }
  return false;
}

function expandHome(p: string): string {
  if (p.startsWith('~/') || p === '~') {
    return p.replace('~', process.env.HOME || '/tmp');
  }
  return p;
}

function truncateForSlack(text: string): string {
  if (text.length <= MAX_SLACK_CHARS) return text;
  return text.slice(0, MAX_SLACK_CHARS - 20) + '\n\n...(truncated)';
}

function buildPrompt(request: TaskRequest): string {
  const parts: string[] = [];

  if (request.conversationHistory) {
    parts.push(
      'You are continuing a previous conversation. Here is the history:',
      '',
      request.conversationHistory,
      '',
      `User's new message: ${request.prompt}`,
    );
  } else {
    parts.push(
      'You are an autonomous Claude Code agent executing a task.',
      `Working directory: ${request.workingDir || config.agent.workingDir}`,
      '',
      'IMPORTANT: Do NOT attempt to reply to Slack or use any Slack/MCP/notification tools.',
      'Do NOT use curl to post to any API. Just execute the task and print your result to stdout.',
      'Your stdout output will be captured and posted as a reply automatically.',
      '',
      'Task:',
      request.prompt,
      '',
      'Execute this task. Be concise — keep output under 3000 characters.',
    );
  }

  return parts.join('\n');
}

function runTask(request: TaskRequest): Promise<TaskResult> {
  const cwd = expandHome(request.workingDir || config.agent.workingDir);

  // Validate working directory
  if (!fs.existsSync(cwd)) {
    return Promise.resolve({
      output: `Directory not found: \`${cwd}\`\nPlease check the path and try again.`,
      exitCode: 1,
      timedOut: false,
      durationMs: 0,
    });
  }

  const prompt = buildPrompt(request);
  const startTime = Date.now();

  currentTaskInfo = {
    threadTs: request.threadTs,
    channel: request.channel,
    startedAt: new Date().toISOString(),
  };

  return new Promise<TaskResult>((resolve) => {
    const args: string[] = ['-p', prompt, '--max-turns', String(config.agent.maxTurns), '--allowedTools', config.agent.allowedTools];

    if (config.agent.model) {
      args.push('--model', config.agent.model);
    }

    const child = execFile('claude', args, {
      cwd,
      timeout: config.agent.timeoutMs,
      maxBuffer: MAX_BUFFER,
      env: { ...process.env, DISABLE_INTERACTIVITY: '1' },
    }, (error, stdout, stderr) => {
      const durationMs = Date.now() - startTime;
      currentChild = null;
      currentTaskInfo = null;

      if (error) {
        logger.error(COMPONENT, 'Task failed', { error: error.message, durationMs });
        const output = stdout ? truncateForSlack(stdout) : `Task failed: ${error.message}`;
        const timedOut = error.message.includes('TIMEOUT') || error.killed === true;
        resolve({ output, exitCode: 1, timedOut, durationMs });
      } else {
        const output = truncateForSlack(stdout.trim() || '(no output)');
        resolve({ output, exitCode: 0, timedOut: false, durationMs });
      }
    });

    currentChild = child;
    if (child.stdin) child.stdin.end();
  });
}

export async function executeTask(request: TaskRequest): Promise<TaskResult> {
  return new Promise<TaskResult>((resolve) => {
    taskQueue.push({ request, resolve });
    processQueue();
  });
}

async function processQueue(): Promise<void> {
  if (isProcessing) return;
  isProcessing = true;

  while (taskQueue.length > 0) {
    const item = taskQueue.shift()!;
    try {
      const result = await runTask(item.request);
      item.resolve(result);
    } catch (err) {
      logger.error(COMPONENT, 'Unexpected error', { error: String(err) });
      item.resolve({
        output: `Internal error: ${String(err)}`,
        exitCode: 1,
        timedOut: false,
        durationMs: 0,
      });
    }
  }

  isProcessing = false;
}
```

- [ ] **Step 4: Create the directory**

```bash
mkdir -p src/agent
```

- [ ] **Step 5: Run executor tests**

```bash
npx vitest run src/__tests__/executor.test.ts 2>&1
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/agent/executor.ts src/__tests__/executor.test.ts
git commit -m "feat: add task executor for claude -p management

Spawns claude -p child processes with configurable max turns,
timeout, allowed tools, and working directory. Sequential queue
with status reporting and task cancellation support."
```

---

## Task 5: Build Session Manager

**Files:**
- Create: `src/agent/session-manager.ts`
- Test: `src/__tests__/session-manager.test.ts`

- [ ] **Step 1: Write failing tests**

Create `src/__tests__/session-manager.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  getOrCreateSession,
  addExchange,
  getSession,
  buildContextPrompt,
  listSessions,
  cleanStaleSessions,
} from '../agent/session-manager.js';

const SESSIONS_DIR = path.resolve(process.cwd(), 'data', 'agent-sessions');

describe('session-manager', () => {
  beforeEach(() => {
    // Clean session data before each test
    if (fs.existsSync(SESSIONS_DIR)) {
      fs.rmSync(SESSIONS_DIR, { recursive: true });
    }
  });

  afterEach(() => {
    if (fs.existsSync(SESSIONS_DIR)) {
      fs.rmSync(SESSIONS_DIR, { recursive: true });
    }
  });

  it('should create a new session for a thread', () => {
    const session = getOrCreateSession('C123', '1.0', '/tmp');
    expect(session.threadTs).toBe('1.0');
    expect(session.channel).toBe('C123');
    expect(session.exchanges).toEqual([]);
    expect(session.workingDir).toBe('/tmp');
  });

  it('should return existing session for same thread', () => {
    getOrCreateSession('C123', '1.0', '/tmp');
    const session = getOrCreateSession('C123', '1.0', '/other');
    // Working dir should NOT change on re-get
    expect(session.workingDir).toBe('/tmp');
  });

  it('should add exchanges to a session', () => {
    getOrCreateSession('C123', '1.0', '/tmp');
    addExchange('C123', '1.0', 'user', 'fix the bug');
    addExchange('C123', '1.0', 'agent', 'I fixed src/main.ts');

    const session = getSession('C123', '1.0');
    expect(session).not.toBeNull();
    expect(session!.exchanges).toHaveLength(2);
    expect(session!.exchanges[0].role).toBe('user');
    expect(session!.exchanges[0].content).toBe('fix the bug');
    expect(session!.exchanges[1].role).toBe('agent');
  });

  it('should build context prompt from history', () => {
    getOrCreateSession('C123', '1.0', '/tmp');
    addExchange('C123', '1.0', 'user', 'add a login page');
    addExchange('C123', '1.0', 'agent', 'Created src/login.tsx');

    const prompt = buildContextPrompt('C123', '1.0');
    expect(prompt).toContain('previous conversation');
    expect(prompt).toContain('add a login page');
    expect(prompt).toContain('Created src/login.tsx');
  });

  it('should return null context prompt for empty session', () => {
    getOrCreateSession('C123', '1.0', '/tmp');
    const prompt = buildContextPrompt('C123', '1.0');
    expect(prompt).toBeNull();
  });

  it('should return null for non-existent session', () => {
    const session = getSession('C999', '99.0');
    expect(session).toBeNull();
  });

  it('should list all active sessions', () => {
    getOrCreateSession('C1', '1.0', '/tmp');
    getOrCreateSession('C2', '2.0', '/tmp');

    const sessions = listSessions();
    expect(sessions).toHaveLength(2);
  });

  it('should clean stale sessions', () => {
    const session = getOrCreateSession('C123', '1.0', '/tmp');
    // Manually backdate the session
    const sessionFile = path.join(SESSIONS_DIR, `C123-1.0.json`);
    const data = JSON.parse(fs.readFileSync(sessionFile, 'utf-8'));
    data.lastActiveAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString(); // 25 hours ago
    fs.writeFileSync(sessionFile, JSON.stringify(data));

    const removed = cleanStaleSessions(24);
    expect(removed).toBe(1);

    const after = getSession('C123', '1.0');
    expect(after).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/__tests__/session-manager.test.ts 2>&1
```

Expected: FAIL — module `../agent/session-manager.js` does not exist.

- [ ] **Step 3: Implement the session manager**

Create `src/agent/session-manager.ts`:

```typescript
import fs from 'node:fs';
import path from 'node:path';
import { logger } from '../utils/logger.js';
import { config } from '../config.js';
import type { AgentSession, AgentExchange } from '../types.js';

const COMPONENT = 'session-manager';
const SESSIONS_DIR = path.resolve(process.cwd(), 'data', 'agent-sessions');

function ensureDir(): void {
  if (!fs.existsSync(SESSIONS_DIR)) {
    fs.mkdirSync(SESSIONS_DIR, { recursive: true });
  }
}

function sessionKey(channel: string, threadTs: string): string {
  return `${channel}-${threadTs}`;
}

function sessionFilePath(channel: string, threadTs: string): string {
  return path.join(SESSIONS_DIR, `${sessionKey(channel, threadTs)}.json`);
}

function readSessionFile(filePath: string): AgentSession | null {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8')) as AgentSession;
  } catch (err) {
    logger.error(COMPONENT, 'Failed to read session file', { filePath, error: String(err) });
    return null;
  }
}

function writeSessionFile(filePath: string, session: AgentSession): void {
  ensureDir();
  fs.writeFileSync(filePath, JSON.stringify(session, null, 2), 'utf-8');
}

export function getOrCreateSession(channel: string, threadTs: string, workingDir: string): AgentSession {
  ensureDir();
  const filePath = sessionFilePath(channel, threadTs);
  const existing = readSessionFile(filePath);

  if (existing) {
    return existing;
  }

  const now = new Date().toISOString();
  const session: AgentSession = {
    threadTs,
    channel,
    createdAt: now,
    lastActiveAt: now,
    workingDir,
    exchanges: [],
  };

  writeSessionFile(filePath, session);
  logger.info(COMPONENT, 'Created session', { channel, threadTs });
  return session;
}

export function getSession(channel: string, threadTs: string): AgentSession | null {
  return readSessionFile(sessionFilePath(channel, threadTs));
}

export function addExchange(channel: string, threadTs: string, role: 'user' | 'agent', content: string): void {
  const filePath = sessionFilePath(channel, threadTs);
  const session = readSessionFile(filePath);
  if (!session) {
    logger.warn(COMPONENT, 'Cannot add exchange: session not found', { channel, threadTs });
    return;
  }

  const exchange: AgentExchange = {
    role,
    content,
    timestamp: new Date().toISOString(),
  };

  session.exchanges.push(exchange);
  session.lastActiveAt = new Date().toISOString();
  writeSessionFile(filePath, session);
}

export function buildContextPrompt(channel: string, threadTs: string): string | null {
  const session = readSessionFile(sessionFilePath(channel, threadTs));
  if (!session || session.exchanges.length === 0) return null;

  const lines: string[] = [
    'You are continuing a previous conversation. Here is the history:',
    '',
  ];

  for (const exchange of session.exchanges) {
    const label = exchange.role === 'user' ? 'User' : 'Agent';
    lines.push(`${label}: ${exchange.content}`);
    lines.push('');
  }

  return lines.join('\n');
}

export function listSessions(): AgentSession[] {
  ensureDir();
  const files = fs.readdirSync(SESSIONS_DIR).filter((f) => f.endsWith('.json'));
  const sessions: AgentSession[] = [];

  for (const file of files) {
    const session = readSessionFile(path.join(SESSIONS_DIR, file));
    if (session) sessions.push(session);
  }

  return sessions.sort((a, b) => new Date(b.lastActiveAt).getTime() - new Date(a.lastActiveAt).getTime());
}

export function cleanStaleSessions(ttlHours?: number): number {
  ensureDir();
  const ttl = ttlHours ?? config.agent.sessionTtlHours;
  const cutoff = Date.now() - ttl * 60 * 60 * 1000;
  const files = fs.readdirSync(SESSIONS_DIR).filter((f) => f.endsWith('.json'));
  let removed = 0;

  for (const file of files) {
    const filePath = path.join(SESSIONS_DIR, file);
    const session = readSessionFile(filePath);
    if (session && new Date(session.lastActiveAt).getTime() < cutoff) {
      fs.unlinkSync(filePath);
      removed++;
      logger.info(COMPONENT, 'Removed stale session', { file });
    }
  }

  return removed;
}
```

- [ ] **Step 4: Run session manager tests**

```bash
npx vitest run src/__tests__/session-manager.test.ts 2>&1
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/agent/session-manager.ts src/__tests__/session-manager.test.ts
git commit -m "feat: add session manager for thread-based conversations

File-based session storage mapping Slack threads to conversation
histories. Supports context prompt building for multi-turn agent
interactions and stale session cleanup."
```

---

## Task 6: Build Message Router

**Files:**
- Create: `src/agent/router.ts`
- Test: `src/__tests__/router.test.ts`

- [ ] **Step 1: Write failing tests**

Create `src/__tests__/router.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { routeMessage, parseBuiltInCommand, parseWorkingDir } from '../agent/router.js';

describe('router', () => {
  describe('parseBuiltInCommand', () => {
    it('should detect help command', () => {
      expect(parseBuiltInCommand('help')).toBe('help');
    });

    it('should detect status command', () => {
      expect(parseBuiltInCommand('status')).toBe('status');
    });

    it('should detect cancel command', () => {
      expect(parseBuiltInCommand('cancel')).toBe('cancel');
    });

    it('should detect config workspace command', () => {
      expect(parseBuiltInCommand('config workspace /tmp')).toBe('config');
    });

    it('should detect history command', () => {
      expect(parseBuiltInCommand('history')).toBe('history');
    });

    it('should return null for regular messages', () => {
      expect(parseBuiltInCommand('fix the login bug')).toBeNull();
      expect(parseBuiltInCommand('please help me refactor')).toBeNull();
    });
  });

  describe('parseWorkingDir', () => {
    it('should extract pwd= prefix', () => {
      const result = parseWorkingDir('pwd=/Users/me/project fix the bug');
      expect(result.workingDir).toBe('/Users/me/project');
      expect(result.cleanText).toBe('fix the bug');
    });

    it('should expand ~ in pwd', () => {
      const result = parseWorkingDir('pwd=~/myproject do something');
      expect(result.workingDir).toContain('myproject');
      expect(result.cleanText).toBe('do something');
    });

    it('should return null workingDir when no prefix', () => {
      const result = parseWorkingDir('just a regular message');
      expect(result.workingDir).toBeNull();
      expect(result.cleanText).toBe('just a regular message');
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/__tests__/router.test.ts 2>&1
```

Expected: FAIL — module `../agent/router.js` does not exist.

- [ ] **Step 3: Implement the router**

Create `src/agent/router.ts`:

```typescript
import { logger } from '../utils/logger.js';
import { config } from '../config.js';
import { replyInThread } from '../slack/sender.js';
import { executeTask, getExecutorStatus, cancelCurrentTask } from './executor.js';
import {
  getOrCreateSession,
  getSession,
  addExchange,
  buildContextPrompt,
  listSessions as listAgentSessions,
} from './session-manager.js';
import type { TaskRequest } from '../types.js';

const COMPONENT = 'router';

type BuiltInCommand = 'help' | 'status' | 'cancel' | 'config' | 'history';

export function parseBuiltInCommand(text: string): BuiltInCommand | null {
  const trimmed = text.trim().toLowerCase();
  if (trimmed === 'help') return 'help';
  if (trimmed === 'status') return 'status';
  if (trimmed === 'cancel') return 'cancel';
  if (trimmed.startsWith('config workspace')) return 'config';
  if (trimmed === 'history') return 'history';
  return null;
}

export function parseWorkingDir(text: string): { workingDir: string | null; cleanText: string } {
  const match = text.match(/^pwd=(\S+)\s*/);
  if (match) {
    let dir = match[1];
    if (dir.startsWith('~/') || dir === '~') {
      dir = dir.replace('~', process.env.HOME || '/tmp');
    }
    return { workingDir: dir, cleanText: text.slice(match[0].length).trim() };
  }
  return { workingDir: null, cleanText: text };
}

function buildHelpText(): string {
  return [
    '*Claude Agent — Help*',
    '',
    '*Send a task:*',
    '• `@bot <message>` — Execute a task (new thread = new task)',
    '• Reply in a thread — Continue that conversation',
    '• `@bot pwd=/path <message>` — Run in a specific directory',
    '',
    '*Built-in commands:*',
    '• `help` — Show this help',
    '• `status` — Agent status (busy/idle, queue depth)',
    '• `cancel` — Cancel the current task',
    '• `history` — Recent conversation summaries',
    '',
    `*Default working directory:* \`${config.agent.workingDir}\``,
  ].join('\n');
}

function buildStatusText(): string {
  const status = getExecutorStatus();
  const sessions = listAgentSessions();
  const lines = [
    `*Agent Status:* ${status.busy ? 'Busy' : 'Idle'}`,
    `*Queue depth:* ${status.queueDepth}`,
    `*Active conversations:* ${sessions.length}`,
    `*Working directory:* \`${config.agent.workingDir}\``,
  ];
  if (status.currentTask) {
    lines.push(`*Current task:* thread \`${status.currentTask.threadTs}\` (started ${status.currentTask.startedAt})`);
  }
  return lines.join('\n');
}

function buildHistoryText(): string {
  const sessions = listAgentSessions();
  if (sessions.length === 0) return '_No recent conversations._';

  const lines = sessions.slice(0, 10).map((s) => {
    const exchangeCount = s.exchanges.length;
    const lastMsg = s.exchanges.length > 0
      ? s.exchanges[s.exchanges.length - 1].content.slice(0, 60)
      : '(empty)';
    return `• \`${s.channel}/${s.threadTs}\` — ${exchangeCount} exchanges — _${lastMsg}_`;
  });

  return ['*Recent Conversations:*', '', ...lines].join('\n');
}

async function handleBuiltInCommand(
  command: BuiltInCommand,
  text: string,
  channel: string,
  threadTs?: string,
): Promise<string> {
  switch (command) {
    case 'help':
      return buildHelpText();
    case 'status':
      return buildStatusText();
    case 'cancel': {
      const cancelled = cancelCurrentTask();
      return cancelled ? 'Current task cancelled.' : 'No task is currently running.';
    }
    case 'history':
      return buildHistoryText();
    case 'config':
      return 'Working directory configuration via Slack is not yet supported. Set `AGENT_WORKING_DIR` in .env or use `pwd=` prefix per-task.';
    default:
      return 'Unknown command.';
  }
}

export interface RouteMessageParams {
  text: string;
  userId: string;
  channel: string;
  messageTs: string;
  threadTs?: string;
}

export async function routeMessage(params: RouteMessageParams): Promise<void> {
  const { text, userId, channel, messageTs, threadTs } = params;

  // Check for built-in commands
  const command = parseBuiltInCommand(text);
  if (command) {
    const response = await handleBuiltInCommand(command, text, channel, threadTs);
    await replyInThread(channel, response, threadTs || messageTs);
    return;
  }

  // Parse working directory override
  const { workingDir: cwdOverride, cleanText } = parseWorkingDir(text);

  // Determine if this is a thread continuation or a new task
  const isThreadReply = !!threadTs;
  const effectiveThreadTs = threadTs || messageTs; // New messages use their own ts as thread root

  // Post acknowledgment
  try {
    const ackText = getExecutorStatus().busy
      ? 'Queued — another task is running. I\'ll get to this next.'
      : 'Working on this...';
    await replyInThread(channel, ackText, effectiveThreadTs);
  } catch (err) {
    logger.error(COMPONENT, 'Failed to post acknowledgment', { error: String(err) });
  }

  // Build the task request
  let conversationHistory: string | undefined;

  if (isThreadReply) {
    // Look up existing session for this thread
    const existingSession = getSession(channel, threadTs);
    if (existingSession) {
      conversationHistory = buildContextPrompt(channel, threadTs) || undefined;
    }
  }

  // Create/get session for this thread
  const session = getOrCreateSession(channel, effectiveThreadTs, cwdOverride || config.agent.workingDir);

  // Record the user message
  addExchange(channel, effectiveThreadTs, 'user', cleanText);

  const taskRequest: TaskRequest = {
    prompt: cleanText,
    workingDir: cwdOverride || session.workingDir,
    conversationHistory,
    threadTs: effectiveThreadTs,
    channel,
    messageTs,
    userId,
  };

  // Execute and post result
  const result = await executeTask(taskRequest);

  // Record the agent response
  addExchange(channel, effectiveThreadTs, 'agent', result.output);

  // Post result to Slack
  try {
    const prefix = result.timedOut ? '*Task timed out.* Partial output:\n\n' : '';
    const suffix = result.exitCode !== 0 && !result.timedOut ? '\n\n_Task exited with an error._' : '';
    await replyInThread(channel, `${prefix}${result.output}${suffix}`, effectiveThreadTs);
  } catch (err) {
    logger.error(COMPONENT, 'Failed to post result', { error: String(err) });
  }
}
```

- [ ] **Step 4: Run router tests**

```bash
npx vitest run src/__tests__/router.test.ts 2>&1
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/agent/router.ts src/__tests__/router.test.ts
git commit -m "feat: add message router with built-in commands

Routes Slack messages to executor with thread-based session
continuity. Built-in commands: help, status, cancel, history.
Parses pwd= prefix for working directory overrides."
```

---

## Task 7: Rewrite `index.ts` as Thin Message Handler

**Files:**
- Modify: `src/index.ts`

- [ ] **Step 1: Rewrite `src/index.ts`**

```typescript
import { App, LogLevel } from '@slack/bolt';
import { config } from './config.js';
import { initSender } from './slack/sender.js';
import { startCliBridge } from './slack/cli-bridge.js';
import { logger } from './utils/logger.js';
import { routeMessage } from './agent/router.js';
import { cleanStaleSessions } from './agent/session-manager.js';

const SESSION_CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // 1 hour

async function main() {
  const app = new App({
    token: config.slack.botToken,
    appToken: config.slack.appToken,
    signingSecret: config.slack.signingSecret,
    socketMode: true,
    logLevel: LogLevel.WARN,
  });

  initSender(app.client, config.slack.channelId);

  // Handle @mentions
  app.event('app_mention', async ({ event }) => {
    const rawText = event.text.replace(/<@[A-Z0-9]+>\s*/g, '').trim();
    if (!rawText) return;

    routeMessage({
      text: rawText,
      userId: event.user ?? 'unknown',
      channel: event.channel,
      messageTs: event.ts,
      threadTs: event.thread_ts,
    }).catch((err) => {
      logger.error('app', 'Error routing mention', { error: String(err) });
    });
  });

  // Handle direct messages
  app.event('message', async ({ event }) => {
    if (event.channel_type !== 'im') return;
    if ('bot_id' in event || ('subtype' in event && event.subtype !== undefined)) return;

    const rawText = 'text' in event ? (event.text || '') : '';
    if (!rawText.trim()) return;

    const userId = 'user' in event ? (event.user as string) : 'unknown';

    routeMessage({
      text: rawText,
      userId,
      channel: event.channel,
      messageTs: event.ts,
      threadTs: 'thread_ts' in event ? (event.thread_ts as string | undefined) : undefined,
    }).catch((err) => {
      logger.error('app', 'Error routing DM', { error: String(err) });
    });
  });

  await app.start();
  logger.info('app', 'Slack bot connected via Socket Mode');

  const bridgeServer = startCliBridge(config.cliBridgePort);
  logger.info('app', `CLI bridge listening on 127.0.0.1:${config.cliBridgePort}`);

  // Periodic stale session cleanup
  const cleanupTimer = setInterval(() => {
    try {
      cleanStaleSessions();
    } catch (err) {
      logger.error('app', 'Session cleanup error', { error: String(err) });
    }
  }, SESSION_CLEANUP_INTERVAL_MS);

  logger.info('app', `Agent ready (working dir: ${config.agent.workingDir})`);

  const shutdown = async () => {
    logger.info('app', 'Shutting down...');
    clearInterval(cleanupTimer);
    bridgeServer.close();
    await app.stop();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  logger.error('app', 'Failed to start', { error: String(err) });
  process.exit(1);
});
```

- [ ] **Step 2: Verify compilation**

```bash
npx tsc --noEmit 2>&1
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add src/index.ts
git commit -m "feat: rewrite index.ts as thin Slack message handler

Delegates all message routing to agent/router.ts. Removes old
command registration, help text, session prefix parsing. Adds
periodic stale session cleanup."
```

---

## Task 8: Update CLI Bridge with Agent Routes

**Files:**
- Modify: `src/slack/cli-bridge.ts`

- [ ] **Step 1: Add agent routes to `handleRequest` in `src/slack/cli-bridge.ts`**

Add these imports at the top of the file:

```typescript
import { getExecutorStatus } from '../agent/executor.js';
import { listSessions as listAgentSessions, getSession as getAgentSession } from '../agent/session-manager.js';
import { routeMessage } from '../agent/router.js';
```

Add these route handlers before the 404 at the end of `handleRequest`:

```typescript
  // GET /agent/status — agent executor status
  if (pathname === '/agent/status' && method === 'GET') {
    const status = getExecutorStatus();
    sendJson(res, 200, { ok: true, ...status });
    return;
  }

  // POST /agent/task — submit a task programmatically
  if (pathname === '/agent/task' && method === 'POST') {
    readBody(req).then((raw) => {
      let body: { text: string; channel?: string; threadTs?: string };
      try {
        body = JSON.parse(raw) as { text: string; channel?: string; threadTs?: string };
      } catch {
        sendJson(res, 400, { error: 'Invalid JSON' });
        return;
      }
      if (!body.text) {
        sendJson(res, 400, { error: 'Missing required field: text' });
        return;
      }
      const channel = body.channel || 'api';
      const ts = body.threadTs || Date.now().toString();
      routeMessage({
        text: body.text,
        userId: 'api',
        channel,
        messageTs: ts,
        threadTs: body.threadTs,
      }).catch((err) => {
        logger.error(COMPONENT, 'API task failed', { error: String(err) });
      });
      sendJson(res, 202, { ok: true, message: 'Task queued' });
    }).catch((err) => {
      logger.error(COMPONENT, 'Error reading body', { error: String(err) });
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    });
    return;
  }

  // GET /agent/sessions — list agent conversation sessions
  if (pathname === '/agent/sessions' && method === 'GET') {
    const sessions = listAgentSessions().map((s) => ({
      channel: s.channel,
      threadTs: s.threadTs,
      createdAt: s.createdAt,
      lastActiveAt: s.lastActiveAt,
      workingDir: s.workingDir,
      exchangeCount: s.exchanges.length,
    }));
    sendJson(res, 200, { ok: true, count: sessions.length, sessions });
    return;
  }

  // GET /agent/sessions/:channel/:threadTs — get conversation history
  const sessionMatch = pathname.match(/^\/agent\/sessions\/([^/]+)\/([^/]+)$/);
  if (sessionMatch && method === 'GET') {
    const session = getAgentSession(sessionMatch[1], sessionMatch[2]);
    if (session) {
      sendJson(res, 200, { ok: true, session: session as unknown as Record<string, unknown> });
    } else {
      sendJson(res, 404, { error: 'Session not found' });
    }
    return;
  }
```

- [ ] **Step 2: Update the CLI bridge test with new agent route tests**

Add these test blocks to `src/__tests__/cli-bridge.test.ts`:

```typescript
  describe('GET /agent/status', () => {
    it('should return executor status', async () => {
      const { status, data } = await request('GET', '/agent/status');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data).toHaveProperty('busy');
      expect(data).toHaveProperty('queueDepth');
    });
  });

  describe('POST /agent/task', () => {
    it('should return 400 when missing text', async () => {
      const { status, data } = await request('POST', '/agent/task', {});
      expect(status).toBe(400);
      expect(data.error).toBe('Missing required field: text');
    });

    it('should return 400 for invalid JSON', async () => {
      const { status } = await request('POST', '/agent/task', undefined);
      expect(status).toBe(400);
    });
  });

  describe('GET /agent/sessions', () => {
    it('should return empty when no sessions', async () => {
      const { status, data } = await request('GET', '/agent/sessions');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.count).toBe(0);
    });
  });
```

- [ ] **Step 3: Run tests**

```bash
npx vitest run src/__tests__/cli-bridge.test.ts 2>&1
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/slack/cli-bridge.ts src/__tests__/cli-bridge.test.ts
git commit -m "feat: add /agent/* routes to CLI bridge

GET /agent/status — executor status (busy, queue depth).
POST /agent/task — submit tasks programmatically.
GET /agent/sessions — list conversation sessions.
GET /agent/sessions/:channel/:threadTs — get history."
```

---

## Task 9: Thin the Channel Server

**Files:**
- Modify: `channel-server/server.ts`

- [ ] **Step 1: Remove autonomous execution logic from channel server**

Remove these from `channel-server/server.ts`:
- The `AUTONOMOUS_*` configuration constants (lines 30-37)
- The `taskQueue`, `isProcessing`, `seenMessageIds` state (lines 204-206)
- The `SlackMessage` interface (keep — needed by `deliverMessage` and `formatSlackMessage`)
- The `executeTask` function (lines 282-377)
- The `processQueue` function (lines 379-393)
- The `enqueueTask` function (lines 395-421)
- The `stripSessionPrefix`, `expandHome`, `parseTaskDirectives`, `truncateForSlack` helpers (lines 247-280)
- The `TaskDirectives` interface (lines 258-261)
- Remove the `enqueueTask(parsed.message)` call from the WebSocket `on('message')` handler (line 468)
- Remove the `AUTONOMOUS_ENABLED` check and `execFileSync` validation in `main()` (lines 502-511)
- Remove `execFile`, `execFileSync` from imports (line 21)
- Remove `AUTONOMOUS_ENABLED` from MCP instructions (lines 125-128)
- Remove task queue warning from shutdown handler (lines 528-529)

The channel server should keep:
- MCP server setup and tools (`slack_reply`, `slack_notify`)
- WebSocket client connection and message delivery
- Session registration
- `httpRequest` helper
- `deriveSessionId`
- `formatSlackMessage` and `deliverMessage`
- `fetchMissedMessages`

- [ ] **Step 2: Verify channel server still compiles**

```bash
cd channel-server && npx tsc --noEmit --esModuleInterop --module nodenext --moduleResolution nodenext server.ts 2>&1; cd ..
```

If there's no tsconfig in channel-server, just verify no syntax errors by scanning the file manually.

- [ ] **Step 3: Commit**

```bash
git add channel-server/server.ts
git commit -m "refactor: remove autonomous execution from channel server

Channel server is now a thin MCP bridge. Task execution is handled
by src/agent/executor.ts in the main process. Keeps MCP tools,
WebSocket connection, and session registration."
```

---

## Task 10: Update Package Metadata and Documentation

**Files:**
- Modify: `package.json`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update `package.json` description**

Change the `description` field:

```json
"description": "Slack-driven Claude Code agent — personal coding assistant controlled via Slack"
```

- [ ] **Step 2: Update `CLAUDE.md`**

Replace the project-level CLAUDE.md with updated instructions reflecting the new agent-focused purpose:

```markdown
# slack-bot Project Instructions

## Overview

This is a Slack-driven Claude Code agent. It runs as a background service and executes coding tasks sent via Slack messages. Thread replies continue conversations.

## Slack Status Updates

**Always post status updates to Slack** when completing tasks or encountering errors.

\`\`\`bash
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
\`\`\`

If the bot is not running (connection refused), skip silently and continue working.
```

- [ ] **Step 3: Update `README.md` header and description**

Update the first section of README.md to reflect the new purpose. Keep the setup instructions but remove references to system monitoring, slash commands, and health alerts. (Full README rewrite can be a follow-up task.)

- [ ] **Step 4: Commit**

```bash
git add package.json CLAUDE.md README.md
git commit -m "docs: update metadata and docs for agent-focused redesign

Update package.json description, CLAUDE.md instructions, and
README.md to reflect the new Slack-driven Claude Code agent purpose."
```

---

## Task 11: Full Test Suite Verification

**Files:**
- All test files

- [ ] **Step 1: Run the complete test suite**

```bash
npx vitest run 2>&1
```

Expected: All tests pass.

- [ ] **Step 2: Run TypeScript compilation check**

```bash
npx tsc --noEmit 2>&1
```

Expected: No errors.

- [ ] **Step 3: Verify the app starts** (requires Slack credentials)

```bash
SLACK_BOT_TOKEN=xoxb-test SLACK_APP_TOKEN=xapp-test SLACK_SIGNING_SECRET=test timeout 5 npx tsx src/index.ts 2>&1 || true
```

Expected: Should attempt to start and fail on Slack auth (not on missing modules or type errors).

- [ ] **Step 4: Fix any failures found**

If tests fail, fix the specific issues. Common issues:
- Import path mismatches
- Missing exports
- Mock setup issues

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: verify all tests pass after agent redesign

Full test suite verification: executor, session-manager, router,
cli-bridge, message-queue, session-registry, ws-bridge."
```

---

## Summary

| Task | Component | What It Does |
|------|-----------|-------------|
| 1 | Cleanup | Delete all monitoring, commands, scheduler, dashboard, hooks |
| 2 | Config & Types | Agent-focused config and TypeScript types |
| 3 | Restructure | Move `notifier/` → `slack/`, fix imports |
| 4 | Executor | `claude -p` task runner with queue and cancellation |
| 5 | Session Manager | Thread → conversation history mapping |
| 6 | Router | Message dispatch with built-in commands |
| 7 | Entry Point | Thin `index.ts` delegating to router |
| 8 | CLI Bridge | Add `/agent/*` HTTP routes |
| 9 | Channel Server | Remove embedded execution, keep MCP bridge |
| 10 | Documentation | Update package.json, CLAUDE.md, README.md |
| 11 | Verification | Full test suite + compilation check |
