#!/usr/bin/env node
/**
 * MCP Channel Server for real-time Slack <-> Claude Code messaging.
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
import http from 'node:http';

// --- Configuration ---
const BOT_PORT = parseInt(process.env.SLACK_BOT_PORT || '3848', 10);
const BOT_BASE = `http://127.0.0.1:${BOT_PORT}`;
const WS_URL = `ws://127.0.0.1:${BOT_PORT}/ws`;
const RECONNECT_DELAY_MS = 5_000;

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

async function fetchMissedMessages(): Promise<void> {
  try {
    const { status, data } = await httpRequest(
      'GET',
      `/messages?unread=true&mark_read=true&session_id=${SESSION_ID}`,
    );

    if (status === 200 && Array.isArray(data.messages)) {
      for (const msg of data.messages as SlackMessage[]) {
        await deliverMessage(msg);
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
