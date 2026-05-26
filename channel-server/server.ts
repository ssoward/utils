#!/usr/bin/env node
/**
 * MCP Channel Server for real-time Slack ↔ Claude Code messaging.
 *
 * This server:
 * 1. Connects to the slack-bot's WebSocket endpoint for real-time message push
 * 2. Exposes `reply` and `notify` tools for Claude to respond via Slack
 * 3. Sends incoming Slack messages as MCP logging notifications to Claude Code
 *
 * Session ID is derived from TERM_SESSION_ID using the same SHA-256 logic
 * as the hook script, ensuring consistent identity.
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import WebSocket from 'ws';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import { execFile, execFileSync } from 'node:child_process';

// --- Configuration ---
const BOT_PORT = parseInt(process.env.SLACK_BOT_PORT || '3848', 10);
const BOT_BASE = `http://127.0.0.1:${BOT_PORT}`;
const WS_URL = `ws://127.0.0.1:${BOT_PORT}/ws`;
const RECONNECT_DELAY_MS = 5_000;

// --- Autonomous execution configuration ---
const AUTONOMOUS_ENABLED = process.env.AUTONOMOUS !== 'false'; // on by default
const AUTONOMOUS_MAX_TURNS = parseInt(process.env.AUTONOMOUS_MAX_TURNS || '25', 10);
const AUTONOMOUS_TIMEOUT_MS = parseInt(process.env.AUTONOMOUS_TIMEOUT_MS || '300000', 10);
const AUTONOMOUS_WORKING_DIR = process.env.AUTONOMOUS_WORKING_DIR || process.cwd();
const SLACK_REPLY_MAX_CHARS = 3000;
const SESSION_PREFIX_RE = /^cc-[0-9a-f]{4}:\s*/i;
const HELP_RE = /^-help$/i;
const LIST_CC_RE = /^list-cc$/i;

// --- Session ID derivation (mirrors hook script logic) ---
function deriveSessionId(): string {
  const termSessionId = process.env.TERM_SESSION_ID;
  if (termSessionId) {
    const hash = crypto.createHash('sha256').update(termSessionId).digest('hex').slice(0, 4);
    return `cc-${hash}`;
  }
  // Fallback: random ID
  const hash = crypto.randomBytes(16).toString('hex');
  const short = crypto.createHash('sha256').update(hash).digest('hex').slice(0, 4);
  return `cc-${short}`;
}

const SESSION_ID = deriveSessionId();

