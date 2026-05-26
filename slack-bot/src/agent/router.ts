import { logger } from '../utils/logger.js';
import { config } from '../config.js';
import { replyInThread } from '../slack/sender.js';
import { executeTask, getExecutorStatus, cancelCurrentTask } from './executor.js';
import {
  getOrCreateSession,
  getSession,
  addExchange,
  buildContextPrompt,
  listSessions as listAgentSessions,
} from './session-manager.js';
import type { TaskRequest } from '../types.js';

const COMPONENT = 'router';

type BuiltInCommand = 'help' | 'status' | 'cancel' | 'config' | 'history';

export function parseBuiltInCommand(text: string): BuiltInCommand | null {
  const trimmed = text.trim().toLowerCase();
  if (trimmed === 'help') return 'help';
  if (trimmed === 'status') return 'status';
  if (trimmed === 'cancel') return 'cancel';
  if (trimmed.startsWith('config workspace')) return 'config';
  if (trimmed === 'history') return 'history';
  return null;
}

export function parseWorkingDir(text: string): { workingDir: string | null; cleanText: string } {
  const match = text.match(/^pwd=(\S+)\s*/);
  if (match) {
    let dir = match[1];
    if (dir.startsWith('~/') || dir === '~') {
      dir = dir.replace('~', process.env.HOME || '/tmp');
    }
    return { workingDir: dir, cleanText: text.slice(match[0].length).trim() };
  }
  return { workingDir: null, cleanText: text };
}

function buildHelpText(): string {
  return [
    '*Claude Agent — Help*',
    '',
    '*Send a task:*',
    '• `@bot <message>` — Execute a task (new thread = new task)',
    '• Reply in a thread — Continue that conversation',
    '• `@bot pwd=/path <message>` — Run in a specific directory',
    '',
    '*Built-in commands:*',
    '• `help` — Show this help',
    '• `status` — Agent status (busy/idle, queue depth)',
    '• `cancel` — Cancel the current task',
    '• `history` — Recent conversation summaries',
    '',
    `*Default working directory:* \`${config.agent.workingDir}\``,
  ].join('\n');
}

function buildStatusText(): string {
  const status = getExecutorStatus();
  const sessions = listAgentSessions();
  const lines = [
    `*Agent Status:* ${status.busy ? 'Busy' : 'Idle'}`,
    `*Queue depth:* ${status.queueDepth}`,
    `*Active conversations:* ${sessions.length}`,
    `*Working directory:* \`${config.agent.workingDir}\``,
  ];
  if (status.currentTask) {
    lines.push(`*Current task:* thread \`${status.currentTask.threadTs}\` (started ${status.currentTask.startedAt})`);
  }
  return lines.join('\n');
}

function buildHistoryText(): string {
  const sessions = listAgentSessions();
  if (sessions.length === 0) return '_No recent conversations._';

  const lines = sessions.slice(0, 10).map((s) => {
    const exchangeCount = s.exchanges.length;
    const lastMsg = s.exchanges.length > 0
      ? s.exchanges[s.exchanges.length - 1].content.slice(0, 60)
      : '(empty)';
    return `• \`${s.channel}/${s.threadTs}\` — ${exchangeCount} exchanges — _${lastMsg}_`;
  });

  return ['*Recent Conversations:*', '', ...lines].join('\n');
}

async function handleBuiltInCommand(
  command: BuiltInCommand,
  text: string,
  channel: string,
  threadTs?: string,
): Promise<string> {
  switch (command) {
    case 'help':
      return buildHelpText();
    case 'status':
      return buildStatusText();
    case 'cancel': {
      const cancelled = cancelCurrentTask();
      return cancelled ? 'Current task cancelled.' : 'No task is currently running.';
    }
    case 'history':
      return buildHistoryText();
    case 'config':
      return 'Working directory configuration via Slack is not yet supported. Set `AGENT_WORKING_DIR` in .env or use `pwd=` prefix per-task.';
    default:
      return 'Unknown command.';
  }
}

export interface RouteMessageParams {
  text: string;
  userId: string;
  channel: string;
  messageTs: string;
  threadTs?: string;
}

export async function routeMessage(params: RouteMessageParams): Promise<void> {
  const { text, userId, channel, messageTs, threadTs } = params;

  // Check for built-in commands
  const command = parseBuiltInCommand(text);
  if (command) {
    const response = await handleBuiltInCommand(command, text, channel, threadTs);
    await replyInThread(channel, response, threadTs || messageTs);
    return;
  }

  // Parse working directory override
  const { workingDir: cwdOverride, cleanText } = parseWorkingDir(text);

  // Determine if this is a thread continuation or a new task
  const isThreadReply = !!threadTs;
  const effectiveThreadTs = threadTs || messageTs;

  // Post acknowledgment
  try {
    const ackText = getExecutorStatus().busy
      ? 'Queued — another task is running. I\'ll get to this next.'
      : 'Working on this...';
    await replyInThread(channel, ackText, effectiveThreadTs);
  } catch (err) {
    logger.error(COMPONENT, 'Failed to post acknowledgment', { error: String(err) });
  }

  // Build the task request
  let conversationHistory: string | undefined;

  if (isThreadReply) {
    const existingSession = getSession(channel, threadTs);
    if (existingSession) {
      conversationHistory = buildContextPrompt(channel, threadTs) || undefined;
    }
  }

  // Create/get session for this thread
  const session = getOrCreateSession(channel, effectiveThreadTs, cwdOverride || config.agent.workingDir);

  // Record the user message
  addExchange(channel, effectiveThreadTs, 'user', cleanText);

  const taskRequest: TaskRequest = {
    prompt: cleanText,
    workingDir: cwdOverride || session.workingDir,
    conversationHistory,
    threadTs: effectiveThreadTs,
    channel,
    messageTs,
    userId,
  };

  // Execute and post result
  const result = await executeTask(taskRequest);

  // Record the agent response
  addExchange(channel, effectiveThreadTs, 'agent', result.output);

  // Post result to Slack
  try {
    const prefix = result.timedOut ? '*Task timed out.* Partial output:\n\n' : '';
    const suffix = result.exitCode !== 0 && !result.timedOut ? '\n\n_Task exited with an error._' : '';
    await replyInThread(channel, `${prefix}${result.output}${suffix}`, effectiveThreadTs);
  } catch (err) {
    logger.error(COMPONENT, 'Failed to post result', { error: String(err) });
  }
}
