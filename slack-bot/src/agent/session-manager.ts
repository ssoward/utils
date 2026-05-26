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
