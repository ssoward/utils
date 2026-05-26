import 'dotenv/config';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function optionalEnv(name: string, fallback: string): string {
  return process.env[name] || fallback;
}

function optionalInt(name: string, fallback: number): number {
  const val = process.env[name];
  return val ? parseInt(val, 10) : fallback;
}

export const config = {
  slack: {
    botToken: requireEnv('SLACK_BOT_TOKEN'),
    appToken: requireEnv('SLACK_APP_TOKEN'),
    signingSecret: requireEnv('SLACK_SIGNING_SECRET'),
    channelId: process.env.SLACK_CHANNEL_ID || '',
  },
  allowedUserId: process.env.ALLOWED_USER_ID || '',
  hookPort: optionalInt('HOOK_PORT', 3847),
  cliBridgePort: optionalInt('CLI_BRIDGE_PORT', 3848),
  schedulerIntervalMinutes: optionalInt('SCHEDULER_INTERVAL_MINUTES', 30),
  maxQueueMessages: optionalInt('MAX_QUEUE_MESSAGES', 200),
  thresholds: {
    batteryLow: optionalInt('BATTERY_LOW_THRESHOLD', 20),
    diskUsageHigh: optionalInt('DISK_USAGE_HIGH_THRESHOLD', 90),
  },
} as const;