// --- HTTP helpers ---
function httpRequest(
  method: string,
  path: string,
  body?: Record<string, unknown>,
): Promise<{ status: number; data: Record<string, unknown> }> {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BOT_BASE);
    const options: http.RequestOptions = {
      method,
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
    };

    const req = http.request(options, (res) => {
      let raw = '';
      res.on('data', (chunk: Buffer) => (raw += chunk.toString()));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode!, data: JSON.parse(raw) });
        } catch {
          resolve({ status: res.statusCode!, data: { raw } });
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// --- Register session with bot ---
async function registerSession(): Promise<void> {
  try {
    await httpRequest('POST', '/sessions/register', {
      id: SESSION_ID,
      termSessionId: process.env.TERM_SESSION_ID || undefined,
    });
    logStderr(`Registered session ${SESSION_ID}`);
  } catch (err) {
    // Session may already be registered (idempotent), or bot may be down
    logStderr(`Session registration note: ${err}`);
  }
}

// --- Logging (to stderr so it doesn't interfere with MCP stdio) ---
function logStderr(msg: string): void {
  process.stderr.write(`[slack-channel] ${msg}\n`);
}

// --- MCP Server Setup ---
const mcpServer = new McpServer(
  {
    name: 'slack-channel',
    version: '1.0.0',
  },
  {
    capabilities: {
      logging: {},
      tools: {},
    },
    instructions: [
      `You are connected to a Slack channel server (session: ${SESSION_ID}).`,
      'Incoming Slack messages will appear as logging notifications.',
      'Use the "reply" tool to respond in a Slack thread.',
      'Use the "notify" tool to post status updates to Slack.',
      'Messages contain channel, thread_ts, user_id, and text fields.',
      'Always use the reply tool to respond in the same thread where the message originated.',
      ...(AUTONOMOUS_ENABLED
        ? ['',
           'Autonomous execution is ENABLED: incoming Slack tasks are automatically executed by a separate claude process. You do not need to act on logging notifications unless they require your direct intervention.']
        : []),
    ].join('\n'),
  },
);

// --- Tool: reply ---
mcpServer.tool(
  'slack_reply',
  'Reply to a Slack message in its thread. Use this after receiving a Slack message to respond.',
  {
    channel: z.string().describe('Slack channel ID (from the incoming message)'),
    text: z.string().describe('Reply text to send'),
    thread_ts: z.string().optional().describe('Thread timestamp to reply in (from the incoming message messageTs or threadTs)'),
  },
  async ({ channel, text, thread_ts }) => {
    try {
      const { status, data } = await httpRequest('POST', '/reply', {
        channel,
        text,
        threadTs: thread_ts,
      });

      if (status === 200) {
        return { content: [{ type: 'text' as const, text: 'Reply sent successfully.' }] };
      }
      return {
        content: [{ type: 'text' as const, text: `Reply failed (${status}): ${JSON.stringify(data)}` }],
        isError: true,
      };
    } catch (err) {
      return {
        content: [{ type: 'text' as const, text: `Reply error: ${err}` }],
        isError: true,
      };
    }
  },
);

// --- Tool: notify ---
mcpServer.tool(
  'slack_notify',
  'Post a status notification to the Slack channel. Use this for task completion updates or status reports.',
  {
    title: z.string().describe('Short title for the notification'),
    message: z.string().describe('Notification message body'),
  },
  async ({ title, message }) => {
    try {
      const { status, data } = await httpRequest('POST', '/notify', {
        title,
        message,
        sessionId: SESSION_ID,
      });

      if (status === 200) {
        return { content: [{ type: 'text' as const, text: 'Notification sent successfully.' }] };
      }
      return {
        content: [{ type: 'text' as const, text: `Notify failed (${status}): ${JSON.stringify(data)}` }],
        isError: true,
      };
    } catch (err) {
      return {
        content: [{ type: 'text' as const, text: `Notify error: ${err}` }],
        isError: true,
      };
    }
  },
);

// --- WebSocket Client (connects to bot for real-time message push) ---
let ws: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let mcpConnected = false;

// --- Autonomous execution state ---
const taskQueue: SlackMessage[] = [];
let isProcessing = false;
const seenMessageIds = new Set<string>();

interface SlackMessage {
  id: string;
  source: string;
  text: string;
  userId: string;
  channel: string;
  threadTs?: string;
  messageTs: string;
  targetSession?: string;
}

function formatSlackMessage(msg: SlackMessage): string {
  const parts = [
    `<channel source="slack-channel" channel="${msg.channel}" message_ts="${msg.messageTs}"${msg.threadTs ? ` thread_ts="${msg.threadTs}"` : ''} user_id="${msg.userId}" message_id="${msg.id}">`,
    msg.text,
    '</channel>',
  ];
  return parts.join('\n');
}

async function deliverMessage(msg: SlackMessage): Promise<void> {
  if (!mcpConnected) {
    logStderr('MCP not connected, cannot deliver message');
    return;
  }

  try {
    await mcpServer.server.sendLoggingMessage({
      level: 'info',
      logger: 'slack-channel',
      data: formatSlackMessage(msg),
    });
    logStderr(`Delivered message ${msg.id} to Claude Code`);
  } catch (err) {
    logStderr(`Failed to deliver message: ${err}`);
  }
}

// --- Autonomous execution helpers ---
function stripSessionPrefix(text: string): string {
  return text.replace(SESSION_PREFIX_RE, '').trim();
}

function expandHome(p: string): string {
  if (p.startsWith('~/') || p === '~') {
    return p.replace('~', process.env.HOME || '/tmp');
  }
  return p;
}

interface TaskDirectives {
  cwd: string;
  taskText: string;
}

function parseTaskDirectives(text: string): TaskDirectives {
  let cwd = AUTONOMOUS_WORKING_DIR;
  let remaining = text;

  // Match pwd=/some/path at the start of the text (path ends at whitespace)
  const pwdMatch = remaining.match(/^pwd=(\S+)\s*/);
  if (pwdMatch) {
    cwd = expandHome(pwdMatch[1]);
    remaining = remaining.slice(pwdMatch[0].length).trim();
  }

  return { cwd, taskText: remaining };
}

function truncateForSlack(text: string): string {
  if (text.length <= SLACK_REPLY_MAX_CHARS) return text;
  return text.slice(0, SLACK_REPLY_MAX_CHARS - 20) + '\n\n...(truncated)';
}

async function executeTask(msg: SlackMessage): Promise<void> {
  const stripped = stripSessionPrefix(msg.text);
  const { cwd, taskText } = parseTaskDirectives(stripped);
  logStderr(`[autonomous] Executing task: ${taskText.slice(0, 80)}... (cwd=${cwd})`);

  // Validate working directory exists
  if (!fs.existsSync(cwd)) {
    logStderr(`[autonomous] Directory not found: ${cwd}`);
    try {
      await httpRequest('POST', '/reply', {
        channel: msg.channel,
        text: `Directory not found: \`${cwd}\`\nPlease check the path and try again.`,
        threadTs: msg.threadTs || msg.messageTs,
      });
    } catch (err) {
      logStderr(`[autonomous] Failed to post error reply: ${err}`);
    }
    return;
  }

  // Post a "working on it" reply first
  try {
    await httpRequest('POST', '/reply', {
      channel: msg.channel,
      text: `Working on this task now...\n_Working directory: \`${cwd}\`_`,
      threadTs: msg.threadTs || msg.messageTs,
    });
  } catch (err) {
    logStderr(`[autonomous] Failed to post working reply: ${err}`);
  }

  const prompt = [
    `You are an autonomous Claude Code agent executing a task.`,
    `Working directory: ${cwd}`,
    ``,
    `IMPORTANT: Do NOT attempt to reply to Slack or use any Slack/MCP/notification tools.`,
    `Do NOT use curl to post to any API. Just execute the task and print your result to stdout.`,
    `Your stdout output will be captured and posted as a reply automatically.`,
    ``,
    `Task:`,
    taskText,
    ``,
    `Execute this task. Be concise — keep output under 3000 characters.`,
  ].join('\n');

  return new Promise<void>((resolve) => {
    const args = [
      '-p', prompt,
      '--max-turns', String(AUTONOMOUS_MAX_TURNS),
      '--allowedTools', 'Bash,Read,Write,Edit,Glob,Grep',
    ];

    const child = execFile('claude', args, {
      cwd,
      timeout: AUTONOMOUS_TIMEOUT_MS,
      maxBuffer: 10 * 1024 * 1024, // 10 MB
      env: { ...process.env, DISABLE_INTERACTIVITY: '1' },
    }, async (error, stdout, stderr) => {
      logStderr(`[autonomous] claude -p exited (error=${!!error}, stdout=${stdout.length} bytes, stderr=${stderr.length} bytes)`);
      let replyText: string;

      if (error) {
        logStderr(`[autonomous] Task error: ${error.message}`);
        if (stderr) logStderr(`[autonomous] stderr: ${stderr.slice(0, 500)}`);
        replyText = `Task failed: ${error.message}`;
        if (stdout) {
          replyText = truncateForSlack(stdout);
        }
      } else {
        replyText = truncateForSlack(stdout.trim() || '(no output)');
      }

      // Post result as Slack reply
      try {
        await httpRequest('POST', '/reply', {
          channel: msg.channel,
          text: replyText,
          threadTs: msg.threadTs || msg.messageTs,
        });
        logStderr(`[autonomous] Replied in Slack thread`);
      } catch (err) {
        logStderr(`[autonomous] Failed to post reply: ${err}`);
      }

      resolve();
    });

    // Close child stdin so claude -p doesn't hang waiting for input
    if (child.stdin) child.stdin.end();

    // Safety note: execFile with callback already creates its own pipes for
    // child stdout/stderr — it never inherits our process stdout (MCP transport).
    // Do NOT call removeAllListeners('data') here, as that would strip the
    // internal listeners execFile uses to collect output into the callback.
  });
}

async function processQueue(): Promise<void> {
  if (isProcessing) return;
  isProcessing = true;

  while (taskQueue.length > 0) {
    const msg = taskQueue.shift()!;
    try {
      await executeTask(msg);
    } catch (err) {
      logStderr(`[autonomous] Unexpected error processing task: ${err}`);
    }
  }

  isProcessing = false;
}

function enqueueTask(msg: SlackMessage): void {
  if (!AUTONOMOUS_ENABLED) return;
  // Skip built-in commands — handled directly by the bot
  const textForCheck = stripSessionPrefix(msg.text);
  if (HELP_RE.test(textForCheck) || LIST_CC_RE.test(textForCheck)) {
    logStderr(`[autonomous] Skipping built-in command`);
    return;
  }
  // Deduplicate by both msg.id and msg.messageTs — the same Slack message can
  // arrive via WebSocket push and fetchMissedMessages with different internal IDs
  const dedupeKey = msg.messageTs || msg.id;
  if (seenMessageIds.has(msg.id) || seenMessageIds.has(dedupeKey)) {
    logStderr(`[autonomous] Skipping duplicate message ${msg.id} (ts=${msg.messageTs})`);
    return;
  }
  seenMessageIds.add(msg.id);
  seenMessageIds.add(dedupeKey);
  // Prevent unbounded growth of seen set
  while (seenMessageIds.size > 1000) {
    const first = seenMessageIds.values().next().value;
    if (first !== undefined) seenMessageIds.delete(first);
    else break;
  }
  taskQueue.push(msg);
  logStderr(`[autonomous] Enqueued task id=${msg.id} ts=${msg.messageTs} (queue size: ${taskQueue.length})`);
  processQueue();
}

async function fetchMissedMessages(): Promise<void> {
  try {
    const { status, data } = await httpRequest(
      'GET',
      `/messages?unread=true&mark_read=true&session_id=${SESSION_ID}`,
    );

    if (status === 200 && Array.isArray(data.messages)) {
      for (const msg of data.messages as SlackMessage[]) {
        await deliverMessage(msg);
        // Note: do NOT enqueueTask here — these are messages that arrived while
        // disconnected. The WebSocket handler is the sole autonomous trigger to
        // prevent double execution. Missed messages get MCP notification only.
      }
      if ((data.messages as SlackMessage[]).length > 0) {
        logStderr(`Delivered ${(data.messages as SlackMessage[]).length} missed message(s)`);
      }
    }
  } catch (err) {
    logStderr(`Failed to fetch missed messages: ${err}`);
  }
}

function connectWebSocket(): void {
  if (ws) {
    ws.removeAllListeners();
    ws.close();
  }

  const wsUrl = `${WS_URL}?session_id=${SESSION_ID}`;
  logStderr(`Connecting to WebSocket: ${wsUrl}`);

  ws = new WebSocket(wsUrl);

  ws.on('open', () => {
    logStderr('WebSocket connected');
    // Fetch any messages that arrived while disconnected
    fetchMissedMessages();
  });

  ws.on('message', (data) => {
    try {
      const parsed = JSON.parse(data.toString());
      if (parsed.type === 'message' && parsed.message) {
        deliverMessage(parsed.message as SlackMessage);
        enqueueTask(parsed.message as SlackMessage);
      }
    } catch (err) {
      logStderr(`Failed to parse WebSocket message: ${err}`);
    }
  });

  ws.on('close', () => {
    logStderr('WebSocket disconnected, will reconnect...');
    scheduleReconnect();
  });

  ws.on('error', (err) => {
    logStderr(`WebSocket error: ${err.message}`);
    // close event will fire after error, triggering reconnect
  });

  // Respond to server pings to stay alive
  ws.on('ping', () => {
    ws?.pong();
  });
}

function scheduleReconnect(): void {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectWebSocket();
  }, RECONNECT_DELAY_MS);
}

