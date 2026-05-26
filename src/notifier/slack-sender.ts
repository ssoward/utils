import type { WebClient } from '@slack/web-api';
import type { KnownBlock } from '@slack/types';
import { logger } from '../utils/logger.js';

let slackClient: WebClient;
let defaultChannel: string;

export function initSender(client: WebClient, channelId: string): void {
  slackClient = client;
  defaultChannel = channelId;
}

export async function sendMessage(
  text: string,
  blocks?: KnownBlock[],
  channel?: string,
): Promise<void> {
  const target = channel || defaultChannel;

  if (!target) {
    logger.warn('slack-sender', 'No channel configured; message not sent', { text });
    return;
  }

  try {
    await slackClient.chat.postMessage({
      channel: target,
      text,
      ...(blocks && { blocks }),
    });
  } catch (error) {
    logger.error('slack-sender', 'Failed to send Slack message', {
      error: error instanceof Error ? error.message : String(error),
      channel: target,
    });
  }
}

export async function replyInThread(
  channel: string,
  text: string,
  threadTs?: string,
): Promise<void> {
  try {
    await slackClient.chat.postMessage({
      channel,
      text,
      ...(threadTs && { thread_ts: threadTs }),
    });
  } catch (error) {
    logger.error('slack-sender', 'Failed to reply in thread', {
      error: error instanceof Error ? error.message : String(error),
      channel,
      threadTs,
    });
    throw error;
  }
}

export async function sendBlocks(
  blocks: KnownBlock[],
  channel?: string,
): Promise<void> {
  // Extract fallback text from the first section block's text field
  let fallbackText = 'Notification';

  for (const block of blocks) {
    if (block.type === 'section' && 'text' in block && block.text) {
      fallbackText = block.text.text;
      break;
    }
    if (block.type === 'header' && 'text' in block && block.text) {
      fallbackText = block.text.text;
      break;
    }
  }

  await sendMessage(fallbackText, blocks, channel);
}
