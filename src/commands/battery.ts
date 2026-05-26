import type { SlackCommandMiddlewareArgs } from '@slack/bolt';
import { getBattery } from '../monitors/battery.js';
import { formatBattery } from '../utils/format.js';
import { logger } from '../utils/logger.js';

export default async function batteryCommand({
  command,
  ack,
  respond,
}: SlackCommandMiddlewareArgs) {
  await ack();

  try {
    const battery = await getBattery();
    const blocks = formatBattery(battery);
    await respond({ blocks, response_type: 'ephemeral' });
  } catch (error) {
    logger.error('commands/battery', 'Failed to get battery info', {
      error: String(error),
      user: command.user_id,
    });
    await respond({
      text: `:x: Failed to retrieve battery info: ${error instanceof Error ? error.message : String(error)}`,
      response_type: 'ephemeral',
    });
  }
}
