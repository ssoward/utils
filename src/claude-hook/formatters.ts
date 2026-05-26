import type { KnownBlock } from '@slack/types';
import type { ClaudeHookEvent } from '../types.js';

type Block = KnownBlock;

interface EventTemplate {
  emoji: string;
  title: string;
  detail: (event: ClaudeHookEvent) => string;
}

const eventTemplates: Record<string, EventTemplate> = {
  session_start: {
    emoji: ':rocket:',
    title: 'Claude Code Session Started',
    detail: (e) => `*Session ID:* ${e.sessionId ?? 'unknown'}`,
  },
  session_end: {
    emoji: ':checkered_flag:',
    title: 'Claude Code Session Ended',
    detail: (e) => `*Session ID:* ${e.sessionId ?? 'unknown'}`,
  },
  tool_use: {
    emoji: ':wrench:',
    title: 'Tool Used',
    detail: (e) => `*Tool:* ${String(e.tool ?? 'unknown')}`,
  },
  error: {
    emoji: ':x:',
    title: 'Claude Code Error',
    detail: (e) => `*Error:* ${e.message ?? 'No error message provided'}`,
  },
  notification: {
    emoji: ':bell:',
    title: 'Claude Code Notification',
    detail: (e) => `*Message:* ${e.message ?? 'No message provided'}`,
  },
};

function buildHeaderBlock(text: string): Block {
  return {
    type: 'header',
    text: {
      type: 'plain_text',
      text,
      emoji: true,
    },
  } as Block;
}

function buildSectionBlock(markdown: string): Block {
  return {
    type: 'section',
    text: {
      type: 'mrkdwn',
      text: markdown,
    },
  } as Block;
}

function buildMetaLine(event: ClaudeHookEvent): string {
  const parts: string[] = [];
  if (event.timestamp) {
    parts.push(`*Timestamp:* ${event.timestamp}`);
  }
  if (event.sessionId) {
    parts.push(`*Session:* ${event.sessionId}`);
  }
  return parts.join('  |  ');
}

export function formatHookEvent(event: ClaudeHookEvent): Block[] {
  const template = eventTemplates[event.type];

  if (template) {
    const headerText = `${template.emoji} ${template.title}`;
    const detail = template.detail(event);
    const meta = buildMetaLine(event);
    const sectionText = meta ? `${detail}\n${meta}` : detail;

    return [buildHeaderBlock(headerText), buildSectionBlock(sectionText)];
  }

  // Default: unknown event type
  const headerText = ':information_source: Claude Code Event';
  const detail = `*Type:* ${event.type}\n*Payload:*\n\`\`\`${JSON.stringify(event, null, 2)}\`\`\``;
  const meta = buildMetaLine(event);
  const sectionText = meta ? `${detail}\n${meta}` : detail;

  return [buildHeaderBlock(headerText), buildSectionBlock(sectionText)];
}
