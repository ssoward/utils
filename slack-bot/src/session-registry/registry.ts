import fs from 'node:fs';
import path from 'node:path';
import { logger } from '../utils/logger.js';
import type { SessionInfo, SessionRegistryFile } from '../types.js';

const COMPONENT = 'session-registry';
const DATA_DIR = path.resolve(process.cwd(), 'data');
const REGISTRY_FILE = path.join(DATA_DIR, 'sessions.json');

const DEFAULT_MAX_AGE_MINUTES = 60;

function ensureDataDir(): void {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function readRegistry(): SessionRegistryFile {
  ensureDataDir();
  if (!fs.existsSync(REGISTRY_FILE)) {
    return { version: 1, lastUpdated: new Date().toISOString(), sessions: [] };
  }
  try {
    const raw = fs.readFileSync(REGISTRY_FILE, 'utf-8');
    return JSON.parse(raw) as SessionRegistryFile;
  } catch (err) {
    logger.error(COMPONENT, 'Failed to read registry file, resetting', { error: String(err) });
    return { version: 1, lastUpdated: new Date().toISOString(), sessions: [] };
  }
}

function writeRegistry(registry: SessionRegistryFile): void {
  ensureDataDir();
  registry.lastUpdated = new Date().toISOString();
  fs.writeFileSync(REGISTRY_FILE, JSON.stringify(registry, null, 2), 'utf-8');
}

export function registerSession(id: string, termSessionId?: string): SessionInfo {
  const registry = readRegistry();

  const existing = registry.sessions.find((s) => s.id === id);
  if (existing) {
    // Re-registration from same terminal session is allowed (idempotent)
    if (termSessionId && existing.termSessionId === termSessionId) {
      existing.lastSeenAt = new Date().toISOString();
      writeRegistry(registry);
      logger.info(COMPONENT, 'Re-registered session', { id });
      return existing;
    }
    throw new Error(`Session ID "${id}" is already registered`);
  }

  const now = new Date().toISOString();
  const session: SessionInfo = {
    id,
    ...(termSessionId && { termSessionId }),
    registeredAt: now,
    lastSeenAt: now,
  };

  registry.sessions.push(session);
  writeRegistry(registry);
  logger.info(COMPONENT, 'Registered session', { id });
  return session;
}

export function unregisterSession(id: string): boolean {
  const registry = readRegistry();
  const before = registry.sessions.length;
  registry.sessions = registry.sessions.filter((s) => s.id !== id);
  if (registry.sessions.length === before) {
    return false;
  }
  writeRegistry(registry);
  logger.info(COMPONENT, 'Unregistered session', { id });
  return true;
}

export function getActiveSessions(maxAgeMinutes: number = DEFAULT_MAX_AGE_MINUTES): SessionInfo[] {
  cleanStaleSessions(maxAgeMinutes);
  const registry = readRegistry();
  return registry.sessions;
}

export function isSessionActive(id: string): boolean {
  const registry = readRegistry();
  return registry.sessions.some((s) => s.id === id);
}

export function touchSession(id: string): boolean {
  const registry = readRegistry();
  const session = registry.sessions.find((s) => s.id === id);
  if (!session) return false;
  session.lastSeenAt = new Date().toISOString();
  writeRegistry(registry);
  return true;
}

export function cleanStaleSessions(maxAgeMinutes: number = DEFAULT_MAX_AGE_MINUTES): number {
  const registry = readRegistry();
  const cutoff = Date.now() - maxAgeMinutes * 60 * 1000;
  const before = registry.sessions.length;

  registry.sessions = registry.sessions.filter((s) => {
    return new Date(s.lastSeenAt).getTime() > cutoff;
  });

  const removed = before - registry.sessions.length;
  if (removed > 0) {
    writeRegistry(registry);
    logger.info(COMPONENT, 'Cleaned stale sessions', { removed });
  }
  return removed;
}
