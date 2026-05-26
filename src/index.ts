import { App, LogLevel } from '@slack/bolt';
import { config } from './config.js';
import { registerCommands } from './commands/index.js';
import { initSender } from './notifier/slack-sender.js';
import { startHookReceiver } from './claude-hook/index.js';
import { startCliBridge } from './notifier/cli-bridge.js';
import { startScheduler } from './scheduler/scheduler.js';
import { enqueueMessage } from './message-queue/index.js';
import { getActiveSessions, isSessionActive } from './session-registry/index.js';
import { pushToClients } from './notifier/ws-bridge.js';
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
    '*Working Directory Override:*',
    '• `@bot cc-XXXX: pwd=/absolute/path <task>` — Run in a specific directory',
    '• `@bot cc-XXXX: pwd=~/relative/path <task>` — Supports `~` expansion',
    '• Without `pwd=`, tasks run in the session\'s default working directory',
    '',
    '*Slash Commands:*',
    '• `/status` — Full system status (CPU, memory, disk, battery)',
    '• `/cpu` `/memory` `/disk` `/battery` `/uptime` — Individual metrics',
    '• `/notify` — Send a notification',
    '• `/run` — Execute a shell command',
    '• `/claude` — Claude Code integration info',
    '',
    '*Sessions:*',
    `Active: ${sessionList}`,
    '',
    '*How It Works:*',
    'Messages routed to a session are automatically executed by `claude -p` and the result is posted in-thread.',
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

  // Initialize the Slack sender with the app's web client
  initSender(app.client, config.slack.channelId);

  // Register all slash commands
  registerCommands(app);

  // Handle app_mention events — enqueue for Claude Code
  app.event('app_mention', async ({ event, say }) => {
    // Strip the @mention prefix to get the actual message text
    const rawText = event.text.replace(/<@[A-Z0-9]+>\s*/g, '').trim();
    if (!rawText) {
      await say(`Hi <@${event.user}>! Send me a message and I'll queue it for processing.`);
      return;
    }

    // Handle built-in commands before enqueueing
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

    // Push to WebSocket-connected channel servers in real-time
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

  // Handle direct messages — enqueue for Claude Code
  app.event('message', async ({ event, say }) => {
    if (event.channel_type !== 'im') return;
    // Filter out bot messages and message subtypes (edits, deletes, etc.)
    if ('bot_id' in event || ('subtype' in event && event.subtype !== undefined)) return;

    const rawText = 'text' in event ? (event.text || '') : '';
    if (!rawText.trim()) return;

    // Handle built-in commands in DMs
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

    // Push to WebSocket-connected channel servers in real-time
    const dmMsg: SlackIncomingMessage = {
      id, source: 'dm', text: cleanText, userId,
      channel: event.channel, messageTs: event.ts, receivedAt: new Date().toISOString(), read: false,
      ...(targetSession && { targetSession }),
    };
    pushToClients(dmMsg);

    const targetNote = targetSession ? ` (routed to \`${targetSession}\`)` : '';
    await say(`Message queued (ref: \`${id}\`)${targetNote}. I'll process it shortly.`);
  });

  // Start the Bolt app (Socket Mode)
  await app.start();
  logger.info('app', 'Slack bot connected via Socket Mode');

  // Start the Claude Code hook receiver
  const hookServer = startHookReceiver(config.hookPort);
  logger.info('app', `Hook receiver listening on 127.0.0.1:${config.hookPort}`);

  // Start the CLI bridge
  const bridgeServer = startCliBridge(config.cliBridgePort);
  logger.info('app', `CLI bridge listening on 127.0.0.1:${config.cliBridgePort}`);

  // Start the scheduler for periodic health checks
  if (config.slack.channelId) {
    startScheduler(config.schedulerIntervalMinutes);
    logger.info('app', `Scheduler started with ${config.schedulerIntervalMinutes}min interval`);
  } else {
    logger.warn('app', 'SLACK_CHANNEL_ID not set — scheduler alerts disabled. Set it in .env to enable threshold alerts.');
  }

  logger.info('app', 'All systems operational');

  // Graceful shutdown
  const shutdown = async () => {
    logger.info('app', 'Shutting down...');
    hookServer.close();
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
