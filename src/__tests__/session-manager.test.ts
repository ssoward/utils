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
    getOrCreateSession('C123', '1.0', '/tmp');
    const sessionFile = path.join(SESSIONS_DIR, 'C123-1.0.json');
    const data = JSON.parse(fs.readFileSync(sessionFile, 'utf-8'));
    data.lastActiveAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
    fs.writeFileSync(sessionFile, JSON.stringify(data));

    const removed = cleanStaleSessions(24);
    expect(removed).toBe(1);

    const after = getSession('C123', '1.0');
    expect(after).toBeNull();
  });
});
