import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import WebSocket from 'ws';
import { startCliBridge } from '../notifier/cli-bridge.js';
import { registerSession, unregisterSession } from '../session-registry/registry.js';
import { clearQueue } from '../message-queue/queue.js';
import { pushToClients, _getClients } from '../notifier/ws-bridge.js';
import type { SlackIncomingMessage } from '../types.js';

const TEST_PORT = 39849;
const BASE = `http://127.0.0.1:${TEST_PORT}`;
const WS_URL = `ws://127.0.0.1:${TEST_PORT}/ws`;
const SESSIONS_FILE = path.resolve(process.cwd(), 'data', 'sessions.json');

let server: http.Server;

function request(
  method: string,
  urlPath: string,
  body?: unknown,
): Promise<{ status: number; data: Record<string, unknown> }> {
  return new Promise((resolve, reject) => {
    const url = new URL(urlPath, BASE);
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

function makeMessage(overrides: Partial<SlackIncomingMessage> = {}): SlackIncomingMessage {
  return {
    id: 'test-msg-1',
    source: 'mention',
    text: 'hello world',
    userId: 'U123',
    channel: 'C456',
    messageTs: '1234567890.123456',
    receivedAt: new Date().toISOString(),
    read: false,
    ...overrides,
  };
}

function connectWs(sessionId: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS_URL}?session_id=${sessionId}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitForMessage(ws: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve) => {
    ws.once('message', (data) => {
      resolve(JSON.parse(data.toString()));
    });
  });
}

function waitForCloseOrError(ws: WebSocket): Promise<void> {
  return new Promise((resolve) => {
    ws.once('close', () => resolve());
    ws.once('error', () => {
      // Error during upgrade (e.g., 400/403) — ws will close after this
      if (ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING) {
        resolve();
      } else {
        ws.once('close', () => resolve());
      }
    });
  });
}

describe('WebSocket bridge', () => {
  beforeAll(
    () =>
      new Promise<void>((resolve) => {
        server = startCliBridge(TEST_PORT);
        server.on('listening', resolve);
      }),
  );

  afterAll(
    () =>
      new Promise<void>((resolve) => {
        server.close(() => resolve());
      }),
  );

  beforeEach(() => {
    clearQueue();
    if (fs.existsSync(SESSIONS_FILE)) fs.unlinkSync(SESSIONS_FILE);
  });

  afterEach(() => {
    // Close any remaining WebSocket clients
    for (const [, entry] of _getClients()) {
      entry.ws.close();
    }
    _getClients().clear();
  });

  describe('connection', () => {
    it('should reject connection without session_id', async () => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}/ws`);
      const closePromise = waitForCloseOrError(ws);
      await closePromise;
      expect(ws.readyState).toBe(WebSocket.CLOSED);
    });

    it('should reject connection for unregistered session', async () => {
      const ws = new WebSocket(`${WS_URL}?session_id=cc-nope`);
      const closePromise = waitForCloseOrError(ws);
      await closePromise;
      expect(ws.readyState).toBe(WebSocket.CLOSED);
    });

    it('should accept connection for registered session', async () => {
      registerSession('cc-ws01');
      const ws = await connectWs('cc-ws01');
      expect(ws.readyState).toBe(WebSocket.OPEN);
      expect(_getClients().has('cc-ws01')).toBe(true);
      ws.close();
      unregisterSession('cc-ws01');
    });

    it('should replace existing connection for same session', async () => {
      registerSession('cc-ws02');
      const ws1 = await connectWs('cc-ws02');
      const close1Promise = waitForCloseOrError(ws1);

      const ws2 = await connectWs('cc-ws02');
      await close1Promise; // ws1 should be closed by the server

      expect(ws2.readyState).toBe(WebSocket.OPEN);
      expect(_getClients().size).toBe(1);
      ws2.close();
      unregisterSession('cc-ws02');
    });
  });

  describe('message push', () => {
    it('should push targeted message to the correct session', async () => {
      registerSession('cc-ws03');
      const ws = await connectWs('cc-ws03');
      const msgPromise = waitForMessage(ws);

      const msg = makeMessage({ targetSession: 'cc-ws03' });
      pushToClients(msg);

      const received = await msgPromise;
      expect(received.type).toBe('message');
      expect((received.message as Record<string, unknown>).text).toBe('hello world');

      ws.close();
      unregisterSession('cc-ws03');
    });

    it('should not push targeted message to other sessions', async () => {
      registerSession('cc-ws04');
      registerSession('cc-ws05');
      const ws4 = await connectWs('cc-ws04');
      const ws5 = await connectWs('cc-ws05');

      let ws4Received = false;
      ws4.on('message', () => { ws4Received = true; });

      const msg = makeMessage({ targetSession: 'cc-ws05' });
      const msg5Promise = waitForMessage(ws5);
      pushToClients(msg);

      await msg5Promise; // ws5 should receive it
      // Give ws4 a moment to potentially receive (should not)
      await new Promise((r) => setTimeout(r, 50));
      expect(ws4Received).toBe(false);

      ws4.close();
      ws5.close();
      unregisterSession('cc-ws04');
      unregisterSession('cc-ws05');
    });

    it('should broadcast message to all sessions when no targetSession', async () => {
      registerSession('cc-ws06');
      registerSession('cc-ws07');
      const ws6 = await connectWs('cc-ws06');
      const ws7 = await connectWs('cc-ws07');

      const msg6Promise = waitForMessage(ws6);
      const msg7Promise = waitForMessage(ws7);

      const msg = makeMessage(); // no targetSession
      pushToClients(msg);

      const [recv6, recv7] = await Promise.all([msg6Promise, msg7Promise]);
      expect(recv6.type).toBe('message');
      expect(recv7.type).toBe('message');

      ws6.close();
      ws7.close();
      unregisterSession('cc-ws06');
      unregisterSession('cc-ws07');
    });
  });

  describe('disconnect cleanup', () => {
    it('should remove client from map on disconnect', async () => {
      registerSession('cc-ws08');
      const ws = await connectWs('cc-ws08');
      expect(_getClients().has('cc-ws08')).toBe(true);

      ws.close();
      await waitForCloseOrError(ws);
      // Give server a tick to process the close event
      await new Promise((r) => setTimeout(r, 50));

      expect(_getClients().has('cc-ws08')).toBe(false);
      unregisterSession('cc-ws08');
    });
  });

  describe('GET /sessions includes wsConnected', () => {
    it('should show wsConnected: true for connected sessions', async () => {
      registerSession('cc-ws09');
      const ws = await connectWs('cc-ws09');

      const { data } = await request('GET', '/sessions');
      const sessions = data.sessions as Array<Record<string, unknown>>;
      const session = sessions.find((s) => s.id === 'cc-ws09');
      expect(session).toBeDefined();
      expect(session!.wsConnected).toBe(true);

      ws.close();
      unregisterSession('cc-ws09');
    });

    it('should show wsConnected: false for sessions without WebSocket', async () => {
      registerSession('cc-ws10');

      const { data } = await request('GET', '/sessions');
      const sessions = data.sessions as Array<Record<string, unknown>>;
      const session = sessions.find((s) => s.id === 'cc-ws10');
      expect(session).toBeDefined();
      expect(session!.wsConnected).toBe(false);

      unregisterSession('cc-ws10');
    });
  });

  describe('non-/ws upgrade path', () => {
    it('should reject WebSocket upgrade on non-/ws path', async () => {
      const ws = new WebSocket(`ws://127.0.0.1:${TEST_PORT}/other`);
      const closePromise = waitForCloseOrError(ws);
      await closePromise;
      expect(ws.readyState).toBe(WebSocket.CLOSED);
    });
  });
});
