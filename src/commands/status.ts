import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getFullStatus } from '../monitors/index.js';
import { formatFullStatus } from '../utils/format.js';
import { logger } from '../utils/logger.js';

export default async function statusCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const status = await getFullStatus();
    const blocks = formatFullStatus(status);
    await respond({ blocks, response_type: 'ephemeral' });
  } catch (error) {
    logger.error('commands/status', 'Failed to get system status', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve system status: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
