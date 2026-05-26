import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getCpu } from '../monitors/system.js';
import { formatCpu } from '../utils/format.js';
import { logger } from '../utils/logger.js';

export default async function cpuCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const cpu = await getCpu();
    const blocks = formatCpu(cpu);
    await respond({ blocks, response_type: 'ephemeral' });
  } catch (error) {
    logger.error('commands/cpu', 'Failed to get CPU info', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve CPU info: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
