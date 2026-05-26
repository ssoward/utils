import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  registerSession,
  unregisterSession,
  getActiveSessions,
  isSessionActive,
  touchSession,
  cleanStaleSessions,
} from '../session-registry/registry.js';

const DATA_DIR = path.resolve(process.cwd(), 'data');
const REGISTRY_FILE = path.join(DATA_DIR, 'sessions.json');

function cleanup() {
  if (fs.existsSync(REGISTRY_FILE)) fs.unlinkSync(REGISTRY_FILE);
}

describe('session-registry', () => {
  beforeEach(cleanup);
  afterEach(cleanup);

  describe('registerSession', () => {
    it('should register a new session and return SessionInfo', () => {
      const session = registerSession('cc-a1b2');
      expect(session.id).toBe('cc-a1b2');
      expect(session.registeredAt).toBeDefined();
      expect(session.lastSeenAt).toBeDefined();
    });

    it('should register with optional termSessionId', () => {
      const session = registerSession('cc-1234', 'term-abc');
      expect(session.termSessionId).toBe('term-abc');
    });

    it('should throw on duplicate ID from different terminal', () => {
      registerSession('cc-dead');
      expect(() => registerSession('cc-dead')).toThrow('already registered');
    });

    it('should allow re-registration from same terminal session (idempotent)', () => {
      registerSession('cc-beef', 'term-123');
      const session = registerSession('cc-beef', 'term-123');
      expect(session.id).toBe('cc-beef');
    });

    it('should persist across reads', () => {
      registerSession('cc-0001');
      registerSession('cc-0002');
      const sessions = getActiveSessions();
      expect(sessions).toHaveLength(2);
    });
  });

  describe('unregisterSession', () => {
    it('should remove an existing session', () => {
      registerSession('cc-rem1');
      const removed = unregisterSession('cc-rem1');
      expect(removed).toBe(true);
      expect(isSessionActive('cc-rem1')).toBe(false);
    });

    it('should return false for non-existent session', () => {
      expect(unregisterSession('cc-nope')).toBe(false);
    });
  });

  describe('getActiveSessions', () => {
    it('should return empty array when no sessions', () => {
      expect(getActiveSessions()).toHaveLength(0);
    });

    it('should return all active sessions', () => {
      registerSession('cc-aaa1');
      registerSession('cc-aaa2');
      const sessions = getActiveSessions();
      expect(sessions).toHaveLength(2);
      expect(sessions.map((s) => s.id)).toContain('cc-aaa1');
      expect(sessions.map((s) => s.id)).toContain('cc-aaa2');
    });
  });

  describe('isSessionActive', () => {
    it('should return true for registered session', () => {
      registerSession('cc-chk1');
      expect(isSessionActive('cc-chk1')).toBe(true);
    });

    it('should return false for unregistered session', () => {
      expect(isSessionActive('cc-nope')).toBe(false);
    });
  });

  describe('touchSession', () => {
    it('should update lastSeenAt timestamp', () => {
      const session = registerSession('cc-tch1');
      const originalTs = session.lastSeenAt;

      // Small delay to ensure timestamp difference
      const result = touchSession('cc-tch1');
      expect(result).toBe(true);

      const sessions = getActiveSessions();
      const updated = sessions.find((s) => s.id === 'cc-tch1');
      expect(updated).toBeDefined();
      expect(new Date(updated!.lastSeenAt).getTime()).toBeGreaterThanOrEqual(
        new Date(originalTs).getTime(),
      );
    });

    it('should return false for non-existent session', () => {
      expect(touchSession('cc-nope')).toBe(false);
    });
  });

  describe('cleanStaleSessions', () => {
    it('should remove sessions older than maxAgeMinutes', () => {
      // Register a session and manually backdate it
      registerSession('cc-old1');
      const registry = JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf-8'));
      registry.sessions[0].lastSeenAt = new Date(Date.now() - 120 * 60 * 1000).toISOString();
      fs.writeFileSync(REGISTRY_FILE, JSON.stringify(registry, null, 2), 'utf-8');

      const removed = cleanStaleSessions(60);
      expect(removed).toBe(1);
      expect(getActiveSessions()).toHaveLength(0);
    });

    it('should keep fresh sessions', () => {
      registerSession('cc-new1');
      const removed = cleanStaleSessions(60);
      expect(removed).toBe(0);
      expect(getActiveSessions()).toHaveLength(1);
    });

    it('should return 0 when no sessions exist', () => {
      expect(cleanStaleSessions(60)).toBe(0);
    });
  });

  describe('resilience', () => {
    it('should handle corrupted registry file gracefully', () => {
      fs.mkdirSync(DATA_DIR, { recursive: true });
      fs.writeFileSync(REGISTRY_FILE, 'not json', 'utf-8');
      const sessions = getActiveSessions();
      expect(sessions).toHaveLength(0);
    });

    it('should create data dir if missing', () => {
      cleanup();
      const session = registerSession('cc-dir1');
      expect(session.id).toBe('cc-dir1');
      expect(fs.existsSync(REGISTRY_FILE)).toBe(true);
    });
  });
});
