import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { logger } from '../utils/logger.js';

export default async function notifyCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const text = command.text.trim();

    if (!text) {
      await respond({
        text: ':warning: Please provide a message. Usage: `/notify <message>`',
        response_type: 'ephemeral',
      });
      return;
    }

    logger.info('commands/notify', 'Notification received', {
      user: command.user_id,
      message: text,
    });

    await respond({
      blocks: [
        {
          type: 'header',
          text: { type: 'plain_text', text: 'Notification Received', emoji: true },
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `:bell: *Your notification has been received:*\n\n> ${text}`,
          },
        },
      ],
      response_type: 'ephemeral',
    });
  } catch (error) {
    logger.error('commands/notify', 'Failed to process notification', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to process notification: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
