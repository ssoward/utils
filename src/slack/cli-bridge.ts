import http from 'node:http';
import { sendMessage, replyInThread } from './sender.js';
import { logger } from '../utils/logger.js';
import { getUnreadMessages, getUnreadMessagesForSession, getAllMessages, markAsRead, clearQueue } from '../message-queue/index.js';
import { registerSession, unregisterSession, getActiveSessions, touchSession } from '../session-registry/index.js';
import { createWebSocketServer, isWsConnected, closeWebSocketServer } from './ws-bridge.js';
import { getExecutorStatus } from '../agent/executor.js';
import { listSessions as listAgentSessions, getSession as getAgentSession } from '../agent/session-manager.js';
import { routeMessage } from '../agent/router.js';
import type { NotifyPayload, ReplyPayload } from '../types.js';

const COMPONENT = 'cli-bridge';
const MAX_BODY_BYTES = 1024 * 1024; // 1 MB
const SAFE_PATH_SEGMENT_RE = /^[a-zA-Z0-9._-]+$/;

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let totalBytes = 0;
    req.on('data', (chunk: Buffer) => {
      totalBytes += chunk.length;
      if (totalBytes > MAX_BODY_BYTES) {
        req.destroy();
        reject(new Error('Request body too large'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function sendJson(
  res: http.ServerResponse,
  statusCode: number,
  body: Record<string, unknown>,
): void {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function parseUrl(raw: string | undefined): { pathname: string; params: URLSearchParams } {
  const url = new URL(raw || '/', 'http://localhost');
  return { pathname: url.pathname, params: url.searchParams };
}

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
    await sendMessage(text, undefined, payload.channel);
    sendJson(res, 200, { ok: true });
  } catch (error) {
    logger.error(COMPONENT, 'Failed to send notification', {
      error: error instanceof Error ? error.message : String(error),
    });
    sendJson(res, 500, { error: 'Failed to send message' });
  }
}

function handleGetMessages(params: URLSearchParams, res: http.ServerResponse): void {
  const unreadOnly = params.get('unread') !== 'false';
  const shouldMarkRead = params.get('mark_read') === 'true';
  const limitStr = params.get('limit');
  const limitParsed = limitStr ? parseInt(limitStr, 10) : NaN;
  const limit = Number.isFinite(limitParsed) && limitParsed > 0 ? limitParsed : undefined;
  const sessionId = params.get('session_id');

  // Touch session to keep it alive
  if (sessionId) {
    touchSession(sessionId);
  }

  let messages;
  if (sessionId && unreadOnly) {
    messages = getUnreadMessagesForSession(sessionId);
  } else if (unreadOnly) {
    messages = getUnreadMessages();
  } else {
    messages = getAllMessages(limit);
  }

  if (shouldMarkRead && messages.length > 0) {
    const ids = messages.filter((m) => !m.read).map((m) => m.id);
    if (ids.length > 0) markAsRead(ids);
  }

  sendJson(res, 200, { ok: true, count: messages.length, messages });
}

async function handleReplyPost(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const raw = await readBody(req);
  let payload: ReplyPayload;
  try {
    payload = JSON.parse(raw) as ReplyPayload;
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON' });
    return;
  }

  if (!payload.channel || !payload.text) {
    sendJson(res, 400, { error: 'Missing required fields: channel, text' });
    return;
  }

  try {
    await replyInThread(payload.channel, payload.text, payload.threadTs);
    sendJson(res, 200, { ok: true });
  } catch (error) {
    logger.error(COMPONENT, 'Failed to send reply', {
      error: error instanceof Error ? error.message : String(error),
    });
    sendJson(res, 500, { error: 'Failed to send reply' });
  }
}

async function handleMarkReadPost(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const raw = await readBody(req);
  let body: { ids?: string[] };
  try {
    body = JSON.parse(raw) as { ids?: string[] };
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON' });
    return;
  }

  const count = markAsRead(body.ids);
  sendJson(res, 200, { ok: true, marked: count });
}

async function handleSessionRegister(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const raw = await readBody(req);
  let body: { id?: string; termSessionId?: string };
  try {
    body = JSON.parse(raw) as { id?: string; termSessionId?: string };
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON' });
    return;
  }

  if (!body.id || typeof body.id !== 'string') {
    sendJson(res, 400, { error: 'Missing required field: id' });
    return;
  }

  try {
    const session = registerSession(body.id, body.termSessionId);
    sendJson(res, 200, { ok: true, session });
  } catch (error) {
    sendJson(res, 409, { error: error instanceof Error ? error.message : String(error) });
  }
}

function handleGetSessions(res: http.ServerResponse): void {
  const sessions = getActiveSessions().map((s) => ({
    ...s,
    wsConnected: isWsConnected(s.id),
  }));
  sendJson(res, 200, { ok: true, count: sessions.length, sessions });
}

function handleDeleteSession(sessionId: string, res: http.ServerResponse): void {
  const removed = unregisterSession(sessionId);
  if (removed) {
    sendJson(res, 200, { ok: true, removed: sessionId });
  } else {
    sendJson(res, 404, { error: `Session "${sessionId}" not found` });
  }
}

function handleDeleteMessages(res: http.ServerResponse): void {
  const count = clearQueue();
  sendJson(res, 200, { ok: true, cleared: count });
}

async function handleAgentTaskPost(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const raw = await readBody(req);
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
  const ts = body.threadTs || `${(Date.now() / 1000).toFixed(6)}`;
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
}

function handleRequest(req: http.IncomingMessage, res: http.ServerResponse): void {
  const { method } = req;
  const { pathname, params } = parseUrl(req.url);

  // Health check
  if (pathname === '/health' && method === 'GET') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  // POST /notify — send formatted notification to Slack
  if (pathname === '/notify' && method === 'POST') {
    handleNotifyPost(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in notify handler', { error: String(err) });
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    });
    return;
  }

  // GET /messages — read queued messages
  if (pathname === '/messages' && method === 'GET') {
    handleGetMessages(params, res);
    return;
  }

  // POST /reply — send reply to Slack channel/thread
  if (pathname === '/reply' && method === 'POST') {
    handleReplyPost(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in reply handler', { error: String(err) });
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    });
    return;
  }

  // POST /messages/mark-read — mark messages as read
  if (pathname === '/messages/mark-read' && method === 'POST') {
    handleMarkReadPost(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in mark-read handler', { error: String(err) });
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    });
    return;
  }

  // DELETE /messages — clear queue
  if (pathname === '/messages' && method === 'DELETE') {
    handleDeleteMessages(res);
    return;
  }

  // POST /sessions/register — register a session
  if (pathname === '/sessions/register' && method === 'POST') {
    handleSessionRegister(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in session register handler', { error: String(err) });
      if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    });
    return;
  }

  // GET /sessions — list active sessions
  if (pathname === '/sessions' && method === 'GET') {
    handleGetSessions(res);
    return;
  }

  // DELETE /sessions/:id — unregister a session
  const sessionDeleteMatch = pathname.match(/^\/sessions\/([a-z0-9-]+)$/i);
  if (sessionDeleteMatch && method === 'DELETE') {
    handleDeleteSession(sessionDeleteMatch[1], res);
    return;
  }

  // GET /agent/status — agent executor status
  if (pathname === '/agent/status' && method === 'GET') {
    const status = getExecutorStatus();
    sendJson(res, 200, { ok: true, ...status });
    return;
  }

  // POST /agent/task — submit a task programmatically
  if (pathname === '/agent/task' && method === 'POST') {
    handleAgentTaskPost(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in agent task handler', { error: String(err) });
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
    const channel = decodeURIComponent(sessionMatch[1]);
    const threadTs = decodeURIComponent(sessionMatch[2]);
    if (!SAFE_PATH_SEGMENT_RE.test(channel) || !SAFE_PATH_SEGMENT_RE.test(threadTs)) {
      sendJson(res, 400, { error: 'Invalid channel or threadTs format' });
      return;
    }
    const session = getAgentSession(channel, threadTs);
    if (session) {
      sendJson(res, 200, { ok: true, session: session as unknown as Record<string, unknown> });
    } else {
      sendJson(res, 404, { error: 'Session not found' });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
}

export function startCliBridge(port: number): http.Server {
  const server = http.createServer(handleRequest);

  // Attach WebSocket server for real-time channel push
  createWebSocketServer(server);

  server.listen(port, '127.0.0.1');

  // Clean up WebSocket server on close
  server.on('close', () => {
    closeWebSocketServer();
  });

  return server;
}
