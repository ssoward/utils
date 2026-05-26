import http from 'node:http';
import { formatHookEvent } from './formatters.js';
import { sendBlocks } from '../notifier/slack-sender.js';
import { logger } from '../utils/logger.js';
import type { ClaudeHookEvent } from '../types.js';

const COMPONENT = 'hook-receiver';

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => chunks.push(chunk));
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

async function handleHookPost(
  req: http.IncomingMessage,
  res: http.ServerResponse,
): Promise<void> {
  let raw: string;
  try {
    raw = await readBody(req);
  } catch (err) {
    logger.error(COMPONENT, 'Failed to read request body', {
      error: String(err),
    });
    sendJson(res, 400, { error: 'Failed to read request body' });
    return;
  }

  let event: ClaudeHookEvent;
  try {
    event = JSON.parse(raw) as ClaudeHookEvent;
  } catch {
    logger.error(COMPONENT, 'Invalid JSON in request body', {
      body: raw.slice(0, 500),
    });
    sendJson(res, 400, { error: 'Invalid JSON' });
    return;
  }

  logger.info(COMPONENT, 'Received hook event', {
    type: event.type,
    sessionId: event.sessionId,
  });

  const blocks = formatHookEvent(event);

  try {
    await sendBlocks(blocks);
    logger.info(COMPONENT, 'Forwarded event to Slack', { type: event.type });
    sendJson(res, 200, { ok: true });
  } catch (err) {
    logger.error(COMPONENT, 'Failed to send blocks to Slack', {
      error: String(err),
    });
    sendJson(res, 502, { error: 'Failed to forward to Slack' });
  }
}

function handleRequest(
  req: http.IncomingMessage,
  res: http.ServerResponse,
): void {
  const { method, url } = req;

  if (url === '/health' && method === 'GET') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  if (url === '/hook') {
    if (method !== 'POST') {
      sendJson(res, 405, { error: 'Method not allowed' });
      return;
    }
    handleHookPost(req, res).catch((err) => {
      logger.error(COMPONENT, 'Unhandled error in hook handler', {
        error: String(err),
      });
      if (!res.headersSent) {
        sendJson(res, 500, { error: 'Internal server error' });
      }
    });
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
}

export function startHookReceiver(port: number): http.Server {
  const server = http.createServer(handleRequest);

  server.listen(port, '127.0.0.1', () => {
    logger.info(COMPONENT, `Hook receiver listening on 127.0.0.1:${port}`);
  });

  return server;
}
