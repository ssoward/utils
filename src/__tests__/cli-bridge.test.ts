import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { startCliBridge } from '../slack/cli-bridge.js';
import { enqueueMessage, clearQueue } from '../message-queue/queue.js';
import { unregisterSession } from '../session-registry/registry.js';

// Use a random high port to avoid conflicts
const TEST_PORT = 39848;
const BASE = `http://127.0.0.1:${TEST_PORT}`;
const QUEUE_FILE = path.resolve(process.cwd(), 'data', 'messages.json');
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

function requestRaw(
  method: string,
  urlPath: string,
): Promise<{ status: number; headers: http.IncomingHttpHeaders; body: string }> {
  return new Promise((resolve, reject) => {
    const url = new URL(urlPath, BASE);
    const req = http.request(
      { method, hostname: url.hostname, port: url.port, path: url.pathname + url.search },
      (res) => {
        let raw = '';
        res.on('data', (chunk: Buffer) => (raw += chunk.toString()));
        res.on('end', () => resolve({ status: res.statusCode!, headers: res.headers, body: raw }));
      },
    );
    req.on('error', reject);
    req.end();
  });
}

describe('cli-bridge HTTP endpoints', () => {
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
    // Clean sessions file between tests
    if (fs.existsSync(SESSIONS_FILE)) fs.unlinkSync(SESSIONS_FILE);
  });

  describe('GET /health', () => {
    it('should return ok status', async () => {
      const { status, data } = await request('GET', '/health');
      expect(status).toBe(200);
      expect(data).toEqual({ status: 'ok' });
    });
  });

  describe('GET /messages', () => {
    it('should return empty when no messages', async () => {
      const { status, data } = await request('GET', '/messages');
      expect(status).toBe(200);
      expect(data).toEqual({ ok: true, count: 0, messages: [] });
    });

    it('should return unread messages by default', async () => {
      enqueueMessage('dm', 'hello', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'world', 'U2', 'D2', '2.0');

      const { status, data } = await request('GET', '/messages');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.count).toBe(2);
      expect(Array.isArray(data.messages)).toBe(true);
    });

    it('should mark messages as read when mark_read=true', async () => {
      enqueueMessage('dm', 'hello', 'U1', 'D1', '1.0');

      await request('GET', '/messages?mark_read=true');

      const { data } = await request('GET', '/messages');
      expect(data.count).toBe(0); // no unread left
    });

    it('should return all messages when unread=false', async () => {
      enqueueMessage('dm', 'hello', 'U1', 'D1', '1.0');
      await request('GET', '/messages?mark_read=true'); // mark read

      const { data } = await request('GET', '/messages?unread=false');
      expect(data.count).toBe(1); // still returns the read message
    });

    it('should respect limit parameter', async () => {
      for (let i = 0; i < 5; i++) {
        enqueueMessage('dm', `msg-${i}`, 'U1', 'D1', `${i}.0`);
      }

      const { data } = await request('GET', '/messages?unread=false&limit=2');
      expect(data.count).toBe(2);
    });
  });

  describe('POST /messages/mark-read', () => {
    it('should mark all messages as read when no ids', async () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');

      const { status, data } = await request('POST', '/messages/mark-read', {});
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.marked).toBe(2);

      const { data: after } = await request('GET', '/messages');
      expect(after.count).toBe(0);
    });

    it('should mark specific ids as read', async () => {
      const id1 = enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');

      const { data } = await request('POST', '/messages/mark-read', { ids: [id1] });
      expect(data.marked).toBe(1);

      const { data: remaining } = await request('GET', '/messages');
      expect(remaining.count).toBe(1);
    });

    it('should return 400 for invalid JSON', async () => {
      const { status } = await request('POST', '/messages/mark-read', undefined);
      // Sending empty body
      expect(status).toBe(400);
    });
  });

  describe('DELETE /messages', () => {
    it('should clear all messages', async () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');

      const { status, data } = await request('DELETE', '/messages');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.cleared).toBe(2);

      const { data: after } = await request('GET', '/messages?unread=false');
      expect(after.count).toBe(0);
    });
  });

  describe('POST /reply', () => {
    it('should return 400 when missing required fields', async () => {
      const { status, data } = await request('POST', '/reply', { text: 'hi' });
      expect(status).toBe(400);
      expect(data.error).toBe('Missing required fields: channel, text');
    });

    it('should return 400 for invalid JSON', async () => {
      const { status } = await request('POST', '/reply', undefined);
      expect(status).toBe(400);
    });

    // Note: Actual Slack send requires valid credentials; we test validation only
  });

  describe('POST /notify', () => {
    it('should return 400 when missing message field', async () => {
      const { status, data } = await request('POST', '/notify', { title: 'oops' });
      expect(status).toBe(400);
      expect(data.error).toBe('Missing required field: message');
    });

    it('should return 400 for invalid JSON', async () => {
      const { status } = await request('POST', '/notify', undefined);
      expect(status).toBe(400);
    });
  });

  describe('POST /sessions/register', () => {
    it('should register a new session', async () => {
      const { status, data } = await request('POST', '/sessions/register', { id: 'cc-test' });
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect((data.session as Record<string, unknown>).id).toBe('cc-test');
    });

    it('should return 400 when missing id', async () => {
      const { status, data } = await request('POST', '/sessions/register', {});
      expect(status).toBe(400);
      expect(data.error).toBe('Missing required field: id');
    });

    it('should return 409 on duplicate registration from different terminal', async () => {
      await request('POST', '/sessions/register', { id: 'cc-dup1' });
      const { status } = await request('POST', '/sessions/register', { id: 'cc-dup1' });
      expect(status).toBe(409);
    });

    it('should allow idempotent re-registration from same terminal', async () => {
      await request('POST', '/sessions/register', { id: 'cc-idem', termSessionId: 'term-x' });
      const { status, data } = await request('POST', '/sessions/register', { id: 'cc-idem', termSessionId: 'term-x' });
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
    });

    it('should return 400 for invalid JSON', async () => {
      const { status } = await request('POST', '/sessions/register', undefined);
      expect(status).toBe(400);
    });
  });

  describe('GET /sessions', () => {
    it('should return empty when no sessions', async () => {
      const { status, data } = await request('GET', '/sessions');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.count).toBe(0);
      expect(data.sessions).toEqual([]);
    });

    it('should return registered sessions', async () => {
      await request('POST', '/sessions/register', { id: 'cc-s001' });
      await request('POST', '/sessions/register', { id: 'cc-s002' });
      const { data } = await request('GET', '/sessions');
      expect(data.count).toBe(2);
    });
  });

  describe('DELETE /sessions/:id', () => {
    it('should remove a registered session', async () => {
      await request('POST', '/sessions/register', { id: 'cc-del1' });
      const { status, data } = await request('DELETE', '/sessions/cc-del1');
      expect(status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.removed).toBe('cc-del1');
    });

    it('should return 404 for non-existent session', async () => {
      const { status } = await request('DELETE', '/sessions/cc-nope');
      expect(status).toBe(404);
    });
  });

  describe('GET /messages with session_id', () => {
    it('should return only messages visible to the session', async () => {
      await request('POST', '/sessions/register', { id: 'cc-f001' });

      enqueueMessage('dm', 'broadcast msg', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'for f001', 'U1', 'D1', '2.0', undefined, 'cc-f001');
      enqueueMessage('dm', 'for other', 'U1', 'D1', '3.0', undefined, 'cc-other');

      const { data } = await request('GET', '/messages?session_id=cc-f001');
      expect(data.count).toBe(2);
      const texts = (data.messages as Array<{ text: string }>).map((m) => m.text);
      expect(texts).toContain('broadcast msg');
      expect(texts).toContain('for f001');
      expect(texts).not.toContain('for other');
    });

    it('should mark session messages as read when mark_read=true', async () => {
      await request('POST', '/sessions/register', { id: 'cc-mr01' });
      enqueueMessage('dm', 'hello', 'U1', 'D1', '1.0');

      await request('GET', '/messages?session_id=cc-mr01&mark_read=true');
      const { data } = await request('GET', '/messages?session_id=cc-mr01');
      expect(data.count).toBe(0);
    });
  });

  describe('POST /notify with sessionId', () => {
    it('should return 400 when missing message (sessionId does not bypass validation)', async () => {
      const { status, data } = await request('POST', '/notify', { title: 'Test', sessionId: 'cc-n001' });
      expect(status).toBe(400);
      expect(data.error).toBe('Missing required field: message');
    });
  });

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

  describe('404 handling', () => {
    it('should return 404 for unknown routes', async () => {
      const { status, data } = await request('GET', '/nonexistent');
      expect(status).toBe(404);
      expect(data.error).toBe('Not found');
    });
  });
});
