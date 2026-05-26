import { App, LogLevel } from '@slack/bolt';
import { config } from './config.js';
import { initSender } from './slack/sender.js';
import { startCliBridge } from './slack/cli-bridge.js';
import { logger } from './utils/logger.js';
import { routeMessage } from './agent/router.js';
import { cleanStaleSessions } from './agent/session-manager.js';

const SESSION_CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // 1 hour

async function main() {
  const app = new App({
    token: config.slack.botToken,
    appToken: config.slack.appToken,
    signingSecret: config.slack.signingSecret,
    socketMode: true,
    logLevel: LogLevel.WARN,
  });

  initSender(app.client, config.slack.channelId);

  // Handle @mentions
  app.event('app_mention', async ({ event }) => {
    const rawText = event.text.replace(/<@[A-Z0-9]+>\s*/g, '').trim();
    if (!rawText) return;

    routeMessage({
      text: rawText,
      userId: event.user ?? 'unknown',
      channel: event.channel,
      messageTs: event.ts,
      threadTs: event.thread_ts,
    }).catch((err) => {
      logger.error('app', 'Error routing mention', { error: String(err) });
    });
  });

  // Handle direct messages
  app.event('message', async ({ event }) => {
    if (event.channel_type !== 'im') return;
    if ('bot_id' in event || ('subtype' in event && event.subtype !== undefined)) return;

    const rawText = 'text' in event ? (event.text || '') : '';
    if (!rawText.trim()) return;

    const userId = 'user' in event ? (event.user as string) : 'unknown';

    routeMessage({
      text: rawText,
      userId,
      channel: event.channel,
      messageTs: event.ts,
      threadTs: 'thread_ts' in event ? (event.thread_ts as string | undefined) : undefined,
    }).catch((err) => {
      logger.error('app', 'Error routing DM', { error: String(err) });
    });
  });

  await app.start();
  logger.info('app', 'Slack bot connected via Socket Mode');

  const bridgeServer = startCliBridge(config.cliBridgePort);
  logger.info('app', `CLI bridge listening on 127.0.0.1:${config.cliBridgePort}`);

  // Periodic stale session cleanup
  const cleanupTimer = setInterval(() => {
    try {
      cleanStaleSessions();
    } catch (err) {
      logger.error('app', 'Session cleanup error', { error: String(err) });
    }
  }, SESSION_CLEANUP_INTERVAL_MS);

  logger.info('app', `Agent ready (working dir: ${config.agent.workingDir})`);

  const shutdown = async () => {
    logger.info('app', 'Shutting down...');
    clearInterval(cleanupTimer);
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
