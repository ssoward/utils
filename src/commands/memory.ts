import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getMemory } from '../monitors/system.js';
import { formatMemory } from '../utils/format.js';
import { logger } from '../utils/logger.js';

export default async function memoryCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const memory = await getMemory();
    const blocks = formatMemory(memory);
    await respond({ blocks, response_type: 'ephemeral' });
  } catch (error) {
    logger.error('commands/memory', 'Failed to get memory info', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve memory info: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
