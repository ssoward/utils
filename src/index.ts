import { App, LogLevel } from '@slack/bolt';
import { config } from './config.js';
import { initSender } from './slack/sender.js';
import { startCliBridge } from './slack/cli-bridge.js';
import { enqueueMessage } from './message-queue/index.js';
import { getActiveSessions, isSessionActive } from './session-registry/index.js';
import { pushToClients } from './slack/ws-bridge.js';
import { logger } from './utils/logger.js';
import type { SlackIncomingMessage } from './types.js';

const SESSION_PREFIX_RE = /^(cc-[0-9a-f]{4}):\s*/i;
const HELP_RE = /^-help$/i;
const LIST_CC_RE = /^list-cc$/i;

function buildSessionList(): string {
  const sessions = getActiveSessions();
  if (sessions.length === 0) {
    return '*Active Claude Code Sessions*\n\n_No active sessions._';
  }

  const lines = sessions.map((s) => {
    const ws = s.wsConnected ? ':large_green_circle:' : ':white_circle:';
    const age = formatAge(s.registeredAt);
    const lastSeen = formatAge(s.lastSeenAt);
    return `${ws} \`${s.id}\` — registered ${age} ago, last seen ${lastSeen} ago`;
  });

  return [
    `*Active Claude Code Sessions (${sessions.length})*`,
    '',
    ...lines,
    '',
    ':large_green_circle: = WebSocket connected  :white_circle: = polling only',
  ].join('\n');
}

function formatAge(isoDate: string): string {
  const ms = Date.now() - new Date(isoDate).getTime();
  const secs = Math.floor(ms / 1000);
  if (secs < 60) return `${secs}s`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  const remainMins = mins % 60;
  return `${hours}h ${remainMins}m`;
}

function buildHelpText(): string {
  const activeSessions = getActiveSessions();
  const sessionList = activeSessions.length > 0
    ? activeSessions.map((s) => `\`${s.id}\``).join(', ')
    : '_none_';

  return [
    '*Slack Bot — Help*',
    '',
    '*Messaging:*',
    '• `@bot <message>` — Queue a task for any available session',
    '• `@bot cc-XXXX: <message>` — Route to a specific session',
    '• `@bot list-cc` — List all active Claude Code sessions',
    '• `@bot -help` — Show this help message',
    '',
    '*Sessions:*',
    `Active: ${sessionList}`,
  ].join('\n');
}

function parseSessionTarget(text: string): { targetSession: string | undefined; cleanText: string } {
  const match = text.match(SESSION_PREFIX_RE);
  if (match && isSessionActive(match[1].toLowerCase())) {
    return { targetSession: match[1].toLowerCase(), cleanText: text.slice(match[0].length) };
  }
  return { targetSession: undefined, cleanText: text };
}

async function main() {
  const app = new App({
    token: config.slack.botToken,
    appToken: config.slack.appToken,
    signingSecret: config.slack.signingSecret,
    socketMode: true,
    logLevel: LogLevel.WARN,
  });

  initSender(app.client, config.slack.channelId);

  app.event('app_mention', async ({ event, say }) => {
    const rawText = event.text.replace(/<@[A-Z0-9]+>\s*/g, '').trim();
    if (!rawText) {
      await say(`Hi <@${event.user}>! Send me a message and I'll queue it for processing.`);
      return;
    }

    const textAfterSession = rawText.replace(SESSION_PREFIX_RE, '').trim();
    if (HELP_RE.test(textAfterSession)) {
      await say(buildHelpText());
      return;
    }
    if (LIST_CC_RE.test(textAfterSession)) {
      await say(buildSessionList());
      return;
    }

    const { targetSession, cleanText } = parseSessionTarget(rawText);
    const id = enqueueMessage('mention', cleanText, event.user ?? 'unknown', event.channel, event.ts, event.thread_ts, targetSession);

    const mentionMsg: SlackIncomingMessage = {
      id, source: 'mention', text: cleanText, userId: event.user ?? 'unknown',
      channel: event.channel, messageTs: event.ts, receivedAt: new Date().toISOString(), read: false,
      ...(event.thread_ts && { threadTs: event.thread_ts }),
      ...(targetSession && { targetSession }),
    };
    pushToClients(mentionMsg);

    const activeSessions = getActiveSessions();
    const sessionList = activeSessions.length > 0
      ? ` Active sessions: ${activeSessions.map((s) => `\`${s.id}\``).join(', ')}`
      : '';
    const targetNote = targetSession ? ` (routed to \`${targetSession}\`)` : '';
    await say(`Got it! Your message is queued (ref: \`${id}\`)${targetNote}.${sessionList}`);
  });

  app.event('message', async ({ event, say }) => {
    if (event.channel_type !== 'im') return;
    if ('bot_id' in event || ('subtype' in event && event.subtype !== undefined)) return;

    const rawText = 'text' in event ? (event.text || '') : '';
    if (!rawText.trim()) return;

    const dmTextAfterSession = rawText.replace(SESSION_PREFIX_RE, '').trim();
    if (HELP_RE.test(dmTextAfterSession)) {
      await say(buildHelpText());
      return;
    }
    if (LIST_CC_RE.test(dmTextAfterSession)) {
      await say(buildSessionList());
      return;
    }

    const { targetSession, cleanText } = parseSessionTarget(rawText);
    const userId = 'user' in event ? (event.user as string) : 'unknown';
    const id = enqueueMessage('dm', cleanText, userId, event.channel, event.ts, undefined, targetSession);

    const dmMsg: SlackIncomingMessage = {
      id, source: 'dm', text: cleanText, userId,
      channel: event.channel, messageTs: event.ts, receivedAt: new Date().toISOString(), read: false,
      ...(targetSession && { targetSession }),
    };
    pushToClients(dmMsg);

    const targetNote = targetSession ? ` (routed to \`${targetSession}\`)` : '';
    await say(`Message queued (ref: \`${id}\`)${targetNote}. I'll process it shortly.`);
  });

  await app.start();
  logger.info('app', 'Slack bot connected via Socket Mode');

  const bridgeServer = startCliBridge(config.cliBridgePort);
  logger.info('app', `CLI bridge listening on 127.0.0.1:${config.cliBridgePort}`);

  logger.info('app', 'Agent ready');

  const shutdown = async () => {
    logger.info('app', 'Shutting down...');
    bridgeServer.close();
    await app.stop();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  logger.error('app', 'Failed to start', { error: String(err) });
  process.exit(1);
});
