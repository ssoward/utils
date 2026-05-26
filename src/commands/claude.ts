import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { logger } from '../utils/logger.js';

export default async function claudeCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    await respond({
      blocks: [
        {
          type: 'header',
          text: { type: 'plain_text', text: 'Claude Code Hook Integration', emoji: true },
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text:
              ':robot_face: *Claude Code Hook* sends real-time notifications to this Slack bot ' +
              'when Claude Code sessions produce events.\n\n' +
              `*Hook Endpoint:* \`http://localhost:3847\`\n\n` +
              '*How to configure:*\n' +
              '1. Add a hook in your Claude Code settings pointing to the endpoint above\n' +
              '2. Select which events to forward (e.g., task start, task complete, errors)\n' +
              '3. The bot will relay those events to your configured Slack channel\n\n' +
              '*Supported events:* session start, session end, task updates, errors, and custom notifications',
          },
        },
      ],
      response_type: 'ephemeral',
    });
  } catch (error) {
    logger.error('commands/claude', 'Failed to show Claude hook info', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to display Claude hook info: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
