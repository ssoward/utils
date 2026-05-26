import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { exec } from '../utils/exec.js';
import { logger } from '../utils/logger.js';

const ALLOWED_COMMANDS = new Map<string, string>([
  ['git-status', 'git -C /Users/ssoward status --short'],
  ['top-cpu', 'ps aux -r | head -6'],
  ['top-mem', 'ps aux -m | head -6'],
  ['who', 'who'],
  ['df', 'df -h'],
  ['brew-outdated', 'brew outdated'],
  ['node-version', 'node --version'],
]);

function buildHelpBlocks() {
  const commandList = Array.from(ALLOWED_COMMANDS.keys())
    .map((key) => `\`${key}\``)
    .join(', ');

  return [
    {
      type: 'header' as const,
      text: { type: 'plain_text' as const, text: 'Available Commands', emoji: true },
    },
    {
      type: 'section' as const,
      text: {
        type: 'mrkdwn' as const,
        text:
          `Usage: \`/run <command-name>\`\n\n` +
          `*Available commands:* ${commandList}\n\n` +
          Array.from(ALLOWED_COMMANDS.entries())
            .map(([key, cmd]) => `- \`${key}\` - \`${cmd}\``)
            .join('\n'),
      },
    },
  ];
}

export default async function runCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  const requested = command.text.trim();

  if (!requested || !ALLOWED_COMMANDS.has(requested)) {
    await respond({ blocks: buildHelpBlocks(), response_type: 'ephemeral' });
    return;
  }

  const shellCommand = ALLOWED_COMMANDS.get(requested)!;

  try {
    logger.info('commands/run', `Executing allowed command: ${requested}`, {
      user: command.user_id,
      command: shellCommand,
    });

    const output = await exec(shellCommand);

    await respond({
      blocks: [
        {
          type: 'header',
          text: { type: 'plain_text', text: `Run: ${requested}`, emoji: true },
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `\`\`\`\n${output || '(no output)'}\n\`\`\``,
          },
        },
      ],
      response_type: 'ephemeral',
    });
  } catch (error) {
    logger.error('commands/run', `Command failed: ${requested}`, {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Command \`${requested}\` failed: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
