import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getDisk } from '../monitors/disk.js';
import { formatDisk } from '../utils/format.js';
import { logger } from '../utils/logger.js';

export default async function diskCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const disk = await getDisk();
    const blocks = formatDisk(disk);
    await respond({ blocks, response_type: 'ephemeral' });
  } catch (error) {
    logger.error('commands/disk', 'Failed to get disk info', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve disk info: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
