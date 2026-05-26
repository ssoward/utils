import 'dotenv/config';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
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
  cliBridgePort: optionalInt('CLI_BRIDGE_PORT', 3848),
  maxQueueMessages: optionalInt('MAX_QUEUE_MESSAGES', 200),
  agent: {
    workingDir: process.env.AGENT_WORKING_DIR || process.cwd(),
    maxTurns: optionalInt('AGENT_MAX_TURNS', 25),
    timeoutMs: optionalInt('AGENT_TIMEOUT_MS', 300000),
    allowedTools: process.env.AGENT_ALLOWED_TOOLS || 'Bash,Read,Write,Edit,Glob,Grep',
    model: process.env.AGENT_MODEL || '',
    sessionTtlHours: optionalInt('AGENT_SESSION_TTL_HOURS', 24),
  },
} as const;