// --- Main ---
async function main(): Promise<void> {
  // Check if claude CLI is available when autonomous mode is enabled
  if (AUTONOMOUS_ENABLED) {
    try {
      execFileSync('which', ['claude'], { stdio: 'ignore' });
      logStderr(`Autonomous mode ENABLED (max_turns=${AUTONOMOUS_MAX_TURNS}, timeout=${AUTONOMOUS_TIMEOUT_MS}ms)`);
    } catch {
      logStderr('WARNING: Autonomous mode is enabled but "claude" CLI not found in PATH. Tasks will fail.');
    }
  } else {
    logStderr('Autonomous mode DISABLED');
  }

  // Register session first
  await registerSession();

  // Connect MCP via stdio
  const transport = new StdioServerTransport();
  await mcpServer.connect(transport);
  mcpConnected = true;
  logStderr('MCP server connected via stdio');

  // Connect WebSocket for real-time messages
  connectWebSocket();

  // Clean shutdown
  const shutdown = (signal: string) => {
    logStderr(`Shutting down (${signal})...`);
    if (isProcessing || taskQueue.length > 0) {
      logStderr(`WARNING: ${taskQueue.length} task(s) queued, ${isProcessing ? '1 task still running' : 'none running'}`);
    }
    if (reconnectTimer) clearTimeout(reconnectTimer);
    ws?.close();
    mcpServer.close();
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  logStderr(`Fatal error: ${err}`);
  process.exit(1);
});
