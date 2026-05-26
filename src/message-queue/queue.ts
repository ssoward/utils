import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { logger } from '../utils/logger.js';
import { config } from '../config.js';
import type { SlackIncomingMessage, MessageQueueFile } from '../types.js';

const COMPONENT = 'message-queue';
const DATA_DIR = path.resolve(process.cwd(), 'data');
const QUEUE_FILE = path.join(DATA_DIR, 'messages.json');

function ensureDataDir(): void {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function readQueue(): MessageQueueFile {
  ensureDataDir();
  if (!fs.existsSync(QUEUE_FILE)) {
    return { version: 1, lastUpdated: new Date().toISOString(), messages: [] };
  }
  try {
    const raw = fs.readFileSync(QUEUE_FILE, 'utf-8');
    return JSON.parse(raw) as MessageQueueFile;
  } catch (err) {
    logger.error(COMPONENT, 'Failed to read queue file, resetting', { error: String(err) });
    return { version: 1, lastUpdated: new Date().toISOString(), messages: [] };
  }
}

function writeQueue(queue: MessageQueueFile): void {
  ensureDataDir();
  queue.lastUpdated = new Date().toISOString();
  fs.writeFileSync(QUEUE_FILE, JSON.stringify(queue, null, 2), 'utf-8');
}

export function enqueueMessage(
  source: 'dm' | 'mention',
  text: string,
  userId: string,
  channel: string,
  messageTs: string,
  threadTs?: string,
  targetSession?: string,
): string {
  const queue = readQueue();
  const id = crypto.randomBytes(4).toString('hex');

  const msg: SlackIncomingMessage = {
    id,
    source,
    text,
    userId,
    channel,
    messageTs,
    ...(threadTs && { threadTs }),
    ...(targetSession && { targetSession }),
    receivedAt: new Date().toISOString(),
    read: false,
  };

  queue.messages.push(msg);

  // Cap queue size
  if (queue.messages.length > config.maxQueueMessages) {
    queue.messages = queue.messages.slice(-config.maxQueueMessages);
  }

  writeQueue(queue);
  logger.info(COMPONENT, 'Enqueued message', { id, source, userId, channel });
  return id;
}

export function getUnreadMessages(): SlackIncomingMessage[] {
  const queue = readQueue();
  return queue.messages.filter((m) => !m.read);
}

export function getUnreadMessagesForSession(sessionId: string): SlackIncomingMessage[] {
  const queue = readQueue();
  return queue.messages.filter((m) => {
    if (m.read) return false;
    // Message is visible if it has no targetSession (broadcast) or targets this session
    return !m.targetSession || m.targetSession === sessionId;
  });
}

export function getAllMessages(limit?: number): SlackIncomingMessage[] {
  const queue = readQueue();
  if (limit && limit > 0) {
    return queue.messages.slice(-limit);
  }
  return queue.messages;
}

export function markAsRead(ids?: string[]): number {
  const queue = readQueue();
  let count = 0;

  for (const msg of queue.messages) {
    if (msg.read) continue;
    if (!ids || ids.includes(msg.id)) {
      msg.read = true;
      count++;
    }
  }

  writeQueue(queue);
  logger.info(COMPONENT, 'Marked messages as read', { count });
  return count;
}

export function clearQueue(): number {
  const queue = readQueue();
  const count = queue.messages.length;
  queue.messages = [];
  writeQueue(queue);
  logger.info(COMPONENT, 'Cleared queue', { count });
  return count;
}
