import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getUptime } from '../monitors/system.js';
import { logger } from '../utils/logger.js';

export default async function uptimeCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const uptime = await getUptime();
    await respond({
      text: `:clock1: *System Uptime:* ${uptime}`,
      response_type: 'ephemeral',
    });
  } catch (error) {
    logger.error('commands/uptime', 'Failed to get uptime', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve uptime: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
