import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  enqueueMessage,
  getUnreadMessages,
  getUnreadMessagesForSession,
  getAllMessages,
  markAsRead,
  clearQueue,
} from '../message-queue/queue.js';

const DATA_DIR = path.resolve(process.cwd(), 'data');
const QUEUE_FILE = path.join(DATA_DIR, 'messages.json');

function cleanup() {
  if (fs.existsSync(QUEUE_FILE)) fs.unlinkSync(QUEUE_FILE);
}

describe('message-queue', () => {
  beforeEach(cleanup);
  afterEach(cleanup);

  describe('enqueueMessage', () => {
    it('should enqueue a DM and return an id', () => {
      const id = enqueueMessage('dm', 'hello', 'U123', 'D456', '1234567890.000');
      expect(id).toBeDefined();
      expect(typeof id).toBe('string');
      expect(id.length).toBe(8); // 4 random bytes = 8 hex chars
    });

    it('should enqueue a mention with threadTs', () => {
      const id = enqueueMessage('mention', 'hey bot', 'U123', 'C456', '111.222', '111.111');
      const msgs = getAllMessages();
      expect(msgs).toHaveLength(1);
      expect(msgs[0].id).toBe(id);
      expect(msgs[0].source).toBe('mention');
      expect(msgs[0].text).toBe('hey bot');
      expect(msgs[0].threadTs).toBe('111.111');
      expect(msgs[0].read).toBe(false);
    });

    it('should persist messages across reads', () => {
      enqueueMessage('dm', 'msg1', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'msg2', 'U2', 'D2', '2.0');
      const msgs = getAllMessages();
      expect(msgs).toHaveLength(2);
      expect(msgs[0].text).toBe('msg1');
      expect(msgs[1].text).toBe('msg2');
    });

    it('should cap queue at maxQueueMessages', () => {
      // config.maxQueueMessages defaults to 200; enqueue 205
      for (let i = 0; i < 205; i++) {
        enqueueMessage('dm', `msg-${i}`, 'U1', 'D1', `${i}.0`);
      }
      const msgs = getAllMessages();
      expect(msgs.length).toBeLessThanOrEqual(200);
      // The oldest messages should have been trimmed
      expect(msgs[0].text).toBe('msg-5');
    });
  });

  describe('getUnreadMessages', () => {
    it('should return only unread messages', () => {
      enqueueMessage('dm', 'read-me', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'also-read', 'U1', 'D1', '2.0');
      markAsRead(); // mark all
      enqueueMessage('dm', 'new-one', 'U1', 'D1', '3.0');

      const unread = getUnreadMessages();
      expect(unread).toHaveLength(1);
      expect(unread[0].text).toBe('new-one');
    });

    it('should return empty array when no unread', () => {
      enqueueMessage('dm', 'hi', 'U1', 'D1', '1.0');
      markAsRead();
      expect(getUnreadMessages()).toHaveLength(0);
    });
  });

  describe('getAllMessages', () => {
    it('should return all messages regardless of read status', () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');
      markAsRead();
      enqueueMessage('dm', 'c', 'U1', 'D1', '3.0');

      expect(getAllMessages()).toHaveLength(3);
    });

    it('should respect limit parameter', () => {
      for (let i = 0; i < 10; i++) {
        enqueueMessage('dm', `msg-${i}`, 'U1', 'D1', `${i}.0`);
      }
      const msgs = getAllMessages(3);
      expect(msgs).toHaveLength(3);
      // Should return the last 3
      expect(msgs[0].text).toBe('msg-7');
      expect(msgs[2].text).toBe('msg-9');
    });
  });

  describe('markAsRead', () => {
    it('should mark all messages as read when no ids specified', () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');
      const count = markAsRead();
      expect(count).toBe(2);
      expect(getUnreadMessages()).toHaveLength(0);
    });

    it('should mark only specified ids as read', () => {
      const id1 = enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');
      const count = markAsRead([id1]);
      expect(count).toBe(1);
      const unread = getUnreadMessages();
      expect(unread).toHaveLength(1);
      expect(unread[0].text).toBe('b');
    });

    it('should return 0 when no unread messages', () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      markAsRead();
      expect(markAsRead()).toBe(0);
    });
  });

  describe('clearQueue', () => {
    it('should remove all messages and return count', () => {
      enqueueMessage('dm', 'a', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'b', 'U1', 'D1', '2.0');
      const count = clearQueue();
      expect(count).toBe(2);
      expect(getAllMessages()).toHaveLength(0);
    });

    it('should return 0 on empty queue', () => {
      expect(clearQueue()).toBe(0);
    });
  });

  describe('enqueueMessage with targetSession', () => {
    it('should store targetSession when provided', () => {
      enqueueMessage('dm', 'for session', 'U1', 'D1', '1.0', undefined, 'cc-a1b2');
      const msgs = getAllMessages();
      expect(msgs).toHaveLength(1);
      expect(msgs[0].targetSession).toBe('cc-a1b2');
    });

    it('should not include targetSession when not provided', () => {
      enqueueMessage('dm', 'broadcast', 'U1', 'D1', '1.0');
      const msgs = getAllMessages();
      expect(msgs).toHaveLength(1);
      expect(msgs[0].targetSession).toBeUndefined();
    });
  });

  describe('getUnreadMessagesForSession', () => {
    it('should return unaddressed messages and messages targeted to the session', () => {
      enqueueMessage('dm', 'broadcast', 'U1', 'D1', '1.0');
      enqueueMessage('dm', 'for-a1b2', 'U1', 'D1', '2.0', undefined, 'cc-a1b2');
      enqueueMessage('dm', 'for-dead', 'U1', 'D1', '3.0', undefined, 'cc-dead');

      const msgs = getUnreadMessagesForSession('cc-a1b2');
      expect(msgs).toHaveLength(2);
      expect(msgs.map((m) => m.text)).toContain('broadcast');
      expect(msgs.map((m) => m.text)).toContain('for-a1b2');
      expect(msgs.map((m) => m.text)).not.toContain('for-dead');
    });

    it('should not return read messages', () => {
      enqueueMessage('dm', 'read-me', 'U1', 'D1', '1.0');
      markAsRead();
      enqueueMessage('dm', 'new', 'U1', 'D1', '2.0');

      const msgs = getUnreadMessagesForSession('cc-a1b2');
      expect(msgs).toHaveLength(1);
      expect(msgs[0].text).toBe('new');
    });

    it('should return empty array when all messages target other sessions', () => {
      enqueueMessage('dm', 'not-mine', 'U1', 'D1', '1.0', undefined, 'cc-dead');
      const msgs = getUnreadMessagesForSession('cc-a1b2');
      expect(msgs).toHaveLength(0);
    });
  });

  describe('resilience', () => {
    it('should handle corrupted queue file gracefully', () => {
      fs.mkdirSync(DATA_DIR, { recursive: true });
      fs.writeFileSync(QUEUE_FILE, 'not json at all', 'utf-8');
      // Should not throw — resets to empty
      const msgs = getAllMessages();
      expect(msgs).toHaveLength(0);
    });

    it('should create data dir if missing', () => {
      if (fs.existsSync(DATA_DIR)) {
        // Remove the queue file but leave dir
        cleanup();
      }
      const id = enqueueMessage('dm', 'test', 'U1', 'D1', '1.0');
      expect(id).toBeDefined();
      expect(fs.existsSync(QUEUE_FILE)).toBe(true);
    });
  });
});
